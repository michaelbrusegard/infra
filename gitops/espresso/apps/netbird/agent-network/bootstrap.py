"""Reconcile Agent Network before starting its private proxy (NetBird 0.77)."""

import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen


class NetBird:
    def __init__(self, base_url, token):
        self.base_url = base_url.rstrip("/")
        self.token = token

    def __call__(self, method, path, body=None):
        request = Request(
            self.base_url + path,
            data=None if body is None else json.dumps(body).encode(),
            headers={
                "Authorization": "Token " + self.token,
                "Content-Type": "application/json",
            },
            method=method,
        )
        try:
            with urlopen(request, timeout=30) as response:
                return json.load(response)
        except HTTPError as error:
            # Provider requests contain credentials; never print bodies or headers.
            raise RuntimeError(f"NetBird {method} {path}: HTTP {error.code}") from None


def named(items, name):
    matches = [item for item in items if item["name"] == name]
    if len(matches) > 1:
        raise RuntimeError(f"Multiple NetBird resources named {name!r}")
    return matches[0] if matches else None


def configure_provider(api, desired, upstream_key, state_path):
    path = "/agent-network/providers"
    provider = named(api("GET", path), desired["name"])
    key_digest = hashlib.sha256(upstream_key.encode()).hexdigest()
    last_digest = state_path.read_text().strip() if state_path.exists() else ""
    if provider is None:
        provider = api("POST", path, {**desired, "api_key": upstream_key})
    else:
        # Never send the CLIProxyAPI credential to a different upstream.
        if any(provider[key] != desired[key] for key in ("provider_id", "upstream_url")):
            raise RuntimeError("Existing provider points elsewhere; refusing to send credentials")
        if last_digest == key_digest:
            return provider
        # A rotated key must preserve model restrictions and every other setting
        # managed in the dashboard. These are the 0.77 provider request fields.
        fields = (
            "name", "provider_id", "upstream_url", "enabled", "models",
            "metadata_disabled", "skip_tls_verification", "extra_values",
            "identity_header_user_id", "identity_header_groups",
        )
        body = {key: provider[key] for key in fields if key in provider}
        provider = api("PUT", f"{path}/{quote(provider['id'], safe='')}", {
            **body, "api_key": upstream_key,
        })
    state_path.parent.mkdir(parents=True, exist_ok=True)
    state_path.write_text(key_digest + "\n")
    return provider


def registration_is_valid(token_path, tokens):
    try:
        token, token_id = token_path.read_text().splitlines()
    except (FileNotFoundError, ValueError):
        return False
    existing = next((item for item in tokens if item["id"] == token_id), None)
    if not token or not existing or existing["revoked"]:
        return False
    expires = existing.get("expires_at")
    return not expires or (
        datetime.fromisoformat(expires.replace("Z", "+00:00"))
        > datetime.now(timezone.utc)
    )


def reconcile(api, config, upstream_key, token_path):
    groups = {group["name"]: group["id"] for group in api("GET", "/groups")}
    required = set(config["source_groups"])
    missing = required - groups.keys()
    if missing:
        raise RuntimeError("Waiting for OpenTofu groups: " + ", ".join(sorted(missing)))

    settings = api("GET", "/agent-network/settings")
    endpoint = config["endpoint"]
    if not settings["endpoint"]:
        api("POST", "/agent-network/settings", {
            "endpoint": endpoint,
            "enable_log_collection": True,
            "enable_prompt_collection": False,
            "access_log_retention_days": 30,
            "redact_pii": True,
        })
    elif settings["endpoint"] != endpoint or settings["proxy_address"] != endpoint:
        raise RuntimeError("An existing Agent Network endpoint differs; refusing to replace it")

    provider = configure_provider(
        api, config["provider"], upstream_key, token_path.with_name("provider-key.sha256"),
    )
    # Seed the policy once. Dashboard edits, including disabling access, survive
    # proxy restarts and certificate/key rotation.
    if named(api("GET", "/agent-network/policies"), "Shared AI Access") is None:
        api("POST", "/agent-network/policies", {
            "name": "Shared AI Access",
            "description": "Allow AI users and admins to use CLIProxyAPI over NetBird",
            "enabled": True,
            "source_groups": [groups[name] for name in config["source_groups"]],
            "destination_provider_ids": [provider["id"]],
            "guardrail_ids": [],
        })

    # Proxy tokens are returned only once. Keep one on the PVC, reuse it on
    # restarts, and recreate it if it has been revoked or expired server-side.
    tokens = api("GET", "/reverse-proxies/proxy-tokens")
    if registration_is_valid(token_path, tokens):
        print("Agent Network reconciled; reusing proxy registration")
        return
    created = api("POST", "/reverse-proxies/proxy-tokens", {
        "name": "espresso-agent-network", "expires_in": 0,
    })
    token_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = token_path.with_suffix(".tmp")
    # chmod before writing, including when recovering a previous partial write.
    with open(temporary, "w", opener=lambda p, flags: os.open(p, flags, 0o600)) as out:
        os.chmod(temporary, 0o600)
        out.write(created["plain_token"] + "\n" + created["id"] + "\n")
        out.flush()
        os.fsync(out.fileno())
    temporary.replace(token_path)
    print("Agent Network reconciled; saved proxy registration")


def main():
    config = json.loads(Path("/config/config.json").read_text())
    api = NetBird(os.environ["NETBIRD_API_URL"], os.environ["NETBIRD_API_TOKEN"])
    reconcile(api, config, os.environ["UPSTREAM_API_KEY"], Path("/state/proxy-token"))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Agent Network bootstrap failed: {error}", file=sys.stderr)
        sys.exit(1)
