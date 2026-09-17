"""Check edge guards and SMTP boundaries without submitting mail.

Registry checks alone do not prove the running configuration was reloaded.
This also probes SMTP, but it is not a substitute for the isolated acceptance
suite or a controlled restart after listener/lookup changes.
"""

from __future__ import annotations

import http.client
import json
import os
from pathlib import Path
import smtplib
import socket
import ssl
import sys

HOST = "edge.asgard.michaelbrusegard.com"
INTERNAL_DOMAIN = "system.edge.asgard.michaelbrusegard.com"
DOMAIN = "manafishrov.com"
OBJECTS = (
    "Domain", "Account", "Directory", "NetworkListener", "SieveSystemScript",
    "MtaHook", "StoreLookup", "MtaRoute",
)
SINGLETONS = (
    "Authentication", "MtaStageRcpt", "MtaStageAuth", "MtaOutboundStrategy", "Http",
)
FILTERING_SINGLETONS = ("MtaStageData", "SenderAuth")
AUTH_VERDICT_NAME = "edge-auth-verdict"
AUTH_VERDICT_PATH = Path(__file__).with_name("auth-verdict.sieve")
READINESS_PERMISSIONS = ["authenticate"] + [
    "sys" + kind + operation
    for kind in OBJECTS
    for operation in ("Query", "Get")
] + ["sys" + kind + "Get" for kind in SINGLETONS + FILTERING_SINGLETONS]


def require(condition):
    if not condition:
        raise RuntimeError("edge readiness invariant failed")


class LoopbackHTTPS(http.client.HTTPSConnection):
    def connect(self):
        raw = socket.create_connection(("127.0.0.1", 443), self.timeout)
        try:
            self.sock = self._context.wrap_socket(raw, server_hostname=HOST)
        except Exception:
            raw.close()
            raise


def filtering_stage():
    stage = os.environ.get("STALWART_EDGE_FILTERING_STAGE", "legacy")
    require(stage in ("legacy", "prepare", "backend"))
    return stage


def read_registry():
    # Existing credentials keep working until the explicit permission upgrade.
    singletons = SINGLETONS + (FILTERING_SINGLETONS if filtering_stage() != "legacy" else ())
    calls = []
    for kind in OBJECTS:
        calls.extend([
            [f"x:{kind}/query", {"limit": 100, "calculateTotal": True}, kind + "Query"],
            [f"x:{kind}/get", {"#ids": {"resultOf": kind + "Query",
              "name": f"x:{kind}/query", "path": "/ids"}}, kind],
        ])
    calls.extend([f"x:{kind}/get", {"ids": ["singleton"]}, kind]
                 for kind in singletons)
    responses = []
    # Keep each query/get pair together, below the native per-request call cap.
    for offset in range(0, len(calls), 8):
        conn = LoopbackHTTPS(HOST, timeout=3, context=ssl.create_default_context())
        try:
            conn.request("POST", "/jmap", json.dumps({
                "using": ["urn:ietf:params:jmap:core", "urn:stalwart:jmap"],
                "methodCalls": calls[offset:offset + 8],
            }), {"Content-Type": "application/json",
                 "Authorization": "Bearer " + os.environ["STALWART_EDGE_READINESS_TOKEN"]})
            response = conn.getresponse()
            require(response.status == 200)
            body = response.read(1024 * 1024 + 1)
            require(len(body) <= 1024 * 1024)
            responses.extend(json.loads(body)["methodResponses"])
        finally:
            conn.close()
    expected = {call[2]: call[0] for call in calls}
    result = {}
    for method, value, tag in responses:
        require(tag in expected and tag not in result and method == expected[tag])
        result[tag] = value
    require(set(result) == set(expected))
    for kind in OBJECTS:
        query, rows = result[kind + "Query"], result[kind]
        require(query.get("position", 0) == 0)
        require(query.get("total") == len(query["ids"]) < 100)
        require(not rows.get("notFound"))
        require({row["id"] for row in rows["list"]} == set(query["ids"]))
    for kind in singletons:
        require(not result[kind].get("notFound"))
        require(len(result[kind]["list"]) == 1)
    return {kind: result[kind]["list"] for kind in OBJECTS + singletons}


def expression(value, otherwise, matches=()):
    require(isinstance(value, dict) and value.get("else") == otherwise)
    actual = value.get("match") or {}
    if isinstance(actual, dict):
        actual = [actual[key] for key in sorted(actual, key=int)]
    require(actual == [{"if": condition, "then": outcome} for condition, outcome in matches])


def enabled_keys(value):
    if isinstance(value, dict):
        return {key for key, enabled in value.items() if enabled}
    return set(value or [])


def check_filtering(objects):
    """Allow only the enumerated rollout states; never filter-off without metadata."""
    stage = filtering_stage()
    rows = objects["SieveSystemScript"]
    scripts = {row["name"]: row for row in rows}
    require(len(scripts) == len(rows))
    guard = {"edge-rcpt-domain-guard"}
    if stage == "legacy":
        require(set(scripts) == guard)
        return scripts

    require(set(scripts) in (guard, guard | {AUTH_VERDICT_NAME}))
    auth = scripts.get(AUTH_VERDICT_NAME)
    if auth is not None:
        require(auth["isActive"] is True)
        require(auth["contents"].strip() == AUTH_VERDICT_PATH.read_text().strip())
    data = objects["MtaStageData"][0]
    script = data["script"]
    if script.get("else") == "false":
        require(stage == "prepare")
        expression(script, "false")
        expression(data["enableSpamFilter"], "local_port == 25")
    else:
        require(auth is not None)
        expression(script, repr(AUTH_VERDICT_NAME))
        enabled = data["enableSpamFilter"].get("else")
        require(enabled in (("local_port == 25", "false") if stage == "prepare" else ("false",)))
        expression(data["enableSpamFilter"], enabled)
    sender = objects["SenderAuth"][0]
    for field in ("spfEhloVerify", "spfFromVerify", "dkimVerify", "dmarcVerify", "reverseIpVerify"):
        expression(sender[field], "relaxed")
    expression(sender["dkimSignDomain"], "false")
    return scripts


def check_registry(objects):
    require(not objects["Directory"])
    domains = objects["Domain"]
    require(len(domains) == 1 and domains[0]["name"] == INTERNAL_DOMAIN)
    require(not domains[0].get("aliases") and not domains[0].get("directoryId"))
    require(not domains[0].get("catchAllAddress") and not domains[0].get("allowRelaying"))
    accounts = objects["Account"]
    require({row["name"] for row in accounts} == {"tofu", "readiness"} and len(accounts) == 2)
    for row in accounts:
        require(row["@type"] == "User" and row["domainId"] == domains[0]["id"])
        require(row.get("roles") == {"@type": "User"})
        require(row.get("permissions", {}).get("@type") == "Replace")
        require(not row.get("aliases") and not row.get("memberGroupIds"))
        credentials = row.get("credentials") or {}
        for credential in credentials.values():
            require(credential["@type"] == "ApiKey")
    require(not objects["Authentication"][0].get("directoryId"))
    require(objects["Http"][0].get("useXForwarded") is False)

    listeners = {row["name"]: row for row in objects["NetworkListener"]}
    require(set(listeners) == {"https", "smtp"})
    for name, port in (("https", 443), ("smtp", 25)):
        row = listeners[name]
        require(row["protocol"] == ("http" if name == "https" else "smtp"))
        require(enabled_keys(row["bind"]) == {f"[::]:{port}"})
        require(row["useTls"] is True and row["tlsImplicit"] is (name == "https"))
        require(not row.get("overrideProxyTrustedNetworks"))

    scripts = check_filtering(objects)
    script = scripts["edge-rcpt-domain-guard"]
    require(script["name"] == "edge-rcpt-domain-guard" and script["isActive"] is True)
    expected = ('require ["envelope", "reject"];\n'
                'if not envelope :domain :is "to" "manafishrov.com" {\n'
                '  reject "550 5.7.1 Recipient domain is not served by this edge";\n}')
    require(script["contents"].strip() == expected)
    hooks = objects["MtaHook"]
    require(len(hooks) == 1)
    hook = hooks[0]
    require(hook["url"] == "http://127.0.0.1:8090/rcpt")
    require(enabled_keys(hook["stages"]) == {"rcpt"})
    require(hook["tempFailOnError"] is True and hook["timeout"] == 5000)
    expression(hook["enable"], "true")
    stores = objects["StoreLookup"]
    require(len(stores) == 1 and stores[0]["namespace"] == "edge-recipients")
    require(stores[0]["store"]["@type"] == "Sqlite")
    require(stores[0]["store"]["path"] == "/var/lib/stalwart/routing/recipients.sqlite3")
    query = Path(__file__).with_name("policy.sql").read_text().strip()
    require('"' not in query and "\\" not in query)
    rcpt = objects["MtaStageRcpt"][0]
    expression(rcpt["allowRelaying"], "false", [(f"rcpt_domain == '{DOMAIN}'",
               f'sql_query(\'edge-recipients\', "{query}", [rcpt]) == 1')])
    expression(rcpt["script"], "'edge-rcpt-domain-guard'")
    expression(rcpt["rewrite"], "false")
    auth = objects["MtaStageAuth"][0]
    expression(auth["require"], "false")
    expression(auth["saslMechanisms"], "false")
    expression(objects["MtaOutboundStrategy"][0]["route"], "'edge-dsn-resend'",
               [(f"rcpt_domain == '{DOMAIN}'", "'to-manafishrov'")])
    routes = {row["name"]: row for row in objects["MtaRoute"]}
    require(set(routes) == {"to-manafishrov", "edge-dsn-resend"})
    for name, host, port, protocol in (
        ("to-manafishrov", "backend.manafishrov.com", 24, "lmtp"),
        ("edge-dsn-resend", "smtp.resend.com", 465, "smtp"),
    ):
        row = routes[name]
        require(row["@type"] == "Relay" and row["address"] == host)
        require(row["port"] == port and row["protocol"] == protocol)
        require(row["implicitTls"] is True and row["allowInvalidCerts"] is False)


def check_smtp():
    with smtplib.SMTP("127.0.0.1", 25, timeout=3) as conn:
        require(conn.ehlo("edge-readiness.invalid")[0] == 250)
        require(not conn.has_extn("auth") and conn.has_extn("starttls"))
        # smtplib uses this name for TLS SNI and hostname verification.
        conn._host = HOST
        require(conn.starttls(context=ssl.create_default_context())[0] == 220)
        require(conn.ehlo("edge-readiness.invalid")[0] == 250)
        require(not conn.has_extn("auth"))
        require(conn.mail("")[0] == 250)
        for address in ("outside@unserved.invalid", f"tofu@{INTERNAL_DOMAIN}",
                        f"readiness@{INTERNAL_DOMAIN}"):
            require(conn.rcpt(address)[0] == 550)
        conn.rset()
        # Intentionally no DATA, including when a probe unexpectedly succeeds.


def main():
    try:
        require(Path("/var/lib/stalwart/.bootstrapped").is_file())
        require(os.environ.get("STALWART_EDGE_POLICY_QUALIFIED") == "1")
        conn = http.client.HTTPConnection("127.0.0.1", 8090, timeout=2)
        try:
            conn.request("GET", "/healthz")
            require(conn.getresponse().status == 200)
        finally:
            conn.close()
        check_registry(read_registry())
        check_smtp()
        return 0
    except Exception:
        # Do not expose account objects, authorization headers or API responses.
        print("stalwart-edge readiness checks failed", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
