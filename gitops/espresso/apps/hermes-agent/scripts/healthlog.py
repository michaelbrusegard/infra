#!/usr/bin/env python3
"""Context-efficient, read-only CLI for the HealthLog MCP endpoint."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from contextlib import AsyncExitStack
from datetime import timedelta
from typing import Any

import httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client


WINDOWS = ("last7days", "last30days", "last90days", "lastYear", "allTime")


def compact(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, separators=(",", ":")))


def safe_error(exc: BaseException) -> str:
    current = exc
    while isinstance(current, BaseExceptionGroup) and current.exceptions:
        current = current.exceptions[0]
    message = str(current)
    token = os.environ.get("HEALTHLOG_MCP_TOKEN", "")
    if token:
        message = message.replace(token, "[REDACTED]")
    return f"{type(current).__name__}: {message[:300]}"


def optional(mapping: dict[str, Any], key: str, value: Any) -> None:
    if value is not None:
        mapping[key] = value


def date_range(start: str | None, end: str | None, label: str) -> dict[str, str] | None:
    if start is None and end is None:
        return None
    if start is None or end is None:
        raise ValueError(f"{label} requires both start and end dates")
    return {"from": start, "to": end}


def request_for(args: argparse.Namespace) -> tuple[str, str, dict[str, Any]]:
    command = args.command
    if command == "inventory":
        return "tool", "list_metrics", {}
    if command == "metric":
        if len(args.metrics) > 24:
            raise ValueError("metric accepts at most 24 metrics per request")
        payload: dict[str, Any] = {"window": args.window}
        if len(args.metrics) == 1:
            payload["metric"] = args.metrics[0]
            return "tool", "get_metric_series", payload
        payload["metrics"] = args.metrics
        optional(payload, "cursor", args.cursor)
        return "tool", "get_metrics", payload
    if command == "baseline":
        return "tool", "get_metric_baseline", {"metric": args.metric}
    if command == "compare":
        payload = {"metric": args.metric, "window": args.window}
        optional(payload, "metricB", args.metric_b)
        optional(payload, "windowB", args.window_b)
        optional(payload, "range", date_range(args.start, args.end, "first range"))
        optional(payload, "rangeB", date_range(args.start_b, args.end_b, "second range"))
        return "tool", "compare_metric", payload
    if command == "changes":
        payload = {"metric": args.metric, "window": args.window}
        optional(payload, "range", date_range(args.start, args.end, "range"))
        return "tool", "detect_changepoints", payload
    if command in {"sleep", "workouts", "glucose"}:
        tool = {
            "sleep": "get_sleep",
            "workouts": "get_workouts",
            "glucose": "get_glucose_panel",
        }[command]
        return "tool", tool, {"window": args.window}
    if command == "labs":
        if args.history and not args.analyte:
            raise ValueError("labs --history requires --analyte")
        payload = {}
        optional(payload, "analyte", args.analyte)
        if args.history:
            payload["history"] = True
        optional(payload, "cursor", args.cursor)
        return "tool", "get_labs", payload
    if command == "medications":
        if args.schedule:
            return "tool", "get_medication_schedule", {}
        return "tool", "get_medication_compliance", {"window": args.window}
    if command == "recovery":
        return "tool", "get_illness_recovery", {}
    if command == "correlations":
        if args.metric_a or args.metric_b:
            if not args.metric_a or not args.metric_b:
                raise ValueError("named correlation requires --metric-a and --metric-b")
            return "tool", "get_correlation", {
                "metricA": args.metric_a,
                "metricB": args.metric_b,
            }
        return "tool", "get_correlations", {}
    if command == "integrations":
        return "tool", "get_integration_status", {}
    if command == "preventive":
        return "tool", "get_preventive_care", {}
    if command == "nutrients":
        payload = {}
        optional(payload, "nutrient", args.nutrient)
        optional(payload, "days", args.days)
        return "tool", "get_nutrients", payload
    if command == "pulse":
        payload = {}
        optional(payload, "date", args.date)
        return "tool", "get_intraday_pulse", payload
    if command == "ecg":
        return "tool", "get_ecg_recordings", {}
    if command == "visits":
        payload = {}
        optional(payload, "months", args.months)
        optional(payload, "practitioner", args.practitioner)
        return "tool", "get_visits", payload
    if command == "search":
        payload = {"query": args.query}
        optional(payload, "cursor", args.cursor)
        return "tool", "search", payload
    if command == "fetch":
        return "tool", "fetch", {"id": args.id}
    if command == "review":
        prompt = {
            "doctor": "doctor_visit_summary",
            "weekly": "weekly_review",
            "medication": "medication_check",
            "recovery": "recovery_check",
            "glucose": "glucose_review",
            "sleep": "sleep_review",
            "labs": "lab_trend_brief",
        }[args.review]
        payload = {}
        if args.review == "labs":
            optional(payload, "analyte", args.analyte)
        else:
            optional(payload, "window", args.window)
        if args.review == "medication":
            optional(payload, "medication", args.medication)
            optional(payload, "metric", args.metric)
        return "prompt", prompt, payload
    raise ValueError(f"unsupported command: {command}")


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="healthlog",
        description="Read the current user's HealthLog record through an allowlisted CLI.",
    )
    sub = p.add_subparsers(dest="command", required=True)

    sub.add_parser("inventory", help="show which health domains contain data")

    metric = sub.add_parser("metric", help="read one or more metric series")
    metric.add_argument("metrics", nargs="+")
    metric.add_argument("--window", choices=WINDOWS, default="last30days")
    metric.add_argument("--cursor")

    baseline = sub.add_parser("baseline", help="read a metric's personal baseline")
    baseline.add_argument("metric")

    compare = sub.add_parser("compare", help="compare metrics or date windows")
    compare.add_argument("metric")
    compare.add_argument("--metric-b")
    compare.add_argument("--window", choices=WINDOWS, default="last30days")
    compare.add_argument("--window-b", choices=WINDOWS)
    compare.add_argument("--start", help="first range start, YYYY-MM-DD")
    compare.add_argument("--end", help="first range end, YYYY-MM-DD")
    compare.add_argument("--start-b", help="second range start, YYYY-MM-DD")
    compare.add_argument("--end-b", help="second range end, YYYY-MM-DD")

    changes = sub.add_parser("changes", help="detect level shifts in a metric")
    changes.add_argument("metric")
    changes.add_argument("--window", choices=WINDOWS, default="last90days")
    changes.add_argument("--start", help="range start, YYYY-MM-DD")
    changes.add_argument("--end", help="range end, YYYY-MM-DD")

    for name in ("sleep", "workouts", "glucose"):
        item = sub.add_parser(name, help=f"read {name} data")
        item.add_argument("--window", choices=WINDOWS, default="last30days")

    labs = sub.add_parser("labs", help="read labs or one analyte's history")
    labs.add_argument("--analyte")
    labs.add_argument("--history", action="store_true")
    labs.add_argument("--cursor")

    medications = sub.add_parser("medications", help="read adherence or schedule")
    medications.add_argument("--window", choices=WINDOWS, default="last30days")
    medications.add_argument("--schedule", action="store_true")

    sub.add_parser("recovery", help="read illness and recovery context")
    correlations = sub.add_parser("correlations", help="read discovered or named correlations")
    correlations.add_argument("--metric-a")
    correlations.add_argument("--metric-b")
    sub.add_parser("integrations", help="read device and service sync status")
    sub.add_parser("preventive", help="read preventive-care reminders and visits")

    nutrients = sub.add_parser("nutrients", help="read nutrient intake")
    nutrients.add_argument("--nutrient")
    nutrients.add_argument("--days", type=int, choices=range(1, 366), metavar="1..365")

    pulse = sub.add_parser("pulse", help="read one day's intraday pulse shape")
    pulse.add_argument("--date", help="YYYY-MM-DD in the user's timezone")
    sub.add_parser("ecg", help="read ECG metadata; waveforms are never exposed")

    visits = sub.add_parser("visits", help="read past doctor visits")
    visits.add_argument("--months", type=int, choices=range(1, 61), metavar="1..60")
    visits.add_argument("--practitioner")

    search = sub.add_parser("search", help="search metrics, medications, and labs")
    search.add_argument("query")
    search.add_argument("--cursor")
    fetch = sub.add_parser("fetch", help="fetch an id returned by search")
    fetch.add_argument("id")

    review = sub.add_parser("review", help="run a server-grounded prepared review")
    review.add_argument(
        "review",
        choices=("doctor", "weekly", "medication", "recovery", "glucose", "sleep", "labs"),
    )
    review.add_argument("--window", choices=WINDOWS)
    review.add_argument("--analyte")
    review.add_argument("--medication")
    review.add_argument("--metric")
    return p


def tool_payload(result: Any) -> Any:
    structured = getattr(result, "structuredContent", None)
    if structured is not None:
        return structured
    texts = [item.text for item in result.content if hasattr(item, "text")]
    if len(texts) == 1:
        try:
            return json.loads(texts[0])
        except json.JSONDecodeError:
            return {"text": texts[0]}
    return result.model_dump(mode="json", exclude_none=True)


async def run(kind: str, name: str, arguments: dict[str, Any]) -> Any:
    url = os.environ.get(
        "HEALTHLOG_MCP_URL",
        "http://healthlog.healthlog.svc.cluster.local:3000/mcp",
    )
    token = os.environ.get("HEALTHLOG_MCP_TOKEN", "").strip()
    if not token:
        raise RuntimeError("HEALTHLOG_MCP_TOKEN is not configured")

    timeout = httpx.Timeout(45.0, connect=5.0)
    async with AsyncExitStack() as stack:
        client = await stack.enter_async_context(
            httpx.AsyncClient(
                headers={"Authorization": f"Bearer {token}"},
                timeout=timeout,
                follow_redirects=False,
            )
        )
        read_stream, write_stream, _ = await stack.enter_async_context(
            streamable_http_client(
                url,
                http_client=client,
                # HealthLog's endpoint is explicitly stateless. A DELETE on
                # close has no session to terminate and only adds a failing
                # cleanup round-trip after a successful read.
                terminate_on_close=False,
            )
        )
        session = await stack.enter_async_context(
            ClientSession(
                read_stream,
                write_stream,
                read_timeout_seconds=timedelta(seconds=45),
            )
        )
        await session.initialize()
        if kind == "tool":
            return tool_payload(await session.call_tool(name, arguments))
        result = await session.get_prompt(name, {k: str(v) for k, v in arguments.items()})
        return result.model_dump(mode="json", exclude_none=True)


def main() -> int:
    try:
        args = parser().parse_args()
        kind, name, arguments = request_for(args)
        compact(asyncio.run(run(kind, name, arguments)))
        return 0
    except (ValueError, RuntimeError) as exc:
        print(f"healthlog: {exc}", file=sys.stderr)
        return 2
    except Exception as exc:
        print(f"healthlog: request failed: {safe_error(exc)}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
