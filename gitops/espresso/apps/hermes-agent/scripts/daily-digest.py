#!/usr/bin/env python3
"""Collect a bounded, machine-readable Espresso cluster health snapshot."""

import json
import subprocess
from datetime import datetime, timedelta, timezone


NOW = datetime.now(timezone.utc)
RECENT = NOW - timedelta(hours=24)


def run(*args: str) -> str:
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            check=False,
            text=True,
            timeout=30,
        )
    except Exception as error:
        return f"ERROR: {error}"
    if result.returncode != 0:
        detail = result.stderr.strip() or f"exit {result.returncode}"
        return f"ERROR: {detail}"
    return result.stdout.strip()


def kubectl_json(*args: str) -> dict:
    output = run("kubectl", *args, "-o", "json")
    try:
        return json.loads(output)
    except (TypeError, json.JSONDecodeError):
        return {"error": output or "empty response"}


def timestamp(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def age(value: datetime | None) -> str:
    if value is None:
        return "unknown age"
    seconds = max(0, int((NOW - value).total_seconds()))
    if seconds < 3600:
        return f"{max(1, seconds // 60)}m ago"
    if seconds < 86400:
        return f"{seconds // 3600}h ago"
    return f"{seconds // 86400}d ago"


def condition_status(item: dict, condition_type: str) -> str:
    for condition in item.get("status", {}).get("conditions", []):
        if condition.get("type") == condition_type:
            return condition.get("status", "Unknown")
    return "Unknown"


def print_section(name: str, lines: list[str]) -> None:
    print(f"\n{name}")
    print("\n".join(lines or ["  none"]))


def main() -> None:
    errors: list[str] = []
    current_issues: list[str] = []

    print(f"COLLECTED_AT {NOW.isoformat()}")
    print("WINDOW 24h (historical counters alone are not issues)")

    nodes = kubectl_json("get", "nodes")
    node_lines: list[str] = []
    if "error" in nodes:
        errors.append(f"nodes: {nodes['error']}")
    else:
        for node in nodes.get("items", []):
            name = node["metadata"]["name"]
            ready = condition_status(node, "Ready")
            status = "Ready" if ready == "True" else "NotReady"
            node_lines.append(f"  {name}: {status}")
            if status != "Ready":
                current_issues.append(f"node {name} is {status}")

    top_output = run("kubectl", "top", "nodes", "--no-headers")
    if top_output.startswith("ERROR:"):
        errors.append(f"node metrics: {top_output}")
    else:
        metrics = {}
        for line in top_output.splitlines():
            fields = line.split()
            if len(fields) >= 5:
                metrics[fields[0]] = f"CPU {fields[2]}, memory {fields[4]}"
        node_lines = [f"{line} ({metrics[line.split(':', 1)[0].strip()]})" if line.split(':', 1)[0].strip() in metrics else line for line in node_lines]
    print_section("NODES", node_lines)

    pods = kubectl_json("get", "pods", "-A")
    pod_count = 0
    recent_restarts: list[str] = []
    if "error" in pods:
        errors.append(f"pods: {pods['error']}")
    else:
        pod_count = len(pods.get("items", []))
        for pod in pods.get("items", []):
            namespace = pod["metadata"]["namespace"]
            name = pod["metadata"]["name"]
            phase = pod.get("status", {}).get("phase", "Unknown")
            statuses = pod.get("status", {}).get("containerStatuses", [])
            ready = all(status.get("ready", False) for status in statuses) if statuses else False
            completed = phase == "Succeeded"
            if phase != "Running" and not completed:
                current_issues.append(f"pod {namespace}/{name} is {phase}")
            elif phase == "Running" and not ready:
                current_issues.append(f"pod {namespace}/{name} is not Ready")

            for status in statuses:
                last = status.get("lastState", {}).get("terminated", {})
                finished = timestamp(last.get("finishedAt"))
                if status.get("restartCount", 0) and finished and finished >= RECENT:
                    recent_restarts.append(
                        f"  {namespace}/{name} container {status['name']}: "
                        f"{status['restartCount']} total, last {age(finished)} "
                        f"({last.get('reason', 'unknown')}, exit {last.get('exitCode', '?')})"
                    )

    pod_issue_count = sum(item.startswith("pod ") for item in current_issues)
    print_section("PODS", [f"  {pod_count} observed", f"  current issues: {pod_issue_count}"])
    print_section("RECENT_RESTARTS", recent_restarts)

    pvcs = kubectl_json("get", "pvc", "-A")
    if "error" in pvcs:
        errors.append(f"PVCs: {pvcs['error']}")
    else:
        for pvc in pvcs.get("items", []):
            phase = pvc.get("status", {}).get("phase", "Unknown")
            if phase != "Bound":
                current_issues.append(
                    f"PVC {pvc['metadata']['namespace']}/{pvc['metadata']['name']} is {phase}"
                )

    jobs = kubectl_json("get", "jobs", "-A")
    if "error" in jobs:
        errors.append(f"jobs: {jobs['error']}")
    else:
        for job in jobs.get("items", []):
            namespace = job["metadata"]["namespace"]
            name = job["metadata"]["name"]
            status = job.get("status", {})
            if status.get("failed", 0) > 0 and status.get("succeeded", 0) == 0:
                current_issues.append(f"job {namespace}/{name} has failed")

    flux_lines: list[str] = []
    for resource, label in (("kustomizations", "kustomizations"), ("helmreleases", "Helm releases")):
        data = kubectl_json("get", resource, "-A")
        if "error" in data:
            errors.append(f"Flux {label}: {data['error']}")
            continue
        items = data.get("items", [])
        failed = []
        for item in items:
            ready = condition_status(item, "Ready")
            if ready != "True":
                identifier = f"{item['metadata']['namespace']}/{item['metadata']['name']}"
                failed.append(identifier)
                current_issues.append(f"Flux {resource[:-1]} {identifier} is not Ready")
        flux_lines.append(f"  {len(items)} {label}: {'OK' if not failed else 'not Ready: ' + ', '.join(failed)}")
    print_section("GITOPS", flux_lines)

    events = kubectl_json("get", "events", "-A", "--field-selector", "type=Warning")
    warning_lines: list[str] = []
    if "error" in events:
        errors.append(f"warning events: {events['error']}")
    else:
        recent_events = []
        for event in events.get("items", []):
            event_time = timestamp(
                event.get("eventTime")
                or event.get("series", {}).get("lastObservedTime")
                or event.get("lastTimestamp")
                or event["metadata"].get("creationTimestamp")
            )
            if event_time and event_time >= RECENT:
                recent_events.append((event_time, event))
        for event_time, event in sorted(recent_events, key=lambda item: item[0]):
            regarding = event.get("regarding") or event.get("involvedObject") or {}
            message = event.get("note") or event.get("message") or "no detail"
            line = (
                f"  {age(event_time)} {event['metadata']['namespace']} "
                f"{event.get('reason', 'Warning')} {regarding.get('kind', '?')}/"
                f"{regarding.get('name', '?')}: {message}"
            )
            warning_lines.append(line)
    print_section("RECENT_WARNING_EVENTS", warning_lines)

    print_section("CURRENT_ISSUES", [f"  {item}" for item in current_issues])
    print_section("COLLECTION_ERRORS", [f"  {item}" for item in errors])


if __name__ == "__main__":
    main()
