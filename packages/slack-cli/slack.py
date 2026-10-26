#!/usr/bin/env python3
"""slack: a Slack Web API CLI for Michael and his coding agents.

Single file, standard library only. Auth is the xoxp user token of the
internal `slack-cli` app, read from the sops-nix secret keys/slack-token.
The token is never printed, logged, or written anywhere.
"""

import argparse
import concurrent.futures
import datetime as dt
import difflib
import html
import html.parser
import http.client
import json
import os
import re
import socket
import ssl
import sys
import tempfile
import threading
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

VERSION = "2.0.0"
API_BASE = "https://slack.com/api/"
TOKEN_FILE = os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
    "sops-nix",
    "secrets",
    "keys",
    "slack-token",
)
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "slack-cli")
DRY_ENV = "SLACK_CLI_DRY_RUN"
MANIFEST_HINT = "packages/slack-cli/manifest.json in Michael's infra repo"
TTL = {
    "team": 7 * 86400,
    "users": 86400,
    "conversations": 6 * 3600,
    "usergroups": 86400,
}
WORKERS = 8

# Methods that never change state. Anything else is treated as a write: it
# is not retried after an ambiguous timeout and SLACK_CLI_DRY_RUN=1
# intercepts it.
READ_METHOD_RE = re.compile(
    r"(^auth\.test$|^search\.|^assistant\.search\.|^users\.conversations$|^users\.profile\.get$"
    r"|^users\.lookupByEmail$|\.list$|\.info$|\.history$|\.replies$|\.members$"
    r"|\.get$|\.getPermalink$|\.lookup$)"
)

ID_CONV_RE = re.compile(r"^[CDG][A-Z0-9]{8,}$")
ID_USER_RE = re.compile(r"^[UW][A-Z0-9]{8,}$")
ID_FILE_RE = re.compile(r"^F[A-Z0-9]{8,}$")
TS_RE = re.compile(r"^\d{9,10}\.\d{1,6}$")
PTS_RE = re.compile(r"^p(\d{10})(\d{6})$")
BROADCAST_RE = re.compile(
    r"<!(here|channel|everyone)(\|[^>]*)?>|(?<![\w`/])@(here|channel|everyone)\b",
    re.IGNORECASE,
)
FOOTER_RE = re.compile(r"responding on behalf of Michael\s*$")
TEXT_MIME_RE = re.compile(
    r"^(text/|application/(json|xml|x-yaml|yaml|javascript|x-sh|x-python|toml|sql|csv|x-ndjson))"
)
TEXT_FILETYPES = {
    "text", "markdown", "md", "json", "yaml", "yml", "csv", "tsv", "xml", "html",
    "javascript", "typescript", "python", "shell", "bash", "go", "rust", "nix",
    "sql", "diff", "patch", "log", "toml", "ini", "c", "cpp", "java", "kotlin",
    "swift", "ruby", "php", "css", "scss", "dockerfile", "makefile", "post",
}  # fmt: skip


class SlackError(Exception):
    """A failure to report as a one-line error."""


class UsageError(Exception):
    """Bad command-line usage."""

    def __init__(self, msg, command=None):
        super().__init__(msg)
        self.command = command


def warn(msg):
    print(f"slack: {msg}", file=sys.stderr)


# --------------------------------------------------------------------------
# HTTP client
# --------------------------------------------------------------------------


def slack_host(host):
    host = (host or "").lower()
    return host == "slack.com" or host.endswith((".slack.com", ".slack-edge.com", ".slackb.com"))


class _SafeRedirect(urllib.request.HTTPRedirectHandler):
    """Follow redirects but never forward the token off Slack hosts."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is not None and not slack_host(urllib.parse.urlsplit(newurl).hostname):
            new.remove_header("Authorization")
        return new


def _encode_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (list, dict)):
        return json.dumps(value, separators=(",", ":"))
    return str(value)


def _fake_response(method, params):
    """Plausible response for SLACK_CLI_DRY_RUN=1 so multi-step flows continue."""
    p = params or {}
    chan = p.get("channel") or p.get("channel_id") or "C0DRYRUN0"
    fake = {"ok": True, "dry_run": True}
    if method in ("chat.postMessage", "chat.update", "chat.scheduleMessage"):
        fake.update(
            channel=chan if not str(chan).startswith(("U", "W")) else "D0DRYRUN0",
            ts=p.get("ts") or "1000000000.000001",
            scheduled_message_id="Q0DRYRUN0",
            post_at=p.get("post_at"),
        )
    elif method == "files.getUploadURLExternal":
        fake.update(upload_url="https://files.slack.com/upload/v1/DRYRUN", file_id="F0DRYRUN0")
    elif method == "files.completeUploadExternal":
        fake.update(files=[{"id": "F0DRYRUN0", "permalink": "(dry-run: no permalink)"}])
    elif method in ("conversations.open", "conversations.create", "conversations.invite"):
        fake.update(
            channel={
                "id": "C0DRYRUN0" if method != "conversations.open" else "D0DRYRUN0",
                "name": p.get("name"),
            }
        )
    elif method == "canvases.create":
        fake.update(canvas_id="F0DRYRUN0")
    elif method == "slackLists.create":
        fake.update(list_id="F0DRYRUN0")
    elif method == "slackLists.items.create":
        fake.update(item={"id": "Rec0DRYRUN0"})
    return fake


class Client:
    def __init__(self):
        self._token = None
        self.dry_env = os.environ.get(DRY_ENV) == "1"
        self.opener = urllib.request.build_opener(_SafeRedirect())
        self.last_headers = {}

    def token(self):
        if self._token is None:
            try:
                with open(TOKEN_FILE, encoding="utf-8") as f:
                    tok = f.read().strip()
            except OSError:
                raise SlackError(
                    f"no Slack token at {TOKEN_FILE} (sops-nix secret keys/slack-token)"
                ) from None
            if not tok.startswith("xox"):
                raise SlackError(f"{TOKEN_FILE} does not contain a Slack token")
            self._token = tok
        return self._token

    def _send(self, req, label, timeout, idempotent):
        attempt = 0
        limited = 0
        while True:
            try:
                resp = self.opener.open(req, timeout=timeout)
                return resp, resp.read()
            except urllib.error.HTTPError as e:
                if e.code == 429 and limited < 6:
                    limited += 1
                    try:
                        wait = float(e.headers.get("Retry-After") or 5)
                    except ValueError:
                        wait = 5.0
                    wait = min(max(wait, 1.0), 120.0)
                    warn(f"rate limited on {label}; retrying in {wait:.0f}s")
                    time.sleep(wait)
                    continue
                if 500 <= e.code < 600 and idempotent and attempt < 3:
                    attempt += 1
                    time.sleep(2**attempt / 2)
                    continue
                body = b""
                try:
                    body = e.read()
                except OSError:
                    pass
                return e, body
            except (
                urllib.error.URLError,
                socket.timeout,
                TimeoutError,
                ConnectionError,
                http.client.HTTPException,
                ssl.SSLError,
            ) as e:
                reason = getattr(e, "reason", e)
                timed_out = isinstance(reason, (socket.timeout, TimeoutError)) or "timed out" in str(reason)
                if attempt < 3 and (idempotent or not timed_out):
                    attempt += 1
                    time.sleep(2**attempt / 2)
                    continue
                if timed_out and not idempotent:
                    raise SlackError(
                        f"timed out calling {label}; the write may or may not have happened, "
                        "check before retrying"
                    ) from None
                raise SlackError(f"network error calling {label}: {reason}") from None

    def call(self, method, params=None, json_body=False, allow_error=False, timeout=30):
        """Call a Web API method. Returns the decoded JSON response."""
        params = {k: v for k, v in (params or {}).items() if v is not None}
        write = not READ_METHOD_RE.search(method)
        if write and self.dry_env:
            print(
                f"[{DRY_ENV}] would call {method} " + json.dumps(params, ensure_ascii=False, sort_keys=True),
                file=sys.stderr,
            )
            return _fake_response(method, params)
        headers = {"Authorization": "Bearer " + self.token(), "User-Agent": f"slack-cli/{VERSION}"}
        if json_body:
            data = json.dumps(params).encode()
            headers["Content-Type"] = "application/json; charset=utf-8"
        else:
            data = urllib.parse.urlencode({k: _encode_value(v) for k, v in params.items()}).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        req = urllib.request.Request(API_BASE + method, data=data, headers=headers, method="POST")
        resp, body = self._send(req, method, timeout, idempotent=not write)
        self.last_headers = dict(resp.headers.items()) if resp.headers else {}
        try:
            payload = json.loads(body.decode("utf-8", "replace"))
        except ValueError:
            status = getattr(resp, "status", None) or getattr(resp, "code", "?")
            raise SlackError(f"{method}: unexpected non-JSON response (HTTP {status})") from None
        if not payload.get("ok") and not allow_error:
            raise SlackError(format_api_error(method, payload))
        return payload

    def paginate(self, method, params, key, limit=None, page_size=200):
        """Yield items from a cursor-paginated method."""
        params = dict(params)
        count = 0
        while True:
            want = page_size if limit is None else max(1, min(page_size, limit - count))
            params["limit"] = want
            data = self.call(method, params)
            items = data.get(key) or []
            for item in items:
                yield item
                count += 1
                if limit is not None and count >= limit:
                    return
            cursor = (data.get("response_metadata") or {}).get("next_cursor")
            if not cursor or not items:
                return
            params["cursor"] = cursor

    def download(self, url, timeout=120):
        host = urllib.parse.urlsplit(url).hostname
        if not slack_host(host):
            raise SlackError(f"refusing to send the Slack token to non-Slack host {host!r}")
        req = urllib.request.Request(
            url, headers={"Authorization": "Bearer " + self.token(), "User-Agent": f"slack-cli/{VERSION}"}
        )
        resp, body = self._send(req, "file download", timeout, idempotent=True)
        status = getattr(resp, "status", None) or getattr(resp, "code", 0)
        if status and status >= 400:
            raise SlackError(f"file download failed: HTTP {status}")
        return resp.headers.get("Content-Type", ""), body

    def upload_bytes(self, url, data, label="file upload"):
        if self.dry_env:
            print(f"[{DRY_ENV}] would POST {len(data)} bytes to the upload URL", file=sys.stderr)
            return
        if not slack_host(urllib.parse.urlsplit(url).hostname):
            raise SlackError("upload URL is not a Slack host")
        req = urllib.request.Request(
            url,
            data=data,
            method="POST",
            headers={"Content-Type": "application/octet-stream", "User-Agent": f"slack-cli/{VERSION}"},
        )
        resp, body = self._send(req, label, 300, idempotent=False)
        status = getattr(resp, "status", None) or getattr(resp, "code", 0)
        if status and status >= 300:
            raise SlackError(f"{label} failed: HTTP {status}")


def format_api_error(method, payload):
    err = payload.get("error") or "unknown_error"
    if err == "missing_scope":
        needed = payload.get("needed") or "an additional scope"
        return (
            f"{method}: missing_scope: the token lacks '{needed}'. Add it to the user "
            f"scopes and reinstall the slack-cli Slack app from {MANIFEST_HINT}"
        )
    hints = {
        "invalid_auth": "token rejected; check the sops secret keys/slack-token",
        "token_revoked": "token revoked; reinstall the slack-cli app and update keys/slack-token",
        "not_authed": "no token sent",
        "channel_not_found": "unknown conversation or no access (try: slack channels --refresh)",
        "not_in_channel": "you are not a member of that conversation",
        "thread_not_found": "no thread at that ts",
        "message_not_found": "no message at that ts",
        "cant_update_message": "you can only edit your own messages",
        "cant_delete_message": "you can only delete your own messages",
        "already_reacted": "you already added that reaction",
        "no_reaction": "you have not added that reaction",
        "invalid_name": "unknown emoji name",
        "user_not_found": "unknown user",
        "users_not_found": "unknown user",
        "is_archived": "that conversation is archived",
        "ratelimited": "rate limited; try again later",
        "time_in_past": "the scheduled time is in the past",
        "time_too_far": "the scheduled time is more than 120 days away",
        "file_not_found": "unknown file or no access",
        "name_taken": "a channel with that name already exists",
        "invalid_ts_oldest": "invalid oldest timestamp",
        "paid_only": "this feature needs a paid Slack plan",
    }
    extra = hints.get(err, "")
    detail = payload.get("detail")
    msgs = (payload.get("response_metadata") or {}).get("messages")
    parts = [f"{method}: {err}"]
    if extra:
        parts.append(extra)
    if detail:
        parts.append(str(detail))
    if msgs:
        parts.append("; ".join(map(str, msgs)))
    return " - ".join(parts)


# --------------------------------------------------------------------------
# Cache and context
# --------------------------------------------------------------------------


class Cache:
    def __init__(self, refresh=False):
        self.refresh = refresh

    def path(self, name):
        return os.path.join(CACHE_DIR, f"{name}.v2.json")

    def load(self, name):
        if self.refresh:
            return None
        path = self.path(name)
        try:
            if time.time() - os.path.getmtime(path) > TTL[name]:
                return None
            with open(path, encoding="utf-8") as f:
                return json.load(f)
        except (OSError, ValueError):
            return None

    def save(self, name, data):
        try:
            os.makedirs(CACHE_DIR, mode=0o700, exist_ok=True)
            fd, tmp = tempfile.mkstemp(dir=CACHE_DIR, prefix=f".{name}.")
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False)
            os.replace(tmp, self.path(name))
        except OSError as e:
            warn(f"could not write cache {name}: {e}")


def norm(s):
    s = unicodedata.normalize("NFKD", str(s or "")).encode("ascii", "ignore").decode()
    return re.sub(r"\s+", " ", s.strip().lower().lstrip("@#"))


def fuzzy_rank(query, items, keys):
    """Rank items by how well any of keys(item) matches query. Higher is better."""
    q = norm(query)
    if not q:
        return [(1, it) for it in items]
    qtok = q.split()
    ranked = []
    for it in items:
        best = 0.0
        for key in keys(it):
            k = norm(key)
            if not k:
                continue
            ktok = re.split(r"[\s._\-@]+", k)
            if k == q:
                score = 100
            elif k.startswith(q):
                score = 80
            elif all(any(t.startswith(qt) for t in ktok) for qt in qtok):
                score = 70
            elif q in k:
                score = 60
            else:
                ratio = difflib.SequenceMatcher(None, q, k).ratio()
                score = ratio * 50 if ratio >= 0.75 else 0
            best = max(best, score)
        if best:
            ranked.append((best, it))
    ranked.sort(key=lambda x: -x[0])
    return ranked


def pick_unique(query, ranked, kind, label):
    if not ranked:
        raise SlackError(f"unknown {kind}: {query} (try: slack {kind}s {query!r} --refresh)")
    top = ranked[0][0]
    best = [it for s, it in ranked if s == top]
    if len(best) == 1:
        return best[0]
    names = ", ".join(label(it) for it in best[:8])
    raise SlackError(f"ambiguous {kind} {query!r}: {names}")


def user_summary(u):
    p = u.get("profile") or {}
    return {
        "id": u.get("id"),
        "name": u.get("name") or "",
        "display_name": p.get("display_name") or "",
        "real_name": u.get("real_name") or p.get("real_name") or "",
        "email": p.get("email") or "",
        "title": p.get("title") or "",
        "tz": u.get("tz") or "",
        "team_id": u.get("team_id") or p.get("team") or "",
        "is_bot": bool(u.get("is_bot")),
        "deleted": bool(u.get("deleted")),
        "is_restricted": bool(u.get("is_restricted")),
    }


def conv_summary(c):
    out = {
        "id": c.get("id"),
        "name": c.get("name") or "",
        "is_im": bool(c.get("is_im")),
        "is_mpim": bool(c.get("is_mpim")),
        "is_private": bool(c.get("is_private")),
        "is_member": bool(c.get("is_member")) or bool(c.get("is_im")),
        "is_archived": bool(c.get("is_archived")),
        "is_ext_shared": bool(c.get("is_ext_shared")),
        "user": c.get("user"),
        "num_members": c.get("num_members"),
        "previous_names": c.get("previous_names") or [],
        "topic": ((c.get("topic") or {}).get("value") or ""),
        "purpose": ((c.get("purpose") or {}).get("value") or ""),
    }
    return out


class Ctx:
    def __init__(self, json_out=False, refresh=False, long=False):
        self.client = Client()
        self.cache = Cache(refresh)
        self.json = json_out
        self.long = long
        self.refresh = refresh
        self._lock = threading.RLock()
        self._team = None
        self._users = None
        self._users_dirty = False
        self._users_refreshed = False
        self._convs = None
        self._convs_dirty = False
        self._convs_refreshed = False
        self._groups = None

    # --- team ---------------------------------------------------------------
    def team(self):
        if self._team is None:
            data = self.cache.load("team")
            if not data:
                r = self.client.call("auth.test")
                data = {k: r.get(k) for k in ("url", "team", "team_id", "user", "user_id", "enterprise_id")}
                self.cache.save("team", data)
            self._team = data
        return self._team

    def base_url(self):
        return (self.team().get("url") or "https://slack.com/").rstrip("/")

    def self_id(self):
        return self.team().get("user_id")

    # --- users --------------------------------------------------------------
    def users(self, force=False):
        with self._lock:
            if self._users is None or force:
                data = None if force else self.cache.load("users")
                if data is None:
                    data = {}
                    for u in self.client.paginate("users.list", {}, "members", page_size=500):
                        data[u["id"]] = user_summary(u)
                    # Keep previously cached external users (Slack Connect).
                    old = self._users or {}
                    for uid, u in old.items():
                        data.setdefault(uid, u)
                    self._users_dirty = True
                    self._users_refreshed = True
                self._users = data
            return self._users

    def _save_users(self):
        if self._users_dirty and self._users is not None:
            self.cache.save("users", self._users)
            self._users_dirty = False

    def user(self, uid):
        """Return a cached summary for uid, fetching unknown users once."""
        if not uid:
            return None
        users = self.users()
        if uid in users:
            return users[uid]
        r = self.client.call("users.info", {"user": uid}, allow_error=True)
        if r.get("ok"):
            summary = user_summary(r["user"])
        elif r.get("error") in ("user_not_found", "users_not_found"):
            summary = None
        else:
            return None  # transient or scope problem: do not cache
        with self._lock:
            users[uid] = summary
            self._users_dirty = True
        return summary

    def prefetch_users(self, uids):
        users = self.users()
        missing = sorted({u for u in uids if u and u not in users})
        if not missing:
            return
        with concurrent.futures.ThreadPoolExecutor(WORKERS) as ex:
            list(ex.map(lambda i: self.bot_name(i) if i.startswith("B") else self.user(i), missing))

    def bot_name(self, bid):
        """Name of a bot ID (bots.info), cached alongside users."""
        if not bid:
            return None
        users = self.users()
        if bid in users:
            return (users[bid] or {}).get("name")
        r = self.client.call("bots.info", {"bot": bid}, allow_error=True)
        if r.get("ok"):
            entry = {"id": bid, "name": (r.get("bot") or {}).get("name") or bid, "is_bot_id": True}
        elif r.get("error") == "bot_not_found":
            entry = None
        else:
            return None
        with self._lock:
            users[bid] = entry
            self._users_dirty = True
        return entry["name"] if entry else None

    def user_name(self, uid):
        u = self.user(uid)
        if not u:
            return uid or "?"
        return u.get("display_name") or u.get("real_name") or u.get("name") or uid

    def resolve_user(self, ref):
        ref = (ref or "").strip()
        if not ref:
            raise UsageError("empty user")
        m = re.match(r"^<@([UW][A-Z0-9]+)(\|[^>]*)?>$", ref)
        if m:
            return m.group(1)
        q = ref.lstrip("@")
        users = self.users()
        if ID_USER_RE.match(q) and (q in users or self.user(q)):
            return q
        if "@" in q and "." in q.split("@")[-1]:
            for uid, u in users.items():
                if u and u.get("email", "").lower() == q.lower():
                    return uid
            r = self.client.call("users.lookupByEmail", {"email": q}, allow_error=True)
            if r.get("ok"):
                summary = user_summary(r["user"])
                with self._lock:
                    users[summary["id"]] = summary
                    self._users_dirty = True
                return summary["id"]
            if r.get("error") == "missing_scope":
                raise SlackError(format_api_error("users.lookupByEmail", r))
            raise SlackError(f"no user with email {q}")
        cands = [u for u in users.values() if u and not u.get("is_bot_id")]

        def keys(u):
            return [u["name"], u["display_name"], u["real_name"], u["email"].split("@")[0]]

        ranked = fuzzy_rank(q, cands, keys)
        if not ranked and not self._users_refreshed:
            self.users(force=True)
            ranked = fuzzy_rank(q, [u for u in self._users.values() if u and not u.get("is_bot_id")], keys)
        # Prefer active humans when the match quality ties.
        if ranked:
            top = ranked[0][0]
            tied = [(s, u) for s, u in ranked if s == top]
            active = [(s, u) for s, u in tied if not u["deleted"] and not u["is_bot"]]
            if len(tied) > 1 and len(active) == 1:
                ranked = active
        return pick_unique(ref, ranked, "user", lambda u: f"@{u['name']} ({u['real_name']}, {u['id']})")["id"]

    # --- conversations --------------------------------------------------------
    def convs(self, force=False):
        with self._lock:
            if self._convs is None or force:
                data = None if force else self.cache.load("conversations")
                if data is None:
                    data = {}
                    for c in self.client.paginate(
                        "conversations.list",
                        {"types": "public_channel,private_channel,mpim,im", "exclude_archived": False},
                        "channels",
                        page_size=999,
                    ):
                        data[c["id"]] = conv_summary(c)
                    self._convs_dirty = True
                    self._convs_refreshed = True
                self._convs = data
            return self._convs

    def _save_convs(self):
        if self._convs_dirty and self._convs is not None:
            self.cache.save("conversations", self._convs)
            self._convs_dirty = False

    def conv(self, cid):
        convs = self.convs()
        if cid in convs:
            return convs[cid]
        r = self.client.call("conversations.info", {"channel": cid}, allow_error=True)
        if r.get("ok"):
            summary = conv_summary(r["channel"])
        elif r.get("error") == "channel_not_found":
            summary = None
        else:
            return None
        with self._lock:
            convs[cid] = summary
            self._convs_dirty = True
        return summary

    def conv_label(self, cid):
        c = self.conv(cid)
        if not c:
            return cid
        if c["is_im"]:
            return "@" + self.user_name(c.get("user")) + " (dm)"
        if c["is_mpim"]:
            name = c["name"]
            m = re.match(r"^mpdm-(.*)-\d+$", name)
            return "group dm: " + (m.group(1).replace("--", ", ") if m else name)
        return "#" + (c["name"] or cid)

    def resolve_conv(self, ref, for_write=False):
        """Resolve #name, name, ID, permalink, or @user (DM) to a conversation ID.

        For writes, a user with no existing DM resolves to the user ID, which
        chat.postMessage accepts as "post in the DM with this user".
        """
        ref = (ref or "").strip()
        if not ref:
            raise UsageError("empty conversation")
        if "/archives/" in ref or "app.slack.com/client/" in ref:
            return parse_permalink(ref)[0]
        m = re.match(r"^<#([CDG][A-Z0-9]+)(\|[^>]*)?>$", ref)
        if m:
            return m.group(1)
        convs = self.convs()
        bare = ref.lstrip("#")
        if ID_CONV_RE.match(bare):
            return bare
        if ref.startswith("@") or ID_USER_RE.match(ref) or ref.startswith("<@"):
            uid = self.resolve_user(ref)
            for c in convs.values():
                if c and c["is_im"] and c.get("user") == uid:
                    return c["id"]
            if not self._convs_refreshed:
                for c in self.convs(force=True).values():
                    if c and c["is_im"] and c.get("user") == uid:
                        return c["id"]
            if for_write:
                return uid
            raise SlackError(f"no DM with {ref} found (see: slack conversations --types im)")
        cands = [c for c in convs.values() if c and not c["is_im"]]

        def keys(c):
            return [c["name"]] + list(c.get("previous_names") or [])

        ranked = fuzzy_rank(bare, cands, keys)
        if not ranked and not self._convs_refreshed:
            self.convs(force=True)
            ranked = fuzzy_rank(bare, [c for c in self._convs.values() if c and not c["is_im"]], keys)
        if ranked and ranked[0][0] < 100:
            # Prefer channels the user is in when fuzzy matches tie.
            top = ranked[0][0]
            tied = [(s, c) for s, c in ranked if s == top]
            member = [(s, c) for s, c in tied if c["is_member"] and not c["is_archived"]]
            if len(tied) > 1 and len(member) == 1:
                ranked = member
            pick = pick_unique(ref, ranked, "channel", lambda c: f"#{c['name']} ({c['id']})")
            warn(f"note: {ref!r} matched #{pick['name']} ({pick['id']})")
            return pick["id"]
        return pick_unique(ref, ranked, "channel", lambda c: f"#{c['name']} ({c['id']})")["id"]

    # --- usergroups ---------------------------------------------------------
    def usergroups(self):
        with self._lock:
            if self._groups is None:
                data = self.cache.load("usergroups")
                if data is None:
                    r = self.client.call("usergroups.list", {"include_disabled": True}, allow_error=True)
                    data = {}
                    if r.get("ok"):
                        for g in r.get("usergroups") or []:
                            data[g["id"]] = {"handle": g.get("handle"), "name": g.get("name")}
                    self.cache.save("usergroups", data)
                self._groups = data
            return self._groups

    def group_handle(self, gid):
        g = self.usergroups().get(gid)
        return g["handle"] if g and g.get("handle") else gid

    # --- links --------------------------------------------------------------
    def permalink(self, channel, ts, thread_ts=None):
        url = f"{self.base_url()}/archives/{channel}/p{ts.replace('.', '')}"
        if thread_ts and thread_ts != ts:
            url += f"?thread_ts={thread_ts}&cid={channel}"
        return url

    def close(self):
        self._save_users()
        self._save_convs()


# --------------------------------------------------------------------------
# Parsing helpers
# --------------------------------------------------------------------------


def parse_permalink(url):
    """Return (channel, ts, thread_ts or None) from a message permalink."""
    url = url.strip().strip("<>")
    parts = urllib.parse.urlsplit(url)
    qs = urllib.parse.parse_qs(parts.query)
    m = re.search(r"/archives/([A-Z0-9]+)/p(\d{10})(\d{6})", parts.path)
    if m:
        thread_ts = (qs.get("thread_ts") or [None])[0]
        return m.group(1), f"{m.group(2)}.{m.group(3)}", thread_ts
    m = re.search(r"/client/[A-Z0-9]+/([A-Z0-9]+)/thread/([A-Z0-9]+)-(\d{9,10}\.\d+)", parts.path)
    if m:
        return m.group(1), m.group(3), m.group(3)
    m = re.search(r"/archives/([A-Z0-9]+)/?$", parts.path)
    if m:
        raise SlackError(f"{url} is a channel link, not a message link")
    raise SlackError(f"cannot parse Slack message permalink: {url}")


def file_id_from(ref):
    ref = ref.strip().strip("<>")
    if ID_FILE_RE.match(ref):
        return ref
    m = re.search(r"/files-(?:pri|tmb)/T[A-Z0-9]+-(F[A-Z0-9]+)/", ref)
    if m:
        return m.group(1)
    m = re.search(r"/(?:files/[A-Z0-9]+|docs/[A-Z0-9]+|lists/[A-Z0-9]+)/(F[A-Z0-9]+)", ref)
    if m:
        return m.group(1)
    m = re.search(r"\b(F[A-Z0-9]{8,})\b", ref)
    if m:
        return m.group(1)
    raise SlackError(f"cannot find a file ID in {ref!r}")


def normalize_ts(ts):
    ts = ts.strip()
    m = PTS_RE.match(ts)
    if m:
        return f"{m.group(1)}.{m.group(2)}"
    if TS_RE.match(ts):
        return ts
    raise UsageError(f"not a Slack message ts: {ts}")


def message_ref(ctx, args, what="message"):
    """Parse [permalink] or [channel ts] from a list of positionals.

    Returns (channel, ts, thread_ts, remaining_args).
    """
    if not args:
        raise UsageError(f"expected a {what} permalink or: <channel> <ts>")
    if "/archives/" in args[0] or "app.slack.com/client/" in args[0]:
        ch, ts, thread = parse_permalink(args[0])
        return ch, ts, thread, list(args[1:])
    if len(args) < 2:
        raise UsageError(f"expected a {what} permalink or: <channel> <ts>")
    return ctx.resolve_conv(args[0]), normalize_ts(args[1]), None, list(args[2:])


UNITS = {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800}


def parse_time(spec, future=False):
    """Parse 2d / 5h / +30m / epoch / today / YYYY-MM-DD[THH:MM] into epoch."""
    s = spec.strip().lower()
    now = time.time()
    if re.match(r"^\d{9,10}(\.\d+)?$", s):
        return float(s)
    m = re.match(r"^(in\s+|\+)?(\d+)\s*([smhdw])$", s)
    if m:
        delta = int(m.group(2)) * UNITS[m.group(3)]
        return now + delta if (future or m.group(1)) else now - delta
    today = dt.datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    if s == "now":
        return now
    if s == "today":
        return today.timestamp()
    if s == "yesterday":
        return (today - dt.timedelta(days=1)).timestamp()
    if s == "tomorrow":
        return (today + dt.timedelta(days=1)).timestamp()
    try:
        d = dt.datetime.fromisoformat(spec.strip().replace("Z", "+00:00"))
    except ValueError:
        raise UsageError(
            f"bad time {spec!r} (use 2d, 5h, 30m, +2h, today, yesterday, YYYY-MM-DD, "
            "YYYY-MM-DDTHH:MM, or an epoch ts)"
        ) from None
    if d.tzinfo is None:
        d = d.astimezone()
    return d.timestamp()


def iso(ts):
    try:
        return dt.datetime.fromtimestamp(float(ts), dt.timezone.utc).strftime("%Y-%m-%dT%H:%MZ")
    except (TypeError, ValueError, OverflowError):
        return ""


def read_text(words, file_opt, what="message"):
    """Message text from --file PATH, --file -, a lone '-', or the arguments."""
    if file_opt:
        if file_opt == "-":
            text = sys.stdin.read()
        else:
            try:
                with open(file_opt, encoding="utf-8") as f:
                    text = f.read()
            except OSError as e:
                raise SlackError(f"cannot read {file_opt}: {e.strerror}") from None
        if words:
            raise UsageError(f"give the {what} either as arguments or with --file, not both")
    elif words == ["-"]:
        text = sys.stdin.read()
    else:
        text = " ".join(words)
    text = text.rstrip("\n")
    if not text.strip():
        raise UsageError(f"empty {what} (pass text, '-' for stdin, or --file PATH)")
    return text


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

TOKEN_RE = re.compile(r"<([^<>\n]+)>")


def link_text(label, url):
    """Render a link so both the label and the URL stay visible, without repeats."""
    if url.startswith("mailto:"):
        return label.removeprefix("mailto:") or url[7:]
    if url.startswith("tel:"):
        return label or url[4:]
    bare = re.sub(r"^https?://(www\.)?", "", url).rstrip("/")
    lab = re.sub(r"^https?://(www\.)?", "", label).rstrip("/")
    if not label or lab == bare:
        return url
    return f"{label} ({url})"


class Renderer:
    def __init__(self, ctx):
        self.ctx = ctx

    # --- mrkdwn -------------------------------------------------------------
    def mrkdwn(self, text):
        if not text:
            return ""
        out = []
        pos = 0
        for m in TOKEN_RE.finditer(text):
            out.append(html.unescape(text[pos : m.start()]))
            out.append(self._token(m.group(1)))
            pos = m.end()
        out.append(html.unescape(text[pos:]))
        return "".join(out)

    def _token(self, inner):
        target, _, label = inner.partition("|")
        label = html.unescape(label)
        if target.startswith("@"):
            uid = target[1:]
            return "@" + (self.ctx.user_name(uid) if ID_USER_RE.match(uid) else (label or uid))
        if target.startswith("#"):
            cid = target[1:]
            if label:
                return "#" + label
            lab = self.ctx.conv_label(cid)
            return lab if lab.startswith("#") else "#" + cid
        if target.startswith("!"):
            cmd = target[1:]
            if cmd.startswith("subteam^"):
                gid = cmd.split("^", 1)[1]
                return label if label.startswith("@") else "@" + (label or self.ctx.group_handle(gid))
            if cmd in ("here", "channel", "everyone"):
                return "@" + cmd
            if cmd.startswith("date^"):
                if label:
                    return label
                bits = cmd.split("^")
                return iso(bits[1]) if len(bits) > 1 else cmd
            return label or "@" + cmd
        return link_text(label, html.unescape(target))

    # --- rich text ----------------------------------------------------------
    def _rt_inline(self, els):
        out = []
        for el in els or []:
            t = el.get("type")
            style = el.get("style") or {}
            if t == "text":
                s = el.get("text") or ""
                if style.get("code"):
                    s = f"`{s}`"
                else:
                    if style.get("bold") and s.strip():
                        s = f"*{s}*"
                    if style.get("italic") and s.strip():
                        s = f"_{s}_"
                    if style.get("strike") and s.strip():
                        s = f"~{s}~"
            elif t == "link":
                s = link_text(el.get("text") or "", el.get("url") or "")
            elif t == "user":
                s = "@" + self.ctx.user_name(el.get("user_id"))
            elif t == "usergroup":
                s = "@" + self.ctx.group_handle(el.get("usergroup_id"))
            elif t == "channel":
                lab = self.ctx.conv_label(el.get("channel_id"))
                s = lab if lab.startswith("#") else "#" + str(el.get("channel_id"))
            elif t == "emoji":
                s = f":{el.get('name')}:"
            elif t == "broadcast":
                s = "@" + str(el.get("range"))
            elif t == "date":
                s = el.get("fallback") or iso(el.get("timestamp"))
            elif t == "color":
                s = str(el.get("value") or "")
            elif t == "team":
                s = "@team:" + str(el.get("team_id"))
            else:
                s = str(el.get("text") or "")
            out.append(s)
        return "".join(out)

    def _rich_text(self, block):
        lines = []
        for el in block.get("elements") or []:
            t = el.get("type")
            if t == "rich_text_section":
                lines.append(self._rt_inline(el.get("elements")))
            elif t == "rich_text_list":
                indent = "  " * int(el.get("indent") or 0)
                ordered = el.get("style") == "ordered"
                start = int(el.get("offset") or 0)
                for i, item in enumerate(el.get("elements") or [], start + 1):
                    bullet = f"{i}. " if ordered else "- "
                    lines.append(indent + bullet + self._rt_inline(item.get("elements")))
            elif t == "rich_text_preformatted":
                lines.append("```\n" + self._rt_inline(el.get("elements")).strip("\n") + "\n```")
            elif t == "rich_text_quote":
                q = self._rt_inline(el.get("elements"))
                lines.append("\n".join("> " + ln for ln in q.split("\n")))
            else:
                lines.append(self._rt_inline(el.get("elements")))
        return "\n".join(ln.rstrip("\n") for ln in lines if ln is not None)

    # --- blocks -------------------------------------------------------------
    def _text_obj(self, obj):
        if not obj:
            return ""
        if isinstance(obj, str):
            return obj
        if obj.get("type") == "mrkdwn":
            return self.mrkdwn(obj.get("text") or "")
        return obj.get("text") or ""

    def _element(self, el):
        t = el.get("type")
        if t == "button":
            label = self._text_obj(el.get("text"))
            url = el.get("url")
            return f"[button: {label}{' ' + url if url else ''}]"
        if t == "image":
            return f"[image: {el.get('alt_text') or ''}]".replace(": ]", "]")
        if t in ("mrkdwn", "plain_text"):
            return self._text_obj(el)
        if t in (
            "static_select",
            "overflow",
            "datepicker",
            "users_select",
            "conversations_select",
            "channels_select",
            "multi_static_select",
            "checkboxes",
            "radio_buttons",
            "external_select",
            "multi_users_select",
            "timepicker",
            "datetimepicker",
        ):
            opt = el.get("initial_option") or {}
            return f"[{self._text_obj(opt.get('text'))}]" if opt.get("text") else ""
        return self._collect(el)

    def _collect(self, obj):
        """Fallback: gather text from an unknown structure."""
        found = []

        def walk(o):
            if isinstance(o, dict):
                if o.get("type") in ("mrkdwn", "plain_text") and "text" in o:
                    found.append(self._text_obj(o))
                    return
                if isinstance(o.get("text"), str) and o.get("type") not in ("button",):
                    found.append(self.mrkdwn(o["text"]))
                for k, v in o.items():
                    if k != "text":
                        walk(v)
            elif isinstance(o, list):
                for v in o:
                    walk(v)

        walk(obj)
        return " ".join(f for f in found if f)

    def blocks(self, blocks):
        lines = []
        for b in blocks or []:
            try:
                lines.append(self._block(b))
            except Exception:  # noqa: BLE001 - never crash on odd shapes
                lines.append(self._collect(b))
        return "\n".join(ln for ln in lines if ln)

    def _block(self, b):
        t = b.get("type")
        if t == "rich_text":
            return self._rich_text(b)
        if t == "section":
            parts = []
            if b.get("text"):
                parts.append(self._text_obj(b["text"]))
            for f in b.get("fields") or []:
                parts.append(self._text_obj(f))
            acc = b.get("accessory")
            if acc and acc.get("type") in ("button",):
                parts.append(self._element(acc))
            return "\n".join(p for p in parts if p)
        if t == "header":
            return self._text_obj(b.get("text"))
        if t == "context":
            items = [self._element(e) for e in b.get("elements") or []]
            return "  ".join(i for i in items if i and i != "[image]")
        if t == "actions":
            items = [self._element(e) for e in b.get("elements") or []]
            items = [i for i in items if i and i != "[button: ⋮]"]
            return " ".join(items)
        if t == "divider":
            return ""
        if t == "image":
            title = self._text_obj(b.get("title")) or b.get("alt_text") or ""
            url = b.get("image_url") or (b.get("slack_file") or {}).get("url") or ""
            return f"[image: {title} {url}]".replace("  ", " ")
        if t == "markdown":
            return b.get("text") or ""
        if t == "file":
            return f"[file: {b.get('external_id') or b.get('file_id') or ''}]"
        if t == "video":
            return f"[video: {self._text_obj(b.get('title'))} {b.get('video_url') or ''}]"
        if t == "input":
            return self._text_obj(b.get("label"))
        if t == "table":
            rows = []
            for row in b.get("rows") or []:
                cells = []
                for cell in row:
                    if cell.get("type") == "rich_text":
                        cells.append(self._rich_text(cell).replace("\n", " "))
                    else:
                        cells.append(str(cell.get("text") or ""))
                rows.append(" | ".join(cells))
            return "\n".join(rows)
        if t == "call":
            return "[call]"
        return self._collect(b)

    # --- attachments --------------------------------------------------------
    def attachment(self, a):
        lines = []
        if a.get("blocks"):
            lines.append(self.blocks(a["blocks"]))
        else:
            unfurl = a.get("from_url") and not a.get("is_msg_unfurl") and not a.get("is_share")
            if unfurl:
                title = a.get("title") or a.get("fallback") or ""
                svc = a.get("service_name") or ""
                return f"[link preview: {svc + ': ' if svc else ''}{title}]" if title else ""
            if a.get("is_msg_unfurl") or a.get("is_share"):
                who = a.get("author_name") or a.get("author_subname") or ""
                lines.append(
                    f"[shared message{' from ' + who if who else ''}]"
                    + (f" {a['from_url']}" if a.get("from_url") else "")
                )
            elif a.get("author_name"):
                lines.append(a["author_name"])
            if a.get("pretext"):
                lines.append(self.mrkdwn(a["pretext"]))
            if a.get("title"):
                title = self.mrkdwn(a["title"])
                if a.get("title_link"):
                    title += f" ({a['title_link']})"
                lines.append(title)
            if a.get("text"):
                lines.append(self.mrkdwn(a["text"]))
            for f in a.get("fields") or []:
                ft = self.mrkdwn(f.get("title") or "")
                fv = self.mrkdwn(f.get("value") or "")
                lines.append(f"{ft}: {fv}" if ft else fv)
            if a.get("image_url"):
                lines.append(f"[image: {a['image_url']}]")
            for act in a.get("actions") or []:
                label = act.get("text") or act.get("name") or ""
                if label:
                    lines.append(f"[button: {label}{' ' + act['url'] if act.get('url') else ''}]")
            if a.get("message_blocks"):
                for mb in a["message_blocks"]:
                    lines.append(self.blocks((mb.get("message") or {}).get("blocks")))
            if a.get("footer"):
                foot = self.mrkdwn(a["footer"])
                if a.get("ts"):
                    foot += f" ({iso(a['ts'])})"
                lines.append(foot)
            if not any(ln.strip() for ln in lines) and a.get("fallback"):
                lines.append(self.mrkdwn(a["fallback"]))
        for f in a.get("files") or []:
            lines.append(self.file_line(f))
        return "\n".join(ln for ln in lines if ln)

    def _safe(self, fn, obj):
        try:
            return fn(obj)
        except Exception:  # noqa: BLE001 - never crash on odd shapes
            return self._collect(obj)

    # --- files --------------------------------------------------------------
    @staticmethod
    def file_info(f):
        return {
            "id": f.get("id"),
            "name": f.get("name") or f.get("title") or "",
            "title": f.get("title") or "",
            "mimetype": f.get("mimetype") or "",
            "filetype": f.get("filetype") or "",
            "size": f.get("size"),
            "url_private": f.get("url_private") or "",
            "permalink": f.get("permalink") or "",
            "is_canvas": f.get("filetype") == "quip" or f.get("pretty_type") == "Canvas",
            "is_list": f.get("filetype") == "list",
        }

    def file_line(self, f):
        if f.get("mode") == "tombstone" or f.get("file_access") == "file_not_found":
            return f"[file {f.get('id')} (deleted or inaccessible)]"
        i = self.file_info(f)
        kind = "canvas" if i["is_canvas"] else "list" if i["is_list"] else "file"
        url = i["permalink"] if kind != "file" else i["url_private"] or i["permalink"]
        return f'[{kind} {i["id"]} "{i["name"] or i["title"]}" {i["mimetype"] or i["filetype"]} {url}]'

    # --- messages -----------------------------------------------------------
    def author(self, m):
        bp = m.get("bot_profile") or {}
        username = m.get("username") or (m.get("user_profile") or {}).get("display_name")
        if m.get("bot_id") or m.get("subtype") == "bot_message":
            name = m.get("username") or bp.get("name")
            if not name and m.get("user"):
                name = self.ctx.user_name(m["user"])
            if m.get("username") and bp.get("name") and m["username"] != bp["name"]:
                name = f"{m['username']} ({bp['name']})"
            if not name and m.get("bot_id"):
                name = self.ctx.bot_name(m["bot_id"])
            return (name or m.get("bot_id") or "bot") + " [bot]"
        if m.get("user"):
            return self.ctx.user_name(m["user"])
        return username or "?"

    def message(self, m, channel=None, target_ts=None):
        """Normalize one Slack message dict. Never raises."""
        try:
            return self._message(m, channel, target_ts)
        except Exception as e:  # noqa: BLE001 - last-resort guard
            ts = str(m.get("ts") or "")
            return {
                "ts": ts,
                "time": iso(ts),
                "channel": channel,
                "author": "?",
                "text": f"[unrenderable message: {type(e).__name__}] " + str(m.get("text") or ""),
                "permalink": self.ctx.permalink(channel, ts) if channel and ts else "",
            }

    def _message(self, m, channel, target_ts):
        if not isinstance(m, dict):
            return {"ts": "", "time": "", "author": "?", "text": str(m), "permalink": ""}
        if channel:
            ch = channel
        elif isinstance(m.get("channel"), dict):
            ch = m["channel"].get("id")
        else:
            ch = m.get("channel")
        ts = str(m.get("ts") or "")
        blocks = m.get("blocks") or []
        textual = {"rich_text", "section", "header", "markdown", "context", "table"}
        text = self.mrkdwn(m.get("text") or "")
        if any(b.get("type") in textual for b in blocks if isinstance(b, dict)):
            body = self.blocks(blocks) or text
        elif blocks:
            body = "\n".join(p for p in (text, self.blocks(blocks)) if p)
        else:
            body = text
        att_lines = [
            self._safe(self.attachment, a) for a in m.get("attachments") or [] if isinstance(a, dict)
        ]
        file_lines = [self.file_line(f) for f in m.get("files") or [] if isinstance(f, dict)]
        parts = [p for p in [body] + att_lines + file_lines if p and p.strip()]
        full = "\n".join(parts)
        thread_ts = m.get("thread_ts")
        reactions = [
            {
                "name": r.get("name"),
                "count": r.get("count") or len(r.get("users") or []),
                "users": r.get("users") or [],
            }
            for r in m.get("reactions") or []
        ]
        permalink = m.get("permalink") or (self.ctx.permalink(ch, ts, thread_ts) if ch and ts else "")
        out = {
            "ts": ts,
            "time": iso(ts),
            "channel": ch,
            "author": self.author(m),
            "user": m.get("user"),
            "bot_id": m.get("bot_id"),
            "app_id": m.get("app_id"),
            "subtype": m.get("subtype"),
            "text": full,
            "thread_ts": thread_ts,
            "is_reply": bool(thread_ts and thread_ts != ts),
            "reply_count": m.get("reply_count") or 0,
            "latest_reply": m.get("latest_reply"),
            "reactions": reactions,
            "files": [self.file_info(f) for f in m.get("files") or [] if isinstance(f, dict)],
            "edited": bool(m.get("edited")),
            "permalink": permalink,
        }
        if target_ts is not None:
            out["linked"] = ts == target_ts
        return out

    def line(self, n, indent=""):
        markers = []
        sub = n.get("subtype")
        if sub == "thread_broadcast":
            markers.append("(reply also sent to channel)")
        elif sub and sub != "bot_message":
            markers.append(f"({sub})")
        if n.get("edited"):
            markers.append("(edited)")
        if n.get("reply_count"):
            last = f", last {iso(n['latest_reply'])}" if n.get("latest_reply") else ""
            markers.append(f"[thread: {n['reply_count']} replies{last}]")
        elif n.get("is_reply") and indent == "":
            markers.append(f"[in thread {n['thread_ts']}]")
        if n.get("reactions"):
            markers.append("[" + " ".join(f":{r['name']}:x{r['count']}" for r in n["reactions"]) + "]")
        mark = (" " + " ".join(markers)) if markers else ""
        prefix = "» " if n.get("linked") else ""
        head = f"{indent}{prefix}[{n['ts']} {n['time']}] {n['author']}:"
        if self.ctx.long:
            body = "\n".join(indent + "    " + ln for ln in (n["text"] or "").split("\n"))
            return f"{head}{mark}  <{n['permalink']}>\n{body}\n"
        body = (n["text"] or "").replace("\r", "").replace("\n", " ⏎ ")
        return f"{head} {body}{mark}  <{n['permalink']}>"

    def prefetch(self, messages):
        uids = set()
        for m in messages:
            if not isinstance(m, dict):
                continue
            uids.add(m.get("user"))
            if m.get("bot_id") and not m.get("username") and not (m.get("bot_profile") or {}).get("name"):
                uids.add(m["bot_id"])
            uids.update(m.get("reply_users") or [])
            for r in m.get("reactions") or []:
                uids.update(r.get("users") or [])
            blob = json.dumps(m.get("blocks") or []) + (m.get("text") or "")
            uids.update(re.findall(r"<@([UW][A-Z0-9]+)", blob))
            uids.update(re.findall(r'"user_id": "([UW][A-Z0-9]+)"', blob))
        self.ctx.prefetch_users(uids)


# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------


def emit_json(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False, indent=2) + "\n")


def out(line=""):
    sys.stdout.write(line + "\n")


# --------------------------------------------------------------------------
# Commands: identity and lookup
# --------------------------------------------------------------------------


def manifest_scopes():
    path = os.environ.get("SLACK_CLI_MANIFEST") or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "manifest.json"
    )
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)["oauth_config"]["scopes"]["user"]
    except (OSError, ValueError, KeyError):
        return None


def cmd_whoami(ctx, a):
    r = ctx.client.call("auth.test")
    scopes = sorted(
        s
        for s in (
            ctx.client.last_headers.get("x-oauth-scopes")
            or ctx.client.last_headers.get("X-OAuth-Scopes")
            or ""
        ).split(",")
        if s
    )
    wanted = manifest_scopes()
    missing = sorted(set(wanted) - set(scopes)) if wanted is not None and scopes else []
    info = {k: r.get(k) for k in ("user", "user_id", "team", "team_id", "url", "enterprise_id")}
    info["scopes"] = scopes
    info["missing_manifest_scopes"] = missing
    if ctx.json:
        return emit_json(info)
    out(f"user:  @{info['user']} ({info['user_id']})")
    out(f"team:  {info['team']} ({info['team_id']})  {info['url']}")
    out(f"scopes: {', '.join(scopes) or '(unknown)'}")
    if missing:
        out(f"missing scopes from the manifest: {', '.join(missing)}")
        out(f"  -> reinstall the slack-cli app from {MANIFEST_HINT}")


def user_flags(u, team_id):
    flags = []
    if u.get("is_bot"):
        flags.append("bot")
    if u.get("deleted"):
        flags.append("deactivated")
    if u.get("team_id") and team_id and u["team_id"] != team_id:
        flags.append("external")
    if u.get("is_restricted"):
        flags.append("guest")
    return flags


def user_row(u, team_id):
    flags = user_flags(u, team_id)
    bits = [u["id"], "@" + (u["name"] or "?"), u["real_name"] or u["display_name"]]
    if u.get("display_name") and u["display_name"] != u["real_name"]:
        bits.append(f"display:{u['display_name']}")
    if u.get("title"):
        bits.append(u["title"])
    if u.get("email"):
        bits.append(u["email"])
    if flags:
        bits.append("(" + ", ".join(flags) + ")")
    return "  ".join(b for b in bits if b)


def cmd_users(ctx, a):
    users = [u for u in ctx.users().values() if u and not u.get("is_bot_id")]
    if not a.all:
        users = [u for u in users if not u["deleted"]]
    if a.query:
        ranked = fuzzy_rank(
            " ".join(a.query),
            users,
            lambda u: [u["name"], u["display_name"], u["real_name"], u["email"], u["title"]],
        )
        if not ranked and not ctx._users_refreshed:
            users = [u for u in ctx.users(force=True).values() if u and not u.get("is_bot_id")]
            ranked = fuzzy_rank(
                " ".join(a.query),
                users,
                lambda u: [u["name"], u["display_name"], u["real_name"], u["email"], u["title"]],
            )
        users = [u for _, u in ranked]
    else:
        users.sort(key=lambda u: (u["is_bot"], norm(u["name"])))
    users = users[: a.limit] if a.limit else users
    if ctx.json:
        return emit_json({"users": users})
    team_id = ctx.team().get("team_id")
    for u in users:
        out(user_row(u, team_id))
    if not users:
        raise SlackError(
            "no matching users (Slack Connect users only appear after they are seen; try an email)"
        )


def cmd_user(ctx, a):
    uid = ctx.resolve_user(" ".join(a.user))
    u = ctx.client.call("users.info", {"user": uid})["user"]
    p = u.get("profile") or {}
    info = user_summary(u)
    info.update(
        {
            "status": " ".join(x for x in (p.get("status_emoji"), p.get("status_text")) if x),
            "phone": p.get("phone") or "",
            "pronouns": p.get("pronouns") or "",
            "is_admin": bool(u.get("is_admin")),
            "is_owner": bool(u.get("is_owner")),
            "tz_label": u.get("tz_label") or "",
            "updated": u.get("updated"),
            "dm_mention": f"<@{uid}>",
        }
    )
    with ctx._lock:
        ctx.users()[uid] = user_summary(u)
        ctx._users_dirty = True
    if ctx.json:
        return emit_json(info)
    team_id = ctx.team().get("team_id")
    out(f"id:        {info['id']}   mention: <@{uid}>")
    out(f"handle:    @{info['name']}")
    out(
        f"name:      {info['real_name']}"
        + (f"  (display: {info['display_name']})" if info["display_name"] else "")
    )
    for key in ("title", "email", "phone", "pronouns", "status"):
        if info[key]:
            out(f"{key + ':':<10} {info[key]}")
    if info["tz"]:
        out(f"tz:        {info['tz']} ({info['tz_label']})")
    flags = user_flags(info, team_id) + [f for f in ("admin", "owner") if info["is_" + f]]
    if flags:
        out(f"flags:     {', '.join(flags)}")
    if not info["email"]:
        out("email:     (hidden; needs the users:read.email scope or the user hides it)")


def conv_flags(c):
    flags = []
    if c["is_private"] and not c["is_mpim"]:
        flags.append("private")
    if c["is_member"]:
        flags.append("member")
    if c["is_ext_shared"]:
        flags.append("slack-connect")
    if c["is_archived"]:
        flags.append("archived")
    return flags


def cmd_channels(ctx, a):
    convs = [c for c in ctx.convs().values() if c and not c["is_im"] and not c["is_mpim"]]
    if not a.archived:
        convs = [c for c in convs if not c["is_archived"]]
    if a.member:
        convs = [c for c in convs if c["is_member"]]
    if a.query:
        ranked = fuzzy_rank(
            " ".join(a.query), convs, lambda c: [c["name"]] + c["previous_names"] + [c["topic"], c["purpose"]]
        )
        convs = [c for _, c in ranked]
    else:
        convs.sort(key=lambda c: c["name"])
    if ctx.json:
        return emit_json({"channels": convs})
    for c in convs:
        flags = conv_flags(c)
        members = f"{c['num_members']} members" if c.get("num_members") is not None else ""
        desc = (c["purpose"] or c["topic"]).replace("\n", " ")
        desc = desc[:80] + "…" if len(desc) > 80 else desc
        out(
            "  ".join(
                x
                for x in (
                    c["id"],
                    "#" + c["name"],
                    "(" + ", ".join(flags) + ")" if flags else "",
                    members,
                    desc,
                )
                if x
            )
        )
    if not convs:
        raise SlackError("no matching channels")


def cmd_conversations(ctx, a):
    types = a.types or "public_channel,private_channel,mpim,im"
    types = ",".join(
        {"public": "public_channel", "private": "private_channel", "dm": "im", "group": "mpim"}.get(
            t.strip(), t.strip()
        )
        for t in types.split(",")
    )
    items = list(
        ctx.client.paginate(
            "users.conversations",
            {"types": types, "exclude_archived": not a.archived},
            "channels",
            page_size=999,
        )
    )
    convs = ctx.convs()
    rows = []
    for c in items:
        s = conv_summary(c)
        s["is_member"] = True
        convs[s["id"]] = s
        rows.append(s)
    ctx._convs_dirty = True
    ctx.prefetch_users(c.get("user") for c in rows if c["is_im"])
    for r in rows:
        r["label"] = ctx.conv_label(r["id"])
    rows.sort(key=lambda r: (r["is_im"], r["is_mpim"], r["label"].lower()))
    if ctx.json:
        return emit_json({"conversations": rows})
    for r in rows:
        kind = (
            "dm" if r["is_im"] else "group-dm" if r["is_mpim"] else "private" if r["is_private"] else "public"
        )
        extra = ", slack-connect" if r["is_ext_shared"] else ""
        out(f"{r['id']}  {r['label']}  ({kind}{extra})")


def cmd_members(ctx, a):
    cid = ctx.resolve_conv(a.channel)
    ids = list(ctx.client.paginate("conversations.members", {"channel": cid}, "members", page_size=500))
    ctx.prefetch_users(ids)
    team_id = ctx.team().get("team_id")
    rows = [ctx.user(u) or {"id": u, "name": u, "real_name": "", "display_name": ""} for u in ids]
    if ctx.json:
        return emit_json({"channel": cid, "members": rows})
    out(f"== {ctx.conv_label(cid)}: {len(rows)} members ==")
    for u in rows:
        out(user_row({**{"title": "", "email": "", "is_bot": False, "deleted": False}, **u}, team_id))


def cmd_usergroups(ctx, a):
    r = ctx.client.call("usergroups.list", {"include_users": True, "include_disabled": a.all})
    groups = r.get("usergroups") or []
    if ctx.json:
        return emit_json({"usergroups": groups})
    for g in groups:
        users = ", ".join("@" + ctx.user_name(u) for u in g.get("users") or [])
        out(f"{g['id']}  @{g.get('handle')}  {g.get('name')}  <!subteam^{g['id']}>  [{users}]")


def cmd_emoji(ctx, a):
    emoji = ctx.client.call("emoji.list").get("emoji") or {}
    names = sorted(emoji)
    if a.query:
        q = norm(a.query)
        names = [n for n in names if q in n.lower()]
    if ctx.json:
        return emit_json({"emoji": {n: emoji[n] for n in names}})
    for n in names:
        v = emoji[n]
        out(f":{n}:  " + (f"alias of :{v[6:]}:" if v.startswith("alias:") else v))


# --------------------------------------------------------------------------
# Commands: reading messages
# --------------------------------------------------------------------------


def search_rewrite(ctx, query, ids=False):
    """Resolve in:#name, in:@user and from:@user operators to real names/IDs.

    Real-time Search only understands <#C…> and <@U…>, so ids=True always
    writes channel IDs instead of names.
    """

    def fix_in(m):
        ref = m.group(1)
        if ref.startswith("@"):
            try:
                return f"in:<@{ctx.resolve_user(ref)}>"
            except SlackError as e:
                warn(str(e))
                return m.group(0)
        try:
            cid = ctx.resolve_conv(ref)
        except SlackError as e:
            warn(str(e))
            return m.group(0)
        c = ctx.conv(cid)
        return f"in:#{c['name']}" if c and c["name"] and not ids else f"in:<#{cid}>"

    def fix_from(m):
        ref = m.group(1)
        try:
            return f"from:<@{ctx.resolve_user(ref)}>"
        except SlackError as e:
            warn(str(e))
            return m.group(0)

    query = re.sub(r"\bin:([#@]?[\w.\-]+)", fix_in, query)
    query = re.sub(r"\bfrom:(@?[\w.\-]+(?:@[\w.\-]+)?)", fix_from, query)
    return query


RTS_FALLBACK_ERRORS = {"missing_scope", "not_allowed_token_type", "feature_not_enabled", "unknown_method"}


def cmd_search(ctx, a):
    if not a.legacy and a.page == 1 and search_rts(ctx, a) is not None:
        return
    if a.cursor:
        raise UsageError("--cursor needs Real-time Search; drop --legacy/--page", "search")
    search_legacy(ctx, a)


def search_rts(ctx, a):
    """Search with assistant.search.context. Returns None to fall back to search.messages."""
    query = search_rewrite(ctx, " ".join(a.query), ids=True)
    channel_types = ["public_channel"]
    if not a.public:
        channel_types += ["private_channel", "mpim", "im"]
    params = {
        "query": query,
        "content_types": ["messages"],
        "channel_types": channel_types,
        "sort": a.sort,
        "sort_dir": "asc" if a.asc else "desc",
        "include_bots": True,
        "include_message_blocks": True,
        "include_context_messages": a.context,
        "disable_semantic_search": a.keyword or None,
        "cursor": a.cursor,
    }
    want = max(1, min(a.count, 100))
    hits = []
    cursor = None
    while len(hits) < want:
        params["limit"] = min(20, want - len(hits))
        r = ctx.client.call("assistant.search.context", params, json_body=True, allow_error=True)
        if not r.get("ok"):
            err = r.get("error")
            if not hits and not a.cursor and err in RTS_FALLBACK_ERRORS:
                warn(f"Real-time Search unavailable ({err}); using search.messages")
                return None
            raise SlackError(format_api_error("assistant.search.context", r))
        page = (r.get("results") or {}).get("messages") or []
        hits.extend(page)
        cursor = (r.get("response_metadata") or {}).get("next_cursor") or None
        if not cursor or not page:
            break
        params["cursor"] = cursor
    msgs = [rts_message(h) for h in hits]
    rend = Renderer(ctx)
    rend.prefetch(msgs)
    rows = []
    for h, m in zip(hits, msgs):
        n = rend.message(m, h.get("channel_id"))
        thread = None
        if h.get("permalink"):
            q = urllib.parse.parse_qs(urllib.parse.urlsplit(h["permalink"]).query)
            thread = (q.get("thread_ts") or [None])[0]
        n["thread_ts"] = thread
        n["is_reply"] = bool(thread and thread != n["ts"])
        n["channel_name"] = ctx.conv_label(h["channel_id"]) if h.get("channel_id") else "?"
        if a.context:
            around = h.get("context_messages") or {}
            n["context"] = {
                side: [rend.message(rts_message(c), h.get("channel_id")) for c in around.get(side) or []]
                for side in ("before", "after")
            }
        rows.append(n)
    if ctx.json:
        emit_json(
            {"query": query, "backend": "assistant.search.context", "next_cursor": cursor, "matches": rows}
        )
        return rows
    if query != " ".join(a.query):
        out(f"-- query: {query} --")
    out(f"-- {len(rows)} matches" + (" (public only)" if a.public else "") + " --")
    for n in rows:
        for c in (n.get("context") or {}).get("before") or []:
            out(rend.line(c, "    "))
        line = rend.line(n)
        head, sep, rest = line.partition("] ")
        out(f"{head}] {n['channel_name']} {rest}" if sep else line)
        for c in (n.get("context") or {}).get("after") or []:
            out(rend.line(c, "    "))
    if cursor:
        out(f"-- more: slack search {json.dumps(' '.join(a.query))} --cursor {cursor} --")
    return rows


def rts_message(h):
    """Shape a Real-time Search hit like a conversations.history message."""
    m = {
        "ts": h.get("message_ts") or h.get("ts"),
        "user": h.get("author_user_id") or h.get("user_id"),
        "text": h.get("content") or h.get("text") or "",
        "blocks": h.get("blocks") or [],
        "permalink": h.get("permalink"),
    }
    if h.get("is_author_bot"):
        m["subtype"] = "bot_message"
        m["username"] = h.get("author_name")
    return m


def search_legacy(ctx, a):
    query = search_rewrite(ctx, " ".join(a.query))
    params = {
        "query": query,
        "count": min(a.count, 100),
        "page": a.page,
        "sort": a.sort,
        "sort_dir": "asc" if a.asc else "desc",
        "highlight": False,
    }
    r = ctx.client.call("search.messages", params)
    msgs = r.get("messages") or {}
    matches = msgs.get("matches") or []
    if a.public:
        matches = [
            m
            for m in matches
            if not any(
                (m.get("channel") or {}).get(k) for k in ("is_private", "is_im", "is_mpim", "is_group")
            )
        ]
    rend = Renderer(ctx)
    rend.prefetch(matches)
    rows = []
    for m in matches:
        chan = m.get("channel") or {}
        n = rend.message(m, chan.get("id"))
        thread = None
        if m.get("permalink"):
            q = urllib.parse.parse_qs(urllib.parse.urlsplit(m["permalink"]).query)
            thread = (q.get("thread_ts") or [None])[0]
        n["thread_ts"] = thread or n.get("thread_ts")
        n["is_reply"] = bool(thread and thread != n["ts"])
        if chan.get("is_im"):
            n["channel_name"] = "@" + ctx.user_name(chan.get("user")) if chan.get("user") else "dm"
        elif chan.get("is_mpim"):
            n["channel_name"] = "group dm"
        else:
            n["channel_name"] = "#" + (chan.get("name") or chan.get("id") or "?")
        rows.append(n)
    paging = msgs.get("paging") or msgs.get("pagination") or {}
    total = msgs.get("total", 0)
    pages = paging.get("pages") or paging.get("page_count") or 1
    if ctx.json:
        return emit_json({"query": query, "total": total, "page": a.page, "pages": pages, "matches": rows})
    if query != " ".join(a.query):
        out(f"-- query: {query} --")
    out(f"-- {total} total matches, page {a.page}/{pages}" + (" (public only)" if a.public else "") + " --")
    for n in rows:
        line = rend.line(n)
        # Insert the channel name after the timestamp bracket.
        head, sep, rest = line.partition("] ")
        out(f"{head}] {n['channel_name']} {rest}" if sep else line)
    if a.page < pages:
        out(f"-- more: slack search {json.dumps(' '.join(a.query))} --legacy --page {a.page + 1} --")


def cmd_search_files(ctx, a):
    query = search_rewrite(ctx, " ".join(a.query))
    r = ctx.client.call(
        "search.files",
        {
            "query": query,
            "count": min(a.count, 100),
            "page": a.page,
            "sort": a.sort,
            "sort_dir": "asc" if a.asc else "desc",
            "highlight": False,
        },
    )
    files = r.get("files") or {}
    matches = files.get("matches") or []
    ctx.prefetch_users(f.get("user") for f in matches)
    rows = []
    for f in matches:
        i = Renderer.file_info(f)
        i.update(
            created=f.get("created"),
            time=iso(f.get("created")),
            user=f.get("user"),
            author=ctx.user_name(f.get("user")) if f.get("user") else "?",
        )
        rows.append(i)
    paging = files.get("paging") or {}
    pages = paging.get("pages") or 1
    if ctx.json:
        return emit_json(
            {"query": query, "total": files.get("total", 0), "page": a.page, "pages": pages, "files": rows}
        )
    out(f"-- {files.get('total', 0)} files, page {a.page}/{pages} --")
    for i in rows:
        kind = "canvas" if i["is_canvas"] else "list" if i["is_list"] else i["mimetype"] or i["filetype"]
        out(
            f'[{i["time"]}] {i["id"]}  "{i["title"] or i["name"]}"  {kind}  by {i["author"]}  <{i["permalink"]}>'
        )


def fetch_history(ctx, cid, oldest=None, latest=None, limit=50, cursor=None, inclusive=False):
    params = {"channel": cid, "oldest": oldest, "latest": latest}
    if inclusive:
        params["inclusive"] = True
    if cursor:
        params["cursor"] = cursor
    msgs = []
    next_cursor = None
    while True:
        want = 200 if limit is None else max(1, min(200, limit - len(msgs)))
        params["limit"] = want
        r = ctx.client.call("conversations.history", params)
        msgs.extend(r.get("messages") or [])
        next_cursor = (r.get("response_metadata") or {}).get("next_cursor") or None
        if not r.get("has_more") or not next_cursor:
            next_cursor = None
            break
        if limit is not None and len(msgs) >= limit:
            break
        params["cursor"] = next_cursor
    if limit is not None and len(msgs) > limit:
        msgs = msgs[:limit]
    return msgs, next_cursor


def fetch_replies(ctx, cid, ts, limit=None):
    msgs = list(
        ctx.client.paginate(
            "conversations.replies", {"channel": cid, "ts": ts}, "messages", limit=limit, page_size=200
        )
    )
    # Paginated replies repeat the parent on every page.
    seen = set()
    uniq = []
    for m in msgs:
        if m.get("ts") not in seen:
            seen.add(m.get("ts"))
            uniq.append(m)
    return uniq


def cmd_history(ctx, a):
    cid = ctx.resolve_conv(a.channel)
    oldest = f"{parse_time(a.since):.6f}" if a.since else None
    latest = f"{parse_time(a.until):.6f}" if a.until else None
    if oldest and not latest:
        # With only `oldest`, Slack returns the OLDEST page of the window;
        # pinning `latest` makes --limit keep the newest messages.
        latest = f"{time.time() + 60:.6f}"
    limit = None if a.all else a.limit
    msgs, cursor = fetch_history(ctx, cid, oldest, latest, limit, a.cursor)
    msgs.reverse()
    replies = {}
    if a.replies:
        parents = [m for m in msgs if m.get("reply_count")]
        with concurrent.futures.ThreadPoolExecutor(WORKERS) as ex:
            futs = {m["ts"]: ex.submit(fetch_replies, ctx, cid, m["ts"]) for m in parents}
            for ts, fut in futs.items():
                try:
                    replies[ts] = [r for r in fut.result() if r.get("ts") != ts]
                except SlackError as e:
                    warn(f"replies for {ts}: {e}")
    rend = Renderer(ctx)
    rend.prefetch(msgs + [r for rs in replies.values() for r in rs])
    rows = []
    for m in msgs:
        n = rend.message(m, cid)
        if m.get("ts") in replies:
            n["replies"] = [rend.message(r, cid) for r in replies[m["ts"]]]
        rows.append(n)
    label = ctx.conv_label(cid)
    if ctx.json:
        return emit_json(
            {
                "channel": cid,
                "channel_name": label,
                "messages": rows,
                "has_more": bool(cursor),
                "next_cursor": cursor,
            }
        )
    out(f"== {label} ({cid}): {len(rows)} messages ==")
    for n in rows:
        out(rend.line(n))
        for r in n.get("replies") or []:
            out(rend.line(r, indent="    ↳ "))
    if cursor:
        window = "".join(f" --{k} {v}" for k, v in (("since", a.since), ("until", a.until)) if v)
        out(f"-- more: older messages available; slack history {cid}{window} --cursor {cursor} (or --all) --")


def cmd_thread(ctx, a):
    cid, ts, thread_ts, rest = message_ref(ctx, a.ref, "thread")
    if rest:
        raise UsageError(f"unexpected arguments: {' '.join(rest)}")
    parent = thread_ts or ts
    msgs = fetch_replies(ctx, cid, parent, a.limit)
    if msgs and msgs[0].get("thread_ts") and msgs[0]["thread_ts"] != parent:
        # A reply ts was given without thread_ts: open its parent thread.
        parent = msgs[0]["thread_ts"]
        msgs = fetch_replies(ctx, cid, parent, a.limit)
    rend = Renderer(ctx)
    rend.prefetch(msgs)
    rows = [rend.message(m, cid, target_ts=ts) for m in msgs]
    label = ctx.conv_label(cid)
    parent_link = ctx.permalink(cid, parent)
    if ctx.json:
        return emit_json(
            {
                "channel": cid,
                "channel_name": label,
                "thread_ts": parent,
                "linked_ts": ts,
                "parent_permalink": parent_link,
                "messages": rows,
            }
        )
    replies = max(len(rows) - 1, 0)
    note = "" if ts == parent else f", » marks the linked reply {ts}"
    out(f"== thread in {label}: {replies} replies, parent <{parent_link}>{note} ==")
    for n in rows:
        out(rend.line(n, indent="" if n["ts"] == parent else "  "))
    if a.limit and len(rows) >= a.limit:
        out(f"-- output capped at {a.limit} messages; drop --limit for the whole thread --")


def cmd_unreads(ctx, a):
    t0 = time.time()
    types = "public_channel,private_channel,mpim,im"
    if a.types:
        types = ",".join(
            {"public": "public_channel", "private": "private_channel", "dm": "im", "group": "mpim"}.get(
                t.strip(), t.strip()
            )
            for t in a.types.split(",")
        )
    if a.channel:
        wanted = [ctx.resolve_conv(c) for c in a.channel]
        convs = [{"id": c} for c in wanted]
    else:
        convs = list(
            ctx.client.paginate(
                "users.conversations", {"types": types, "exclude_archived": True}, "channels", page_size=999
            )
        )
    me = ctx.self_id()

    def check(c):
        cid = c["id"]
        if c.get("user") == "USLACKBOT":
            return None
        info = ctx.client.call("conversations.info", {"channel": cid}, allow_error=True)
        if not info.get("ok"):
            return {"id": cid, "error": format_api_error("conversations.info", info)}
        ch = info["channel"]
        last_read = str(ch.get("last_read") or "0")
        try:
            lr = float(last_read)
        except ValueError:
            lr = 0.0
        latest = (ch.get("latest") or {}).get("ts")
        if "unread_count_display" in ch and not ch.get("unread_count_display"):
            return None
        if latest and lr and float(latest) <= lr:
            return None
        params_oldest = last_read if lr > 0 else None
        try:
            msgs, more = fetch_history(ctx, cid, oldest=params_oldest, limit=a.limit)
        except SlackError as e:
            return {"id": cid, "error": str(e)}
        msgs = [
            m
            for m in msgs
            if m.get("user") != me and m.get("subtype") not in ("channel_join", "channel_leave")
        ]
        if not msgs:
            return None
        return {
            "id": cid,
            "info": conv_summary(ch),
            "last_read": last_read,
            "never_read": lr == 0,
            "messages": msgs,
            "truncated": bool(more),
            "unread_count": ch.get("unread_count_display"),
        }

    results = []
    errors = []
    with concurrent.futures.ThreadPoolExecutor(WORKERS) as ex:
        for res in ex.map(check, convs):
            if res is None:
                continue
            if "error" in res:
                errors.append(res)
            else:
                results.append(res)
    for res in results:
        with ctx._lock:
            ctx.convs()[res["id"]] = res["info"]
            ctx._convs_dirty = True
    results.sort(key=lambda r: -max(float(m["ts"]) for m in r["messages"]))
    rend = Renderer(ctx)
    rend.prefetch([m for r in results for m in r["messages"]])
    marked = []
    if a.mark:
        for r in results:
            newest = max(r["messages"], key=lambda m: float(m["ts"]))["ts"]
            if a.dry_run:
                marked.append({"channel": r["id"], "ts": newest, "dry_run": True})
                continue
            resp = ctx.client.call("conversations.mark", {"channel": r["id"], "ts": newest}, allow_error=True)
            if resp.get("ok"):
                marked.append({"channel": r["id"], "ts": newest})
            else:
                errors.append({"id": r["id"], "error": format_api_error("conversations.mark", resp)})
    for e in errors:
        warn(f"{ctx.conv_label(e['id'])}: {e['error']}")
    if ctx.json:
        return emit_json(
            {
                "conversations": [
                    {
                        "id": r["id"],
                        "name": ctx.conv_label(r["id"]),
                        "last_read": r["last_read"],
                        "never_read": r["never_read"],
                        "truncated": r["truncated"],
                        "unread_count": r["unread_count"]
                        if r["unread_count"] is not None
                        else len(r["messages"]),
                        "messages": [rend.message(m, r["id"]) for m in reversed(r["messages"])],
                    }
                    for r in results
                ],
                "marked": marked,
                "errors": errors,
                "checked": len(convs),
                "seconds": round(time.time() - t0, 2),
            }
        )
    if not results:
        out(f"No unread messages ({len(convs)} conversations checked in {time.time() - t0:.1f}s).")
    for r in results:
        n = r["unread_count"] if r["unread_count"] is not None else len(r["messages"])
        more = "+" if r["truncated"] else ""
        note = ", never opened" if r["never_read"] else ""
        out(f"== {ctx.conv_label(r['id'])} ({r['id']}): {n}{more} unread{note} ==")
        for m in reversed(r["messages"]):
            out(rend.line(rend.message(m, r["id"])))
        if r["truncated"]:
            out(f"-- more unread: slack history {r['id']} --since {r['last_read']} --all --")
    if results:
        out(
            f"-- {len(results)} conversations with unreads ({len(convs)} checked, "
            f"{time.time() - t0:.1f}s); thread-only replies are not included --"
        )
    for mk in marked:
        verb = "would mark" if mk.get("dry_run") else "marked"
        out(f"{verb} {ctx.conv_label(mk['channel'])} read through {mk['ts']}")
    if errors and not results and len(errors) == len(convs):
        raise SlackError("every conversation failed")


def cmd_pins(ctx, a):
    cid = ctx.resolve_conv(a.channel)
    items = ctx.client.call("pins.list", {"channel": cid}).get("items") or []
    rend = Renderer(ctx)
    rend.prefetch([i.get("message") or {} for i in items])
    rows = []
    for i in items:
        if i.get("type") == "message" and i.get("message"):
            rows.append({"type": "message", "message": rend.message(i["message"], cid)})
        elif i.get("file"):
            rows.append({"type": "file", "file": Renderer.file_info(i["file"])})
        else:
            rows.append({"type": i.get("type")})
    if ctx.json:
        return emit_json({"channel": cid, "pins": rows})
    out(f"== {ctx.conv_label(cid)}: {len(rows)} pins ==")
    for r in rows:
        if r["type"] == "message":
            out(rend.line(r["message"]))
        elif r["type"] == "file":
            f = r["file"]
            out(f'[file {f["id"]} "{f["name"]}" {f["mimetype"]} {f["permalink"]}]')
        else:
            out(f"[{r['type']}]")


def cmd_bookmarks(ctx, a):
    cid = ctx.resolve_conv(a.channel)
    items = ctx.client.call("bookmarks.list", {"channel_id": cid}).get("bookmarks") or []
    if ctx.json:
        return emit_json({"channel": cid, "bookmarks": items})
    out(f"== {ctx.conv_label(cid)}: {len(items)} bookmarks ==")
    for b in items:
        emoji = f"{b['emoji']} " if b.get("emoji") else ""
        out(f"{b.get('id')}  {emoji}{b.get('title')}  {b.get('link') or ''}  ({b.get('type')})")


def cmd_reactions(ctx, a):
    cid, ts, _thread, rest = message_ref(ctx, a.ref)
    if rest:
        raise UsageError(f"unexpected arguments: {' '.join(rest)}")
    r = ctx.client.call("reactions.get", {"channel": cid, "timestamp": ts, "full": True})
    msg = r.get("message") or {}
    reactions = msg.get("reactions") or []
    ctx.prefetch_users(u for x in reactions for u in x.get("users") or [])
    rows = [
        {
            "name": x.get("name"),
            "count": x.get("count"),
            "users": [{"id": u, "name": ctx.user_name(u)} for u in x.get("users") or []],
        }
        for x in reactions
    ]
    if ctx.json:
        return emit_json({"channel": cid, "ts": ts, "permalink": ctx.permalink(cid, ts), "reactions": rows})
    if not rows:
        out("no reactions")
    for x in rows:
        out(f":{x['name']}: x{x['count']}  " + ", ".join("@" + u["name"] for u in x["users"]))


# --------------------------------------------------------------------------
# Files, canvases, lists
# --------------------------------------------------------------------------


class CanvasText(html.parser.HTMLParser):
    """Convert Slack canvas HTML into readable Markdown-ish text."""

    BLOCK = {"p", "div", "h1", "h2", "h3", "h4", "li", "tr", "blockquote", "pre", "ul", "ol", "table"}

    def __init__(self, show_ids=False):
        super().__init__(convert_charrefs=True)
        self.out = []
        self.line = []
        self.list_stack = []
        self.href = None
        self.show_ids = show_ids
        self.in_pre = False
        self.cells = None
        self.checklist = 0
        self.div_stack = []

    def _flush(self):
        text = "".join(self.line).rstrip()
        self.line = []
        if text.strip():
            self.out.append(text)

    def handle_starttag(self, tag, attrs):
        at = dict(attrs)
        if tag in self.BLOCK and tag not in ("ul", "ol", "table", "div"):
            self._flush()
        sid = at.get("id") or ""
        if (
            self.show_ids
            and tag in ("h1", "h2", "h3", "p", "li", "pre", "blockquote", "tr")
            and sid.startswith("temp:C:")
        ):
            self.line.append(f"{{{sid}}} ")
        if tag in ("h1", "h2", "h3", "h4"):
            self.line.append("#" * int(tag[1]) + " ")
        elif tag == "div":
            is_check = at.get("data-section-style") == "7"
            self.div_stack.append(is_check)
            self.checklist += is_check
        elif tag in ("ul", "ol"):
            self._flush()
            self.list_stack.append(tag)
        elif tag == "li":
            depth = max(len(self.list_stack) - 1, 0)
            kind = self.list_stack[-1] if self.list_stack else "ul"
            cls = at.get("class") or ""
            if self.checklist:
                bullet = "- [x] " if "checked" in cls else "- [ ] "
            else:
                bullet = "1. " if kind == "ol" else "- "
            self.line.append("  " * depth + bullet)
        elif tag == "br":
            if self.in_pre:
                self.line.append("\n")
            else:
                self._flush()
        elif tag in ("a", "lnk"):
            self.href = at.get("href")
            self._link_start = len(self.line)
        elif tag == "blockquote":
            self.line.append("> ")
        elif tag == "pre":
            self.in_pre = True
            self.line.append("```\n")
        elif tag == "code" and not self.in_pre:
            self.line.append("`")
        elif tag in ("b", "strong"):
            self.line.append("*")
        elif tag in ("i", "em"):
            self.line.append("_")
        elif tag == "tr":
            self.cells = []
        elif tag in ("td", "th"):
            if self.cells is not None:
                self.cells.append(len(self.line))
        elif tag == "img":
            self.line.append(f"[image: {at.get('alt') or ''} {at.get('src') or ''}]")
        elif tag == "hr":
            self._flush()
            self.out.append("---")

    def handle_endtag(self, tag):
        if tag in ("a", "lnk"):
            text = "".join(self.line[getattr(self, "_link_start", len(self.line)) :])
            if self.href and self.href not in text:
                self.line.append(f" ({self.href})")
            self.href = None
        elif tag == "code" and not self.in_pre:
            self.line.append("`")
        elif tag in ("b", "strong"):
            self.line.append("*")
        elif tag in ("i", "em"):
            self.line.append("_")
        elif tag == "pre":
            self.line.append("\n```")
            self.in_pre = False
            self._flush()
        elif tag in ("td", "th"):
            self.line.append(" | ")
        elif tag == "tr":
            self.cells = None
            self._flush()
        elif tag in ("ul", "ol"):
            self._flush()
            if self.list_stack:
                self.list_stack.pop()
        elif tag == "div":
            if self.div_stack and self.div_stack.pop():
                self.checklist -= 1
            self._flush()
        elif tag in self.BLOCK:
            self._flush()

    def handle_data(self, data):
        if not self.in_pre:
            data = re.sub(r"\s+", " ", data)
            if not self.line and not data.strip():
                return
        self.line.append(data)

    def text(self):
        self._flush()
        return "\n".join(self.out)


def canvas_to_text(raw, show_ids=False):
    p = CanvasText(show_ids)
    try:
        p.feed(raw)
        p.close()
        return p.text()
    except Exception:  # noqa: BLE001 - fall back to tag stripping
        return html.unescape(re.sub(r"<[^>]+>", " ", raw))


def files_info(ctx, fid):
    return ctx.client.call("files.info", {"file": fid})["file"]


def is_text_file(f):
    mime = (f.get("mimetype") or "").lower()
    ftype = (f.get("filetype") or "").lower()
    return bool(TEXT_MIME_RE.match(mime)) or ftype in TEXT_FILETYPES or f.get("mode") == "snippet"


def safe_name(name):
    name = re.sub(r"[^\w.\-]+", "_", name or "file").strip("._") or "file"
    return name[:120]


def cmd_file(ctx, a):
    ref = a.ref
    out_path = a.out or a.outfile
    if "/archives/" in ref:
        # A message permalink: list its files.
        cid, ts, thread, _ = message_ref(ctx, [ref])
        msgs = fetch_replies(ctx, cid, thread or ts)
        msg = next((m for m in msgs if m.get("ts") == ts), None)
        files = (msg or {}).get("files") or []
        if not files:
            raise SlackError("that message has no files")
        if len(files) > 1 and not a.info:
            rend = Renderer(ctx)
            for f in files:
                out(rend.file_line(f))
            raise SlackError("message has several files; pass one file ID")
        ref = files[0]["id"]
    fid = file_id_from(ref)
    f = files_info(ctx, fid)
    info = Renderer.file_info(f)
    info.update(user=f.get("user"), created=f.get("created"), time=iso(f.get("created")))
    if a.info:
        if ctx.json:
            return emit_json(info)
        for k in ("id", "name", "title", "mimetype", "filetype", "size", "time", "url_private", "permalink"):
            out(f"{k + ':':<12} {info[k]}")
        return
    if info["is_canvas"]:
        return show_canvas(ctx, f, a, out_path)
    url = f.get("url_private_download") or f.get("url_private")
    if not url:
        raise SlackError(f"{fid} has no downloadable content (external or deleted file)")
    ctype, body = ctx.client.download(url)
    if "text/html" in ctype.lower() and "html" not in (info["mimetype"] + info["filetype"]).lower():
        raise SlackError("Slack returned an HTML page instead of the file (no access, or a login page)")
    if not out_path and is_text_file(f) and not a.save:
        text = body.decode("utf-8", "replace")
        if ctx.json:
            return emit_json({**info, "content": text})
        warn(f'{info["id"]} "{info["name"]}" {info["mimetype"]} {len(body)} bytes')
        sys.stdout.write(text if text.endswith("\n") else text + "\n")
        return
    if not out_path:
        d = os.path.join(tempfile.gettempdir(), "slack-cli-files", fid)
        os.makedirs(d, exist_ok=True)
        out_path = os.path.join(d, safe_name(f.get("name") or fid))
    elif os.path.isdir(out_path):
        out_path = os.path.join(out_path, safe_name(f.get("name") or fid))
    with open(out_path, "wb") as fh:
        fh.write(body)
    if ctx.json:
        return emit_json({**info, "saved": out_path, "bytes": len(body)})
    out(f"saved {out_path} ({info['mimetype'] or info['filetype']}, {len(body)} bytes)")


def show_canvas(ctx, f, a, out_path=None):
    ctype, body = ctx.client.download(f["url_private"])
    raw = body.decode("utf-8", "replace")
    if getattr(a, "html", False):
        text = raw
    else:
        text = canvas_to_text(raw, show_ids=getattr(a, "ids", False))
    title = f.get("title") or f.get("name")
    if out_path:
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
        out(f"saved {out_path}")
        return
    if ctx.json:
        return emit_json({**Renderer.file_info(f), "title": title, "content": text})
    out(f'== canvas {f["id"]} "{title}" <{f.get("permalink")}> ==')
    out(text)


def cmd_canvas(ctx, a):
    if a.action == "create":
        a.text = ([a.canvas] if a.canvas else []) + list(a.text)
        a.canvas = None
    elif not a.canvas:
        raise UsageError(f"canvas {a.action} needs a canvas ID or permalink", "canvas")
    if a.action == "read":
        f = files_info(ctx, file_id_from(a.canvas))
        return show_canvas(ctx, f, a)
    if a.action == "sections":
        criteria = {}
        if a.type:
            criteria["section_types"] = [t.strip() for t in a.type.split(",") if t.strip()]
        if a.contains:
            criteria["contains_text"] = a.contains
        if not criteria:
            criteria["section_types"] = ["any_header"]
        r = ctx.client.call(
            "canvases.sections.lookup", {"canvas_id": file_id_from(a.canvas), "criteria": criteria}
        )
        secs = r.get("sections") or []
        if ctx.json:
            return emit_json({"sections": secs})
        for s in secs:
            out(s.get("id"))
        if not secs:
            out("no matching sections")
        return
    if a.action == "create":
        params = {"title": a.title}
        if a.text or a.file:
            params["document_content"] = {
                "type": "markdown",
                "markdown": read_text(a.text, a.file, "canvas content"),
            }
        if a.channel:
            params["channel_id"] = ctx.resolve_conv(a.channel)
        return write_call(
            ctx,
            a,
            "canvases.create",
            params,
            json_body=True,
            describe=f"create canvas {a.title!r}"
            + (f" as a tab in {ctx.conv_label(params['channel_id'])}" if a.channel else ""),
            done=lambda r: (
                f"created canvas {r.get('canvas_id')} "
                f"<{ctx.base_url()}/docs/{ctx.team().get('team_id')}/{r.get('canvas_id')}>"
            ),
        )
    if a.action == "edit":
        cid = file_id_from(a.canvas)
        op = a.op
        change = {"operation": op}
        if op in ("insert_after", "insert_before", "delete") and not a.section:
            raise UsageError(f"--op {op} needs --section ID; find IDs with: slack canvas sections", "canvas")
        if a.section:
            change["section_id"] = a.section
        if op == "rename":
            change["title_content"] = {"type": "markdown", "markdown": read_text(a.text, a.file, "title")}
        elif op != "delete":
            change["document_content"] = {
                "type": "markdown",
                "markdown": read_text(a.text, a.file, "canvas content"),
            }
        if op == "replace" and not a.section:
            warn("warning: replace without --section replaces the WHOLE canvas")
        return write_call(
            ctx,
            a,
            "canvases.edit",
            {"canvas_id": cid, "changes": [change]},
            json_body=True,
            describe=f"edit canvas {cid}: {op}",
            done=lambda r: f"edited canvas {cid} ({op})",
        )
    raise UsageError(f"unknown canvas action {a.action}", "canvas")


def list_schema(ctx, list_id):
    r = ctx.client.call("slackLists.items.list", {"list_id": list_id, "limit": 1, "include_list": True})
    lst = r.get("list") or {}
    meta = lst.get("list_metadata") or lst.get("metadata") or {}
    return lst, meta.get("schema") or lst.get("schema") or []


def list_cell_text(ctx, field, col):
    if field.get("text"):
        return field["text"]
    choices = {
        c.get("value"): c.get("label") for c in ((col or {}).get("options") or {}).get("choices") or []
    }
    for key in (
        "select",
        "user",
        "channel",
        "date",
        "number",
        "email",
        "phone",
        "rating",
        "timestamp",
        "link",
        "attachment",
        "message",
    ):
        vals = field.get(key)
        if vals is None:
            continue
        if not isinstance(vals, list):
            vals = [vals]
        if key == "select":
            return ", ".join(choices.get(v, v) for v in vals)
        if key == "user":
            return ", ".join("@" + ctx.user_name(v) for v in vals)
        if key == "channel":
            return ", ".join(ctx.conv_label(v) for v in vals)
        if key == "timestamp":
            return ", ".join(iso(v) for v in vals)
        return ", ".join(json.dumps(v) if isinstance(v, (dict, list)) else str(v) for v in vals)
    if "checkbox" in field:
        return "[x]" if field["checkbox"] else "[ ]"
    if field.get("rich_text"):
        return Renderer(ctx).blocks(field["rich_text"]).replace("\n", " ⏎ ")
    v = field.get("value")
    return "" if v is None else str(v)


def list_fields(ctx, list_id, specs, schema):
    """Convert COL=VALUE specs into typed Lists cell objects."""
    cols = {}
    for c in schema:
        for k in (c.get("id"), c.get("key"), norm(c.get("name") or "")):
            if k:
                cols[k] = c
    cells = []
    for spec in specs:
        name, sep, value = spec.partition("=")
        if not sep:
            raise UsageError(f"--field needs COLUMN=VALUE, got {spec!r}", "list")
        col = cols.get(name) or cols.get(norm(name))
        if not col:
            known = ", ".join(c.get("name") or c.get("key") for c in schema)
            raise SlackError(f"unknown column {name!r} in list {list_id} (columns: {known})")
        t = col.get("type")
        cell = {"column_id": col["id"]}
        items = [v.strip() for v in value.split(",") if v.strip()]
        if t == "text":
            cell["rich_text"] = [
                {
                    "type": "rich_text",
                    "elements": [
                        {"type": "rich_text_section", "elements": [{"type": "text", "text": value}]}
                    ],
                }
            ]
        elif t in ("number", "rating"):
            try:
                cell[t] = [float(value) if "." in value else int(value)]
            except ValueError:
                raise UsageError(f"{name}: {value!r} is not a number", "list") from None
        elif t == "select":
            choices = (col.get("options") or {}).get("choices") or []
            ids = []
            for v in items:
                hit = next(
                    (
                        c["value"]
                        for c in choices
                        if norm(c.get("value")) == norm(v) or norm(c.get("label")) == norm(v)
                    ),
                    None,
                )
                if not hit:
                    opts = ", ".join(c.get("label") or c.get("value") for c in choices)
                    raise SlackError(f"{name}: no option {v!r} (options: {opts})")
                ids.append(hit)
            cell["select"] = ids
        elif t == "user":
            cell["user"] = [ctx.resolve_user(v) for v in items]
        elif t == "channel":
            cell["channel"] = [ctx.resolve_conv(v) for v in items]
        elif t == "date":
            cell["date"] = [
                dt.datetime.fromtimestamp(parse_time(v)).strftime("%Y-%m-%d")
                if not re.match(r"^\d{4}-\d{2}-\d{2}$", v)
                else v
                for v in items
            ]
        elif t == "checkbox":
            cell["checkbox"] = value.strip().lower() in ("1", "true", "yes", "y", "x", "done", "on")
        elif t in ("email", "phone"):
            cell[t] = items
        else:
            raise SlackError(f"{name}: column type {t!r} is not supported by --field; use --cells JSON")
        cells.append(cell)
    return cells


def parse_json_arg(value, what):
    if value.startswith("@"):
        try:
            with open(value[1:], encoding="utf-8") as f:
                value = f.read()
        except OSError as e:
            raise SlackError(f"cannot read {value[1:]}: {e.strerror}") from None
    try:
        return json.loads(value)
    except ValueError as e:
        raise UsageError(f"{what} is not valid JSON: {e}") from None


def cmd_list(ctx, a):
    if a.action == "read":
        lid = file_id_from(a.list)
        params = {"list_id": lid, "include_list": True, "archived": a.archived or None}
        items = []
        lst = {}
        while True:
            params["limit"] = 100
            r = ctx.client.call("slackLists.items.list", params)
            lst = lst or r.get("list") or {}
            items.extend(r.get("items") or [])
            cur = (r.get("response_metadata") or {}).get("next_cursor")
            if not cur or (a.limit and len(items) >= a.limit):
                break
            params["cursor"] = cur
        if a.limit:
            items = items[: a.limit]
        meta = lst.get("list_metadata") or lst.get("metadata") or {}
        schema = meta.get("schema") or lst.get("schema") or []
        cols = {c.get("id"): c for c in schema}
        cols.update({c.get("key"): c for c in schema if c.get("key")})
        rows = []
        for it in items:
            cells = {}
            for fld in it.get("fields") or []:
                col = cols.get(fld.get("column_id")) or cols.get(fld.get("key"))
                cname = (col or {}).get("name") or fld.get("key") or fld.get("column_id")
                cells[cname] = list_cell_text(ctx, fld, col)
            rows.append(
                {
                    "id": it.get("id"),
                    "parent": it.get("parent_record_id"),
                    "created": iso(it.get("date_created")),
                    "cells": cells,
                }
            )
        if ctx.json:
            return emit_json(
                {
                    "list_id": lid,
                    "title": lst.get("title") or lst.get("name"),
                    "columns": [
                        {"id": c.get("id"), "key": c.get("key"), "name": c.get("name"), "type": c.get("type")}
                        for c in schema
                    ],
                    "items": rows,
                }
            )
        out(f'== list {lid} "{lst.get("title") or lst.get("name") or ""}": {len(rows)} items ==')
        if schema:
            out("columns: " + ", ".join(f"{c.get('name')} [{c.get('type')}, {c.get('id')}]" for c in schema))
        for row in rows:
            sub = f" (subtask of {row['parent']})" if row["parent"] else ""
            out(f"{row['id']}{sub}: " + " | ".join(f"{k}: {v}" for k, v in row["cells"].items() if v))
        return
    if not a.list:
        raise UsageError(
            f"list {a.action} needs a " + ("name" if a.action == "create" else "list ID"), "list"
        )
    if a.action == "create":
        params = {"name": a.list, "todo_mode": a.todo or None}
        if a.schema:
            params["schema"] = parse_json_arg(a.schema, "--schema")
        return write_call(
            ctx,
            a,
            "slackLists.create",
            params,
            json_body=True,
            describe=f"create list {a.list!r}",
            done=lambda r: f"created list {r.get('list_id')}",
        )
    if a.action in ("add", "update"):
        lid = file_id_from(a.list)
        if a.cells:
            cells = parse_json_arg(a.cells, "--cells")
        elif a.field:
            _, schema = list_schema(ctx, lid)
            cells = list_fields(ctx, lid, a.field, schema)
        else:
            cells = []
        if a.action == "add":
            params = {"list_id": lid, "initial_fields": cells or None, "parent_item_id": a.parent}
            return write_call(
                ctx,
                a,
                "slackLists.items.create",
                params,
                json_body=True,
                describe=f"add item to list {lid}",
                done=lambda r: f"added item {(r.get('item') or {}).get('id')} to list {lid}",
            )
        if not a.row:
            raise UsageError("list update needs --row RECORD_ID", "list")
        if not cells:
            raise UsageError("list update needs --field COL=VALUE or --cells JSON", "list")
        for c in cells:
            c.setdefault("row_id", a.row)
        return write_call(
            ctx,
            a,
            "slackLists.items.update",
            {"list_id": lid, "cells": cells},
            json_body=True,
            describe=f"update row {a.row} in list {lid}",
            done=lambda r: f"updated row {a.row} in list {lid}",
        )
    raise UsageError(f"unknown list action {a.action}", "list")


# --------------------------------------------------------------------------
# Writes
# --------------------------------------------------------------------------


def write_call(ctx, a, method, params, describe, done, json_body=False, extra=None):
    """Run or dry-run one write call with a uniform report."""
    params = {k: v for k, v in params.items() if v is not None}
    if getattr(a, "dry_run", False):
        report = {"dry_run": True, "action": describe, "method": method, "payload": params}
        if extra:
            report.update(extra)
        if ctx.json:
            return emit_json(report)
        out("DRY RUN - nothing was sent")
        out(f"action:  {describe}")
        out(f"method:  {method}")
        for k, v in (extra or {}).items():
            if isinstance(v, list):
                out(f"{k}:")
                for item in v:
                    out(f"  - {item}")
            else:
                out(f"{k + ':':<8} {v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)}")
        out("payload:")
        out(json.dumps(params, ensure_ascii=False, indent=2))
        return None
    r = ctx.client.call(method, params, json_body=json_body)
    if ctx.json:
        emit_json(r)
    else:
        out(done(r))
    return r


def text_checks(ctx, text, allow_broadcast):
    """Refuse broadcast mentions; return (mentions, warnings)."""
    m = BROADCAST_RE.search(text)
    if m and not allow_broadcast:
        raise SlackError(
            f"refusing to send a broadcast mention ({m.group(0)}); it notifies everyone. "
            "Pass --allow-broadcast only after Michael explicitly confirmed that exact notification"
        )
    mentions = []
    for uid in dict.fromkeys(re.findall(r"<@([UW][A-Z0-9]+)(?:\|[^>]*)?>", text)):
        u = ctx.user(uid)
        mentions.append(
            f"<@{uid}> = @{ctx.user_name(uid)}" + (f" ({u['real_name']})" if u and u.get("real_name") else "")
            if u
            else f"<@{uid}> = UNKNOWN USER"
        )
    for cid in dict.fromkeys(re.findall(r"<#([CG][A-Z0-9]+)(?:\|[^>]*)?>", text)):
        mentions.append(f"<#{cid}> = {ctx.conv_label(cid)}")
    for gid in dict.fromkeys(re.findall(r"<!subteam\^([A-Z0-9]+)(?:\|[^>]*)?>", text)):
        mentions.append(f"<!subteam^{gid}> = @{ctx.group_handle(gid)} (notifies the whole group)")
    if m:
        mentions.append(f"{m.group(0)} = BROADCAST (allowed by --allow-broadcast)")
    warnings = []
    if "**" in text:
        warnings.append("'**' is not Slack bold; use *bold*")
    if re.search(r"^#{1,6} ", text, re.MULTILINE):
        warnings.append("Markdown headings do not render in Slack; use *bold* lines")
    if re.search(r"\[[^\]]+\]\(https?://[^)]+\)", text):
        warnings.append("Markdown links do not render; use <url|label>")
    names = {
        norm(u["name"]): uid
        for uid, u in ctx.users().items()
        if u and u.get("name") and not u.get("is_bot_id")
    }
    for word in dict.fromkeys(re.findall(r"(?<![\w<`/])@([a-zA-Z][\w.\-]+)", text)):
        if norm(word) in names and word.lower() not in ("here", "channel", "everyone"):
            warnings.append(f"plain @{word} does not notify; use <@{names[norm(word)]}>")
    if "cliproxyapi/" in text:
        warnings.append("footer contains a gateway prefix (cliproxyapi/...); use the bare model slug")
    if not FOOTER_RE.search(text):
        warnings.append(
            "no provenance footer ('---' then '<model-slug> · responding on behalf of Michael'); "
            "add it unless Michael asked for no attribution"
        )
    return mentions, warnings


def resolve_thread(ctx, thread_arg, cid):
    """Return (channel, parent thread ts) for --thread TS|PERMALINK."""
    if not thread_arg:
        return cid, None
    if "/archives/" in thread_arg or "app.slack.com/client/" in thread_arg:
        tcid, ts, thread_ts = parse_permalink(thread_arg)
        if cid and cid != tcid and not ID_USER_RE.match(cid):
            raise SlackError(f"--thread permalink is in {tcid}, but the destination is {cid}")
        cid = tcid
        parent = thread_ts or ts
    else:
        if not cid:
            raise UsageError("--thread TS needs a destination channel (or pass a permalink)")
        parent = normalize_ts(thread_arg)
    # Confirm the message exists and climb to the thread parent.
    r = ctx.client.call("conversations.replies", {"channel": cid, "ts": parent, "limit": 1}, allow_error=True)
    if not r.get("ok"):
        raise SlackError(format_api_error("conversations.replies", r) + f" (thread {parent})")
    msgs = r.get("messages") or []
    if msgs and msgs[0].get("thread_ts") and msgs[0]["thread_ts"] != parent:
        parent = msgs[0]["thread_ts"]
    return cid, parent


def is_permalink(s):
    return bool(s) and ("/archives/" in s or "app.slack.com/client/" in s)


def split_dest(ctx, a):
    """With --thread PERMALINK the destination is optional, so argparse may have
    put the first word of the message into `dest`. Decide which it is."""
    if not (a.dest and is_permalink(a.thread)) or a.file or a.text == ["-"]:
        return
    d = a.dest
    explicit = d.startswith(("#", "@", "<")) or ID_CONV_RE.match(d) or ID_USER_RE.match(d) or is_permalink(d)
    if explicit:
        return
    tcid = parse_permalink(a.thread)[0]
    c = ctx.conv(tcid)
    if c and d in (c["name"], *c.get("previous_names", [])):
        return
    a.text = [d] + list(a.text)
    a.dest = None


def message_plan(ctx, a, text, method_extra=None):
    """Resolve destination/thread and validate text for send/schedule."""
    dest = a.dest
    if is_permalink(dest) and not a.thread:
        raise UsageError(
            "the destination is a message permalink; to reply in its thread use "
            "--thread <permalink>, or give the channel to post top-level"
        )
    cid = ctx.resolve_conv(dest, for_write=True) if dest else None
    cid, parent = resolve_thread(ctx, a.thread, cid)
    if not cid:
        raise UsageError("missing destination: give a channel/@user or --thread PERMALINK")
    if a.broadcast and not parent:
        raise UsageError("--broadcast only applies to thread replies (--thread)")
    mentions, warnings = text_checks(ctx, text, a.allow_broadcast)
    params = {
        "channel": cid,
        "text": text,
        "thread_ts": parent,
        "reply_broadcast": True if a.broadcast else None,
    }
    if getattr(a, "no_unfurl", False):
        params["unfurl_links"] = False
        params["unfurl_media"] = False
    if method_extra:
        params.update(method_extra)
    label = (
        ctx.conv_label(cid)
        if not ID_USER_RE.match(cid)
        else f"DM with @{ctx.user_name(cid)} (opened on send)"
    )
    extra = {"destination": f"{label} ({cid})"}
    if parent:
        extra["thread"] = f"{parent} <{ctx.permalink(cid, parent)}>" + (
            " (reply also sent to channel)" if a.broadcast else ""
        )
    extra["mentions"] = mentions or "none"
    if warnings:
        extra["warnings"] = warnings
    for w in warnings:
        warn("warning: " + w)
    return cid, parent, params, extra


def print_text_block(text):
    out("--- message ---")
    out(text)
    out("--- end ---")


def cmd_send(ctx, a):
    split_dest(ctx, a)
    text = read_text(a.text, a.file)
    cid, parent, params, extra = message_plan(ctx, a, text)
    if a.dry_run:
        write_call(ctx, a, "chat.postMessage", params, "send message", None, extra=extra)
        if not ctx.json:
            print_text_block(text)
        return
    r = ctx.client.call("chat.postMessage", params)
    ch = r.get("channel") or cid
    link = ctx.permalink(ch, r.get("ts", ""), parent)
    if ctx.json:
        return emit_json(
            {"ok": True, "channel": ch, "ts": r.get("ts"), "thread_ts": parent, "permalink": link}
        )
    out(f"sent <{link}>")


def cmd_schedule(ctx, a):
    split_dest(ctx, a)
    text = read_text(a.text, a.file)
    post_at = int(parse_time(a.at, future=True))
    now = time.time()
    if post_at <= now + 10:
        raise UsageError(f"--at {a.at!r} is not in the future")
    if post_at > now + 120 * 86400:
        raise UsageError("Slack only schedules up to 120 days ahead")
    cid, parent, params, extra = message_plan(ctx, a, text, {"post_at": post_at})
    if ID_USER_RE.match(cid):
        raise SlackError("schedule needs an existing conversation; open the DM first with: slack open @user")
    extra["post_at"] = (
        f"{post_at} ({dt.datetime.fromtimestamp(post_at).astimezone().isoformat(timespec='minutes')})"
    )
    if a.dry_run:
        write_call(ctx, a, "chat.scheduleMessage", params, "schedule message", None, extra=extra)
        if not ctx.json:
            print_text_block(text)
        return
    r = ctx.client.call("chat.scheduleMessage", params)
    if ctx.json:
        return emit_json(r)
    out(f"scheduled {r.get('scheduled_message_id')} in {ctx.conv_label(cid)} for {extra['post_at']}")


def cmd_scheduled(ctx, a):
    params = {"channel": ctx.resolve_conv(a.channel) if a.channel else None}
    items = list(
        ctx.client.paginate("chat.scheduledMessages.list", params, "scheduled_messages", page_size=100)
    )
    if ctx.json:
        return emit_json({"scheduled_messages": items})
    if not items:
        out("no scheduled messages")
    rend = Renderer(ctx)
    for s in items:
        when = dt.datetime.fromtimestamp(s.get("post_at", 0)).astimezone().isoformat(timespec="minutes")
        text = rend.mrkdwn(s.get("text") or "").replace("\n", " ⏎ ")
        out(
            f"{s.get('id')}  {ctx.conv_label(s.get('channel_id'))} ({s.get('channel_id')})  at {when}: {text}"
        )


def cmd_unschedule(ctx, a):
    cid = ctx.resolve_conv(a.channel)
    write_call(
        ctx,
        a,
        "chat.deleteScheduledMessage",
        {"channel": cid, "scheduled_message_id": a.id},
        describe=f"delete scheduled message {a.id} in {ctx.conv_label(cid)}",
        done=lambda r: f"deleted scheduled message {a.id}",
    )


def fetch_message(ctx, cid, ts):
    r = ctx.client.call("conversations.replies", {"channel": cid, "ts": ts, "limit": 1}, allow_error=True)
    for m in (r.get("messages") or []) if r.get("ok") else []:
        if m.get("ts") == ts:
            return m
    r = ctx.client.call(
        "conversations.history", {"channel": cid, "latest": ts, "oldest": ts, "inclusive": True, "limit": 1}
    )
    for m in r.get("messages") or []:
        if m.get("ts") == ts:
            return m
    raise SlackError(f"no message {ts} in {cid}")


def own_message(ctx, cid, ts):
    m = fetch_message(ctx, cid, ts)
    if m.get("user") != ctx.self_id():
        raise SlackError(f"message {ts} was posted by {Renderer(ctx).author(m)}, not you; refusing")
    return m


def cmd_edit(ctx, a):
    cid, ts, thread, rest = message_ref(ctx, a.ref)
    text = read_text(rest, a.file)
    old = own_message(ctx, cid, ts)
    mentions, warnings = text_checks(ctx, text, a.allow_broadcast)
    for w in warnings:
        warn("warning: " + w)
    extra = {
        "message": f"<{ctx.permalink(cid, ts, thread or old.get('thread_ts'))}>",
        "mentions": mentions or "none",
        "old_text": Renderer(ctx).mrkdwn(old.get("text") or ""),
    }
    r = write_call(
        ctx,
        a,
        "chat.update",
        {"channel": cid, "ts": ts, "text": text},
        describe="edit your message",
        extra=extra,
        done=lambda r: f"edited <{ctx.permalink(cid, ts, thread or old.get('thread_ts'))}>",
    )
    if a.dry_run and not ctx.json:
        print_text_block(text)
    return r


def cmd_delete(ctx, a):
    cid, ts, thread, rest = message_ref(ctx, a.ref)
    if rest:
        raise UsageError(f"unexpected arguments: {' '.join(rest)}")
    old = own_message(ctx, cid, ts)
    extra = {
        "message": f"<{ctx.permalink(cid, ts, thread or old.get('thread_ts'))}>",
        "text": Renderer(ctx).mrkdwn(old.get("text") or ""),
    }
    write_call(
        ctx,
        a,
        "chat.delete",
        {"channel": cid, "ts": ts},
        describe="delete your message",
        extra=extra,
        done=lambda r: f"deleted message {ts} in {ctx.conv_label(cid)}",
    )


def cmd_permalink(ctx, a):
    cid, ts, thread, rest = message_ref(ctx, a.ref)
    if rest:
        raise UsageError(f"unexpected arguments: {' '.join(rest)}")
    r = ctx.client.call("chat.getPermalink", {"channel": cid, "message_ts": ts})
    if ctx.json:
        return emit_json({"channel": cid, "ts": ts, "permalink": r.get("permalink")})
    out(r.get("permalink"))


def cmd_react(ctx, a, remove=False):
    if len(a.args) < 2:
        raise UsageError("expected: <permalink | channel ts> <emoji>", "unreact" if remove else "react")
    emoji = a.args[-1].strip(":")
    cid, ts, _thread, rest = message_ref(ctx, a.args[:-1])
    if rest:
        raise UsageError(f"unexpected arguments: {' '.join(rest)}")
    remove = remove or a.remove
    method = "reactions.remove" if remove else "reactions.add"
    write_call(
        ctx,
        a,
        method,
        {"channel": cid, "timestamp": ts, "name": emoji},
        describe=f"{'remove' if remove else 'add'} :{emoji}: on {ctx.permalink(cid, ts)}",
        done=lambda r: f"{'removed' if remove else 'reacted'} :{emoji}: <{ctx.permalink(cid, ts)}>",
    )


def cmd_create_channel(ctx, a):
    name = a.name.lstrip("#")
    if not re.match(r"^[a-z0-9][a-z0-9_\-]{0,79}$", name):
        raise UsageError("channel names are lowercase letters, digits, - and _ (max 80)")
    write_call(
        ctx,
        a,
        "conversations.create",
        {"name": name, "is_private": a.private},
        describe=f"create {'private' if a.private else 'public'} channel #{name}",
        done=lambda r: (
            f"created #{(r.get('channel') or {}).get('name')} ({(r.get('channel') or {}).get('id')})"
        ),
    )


def cmd_open(ctx, a):
    uids = [ctx.resolve_user(u) for u in a.users]
    names = ", ".join("@" + ctx.user_name(u) for u in uids)
    write_call(
        ctx,
        a,
        "conversations.open",
        {"users": ",".join(uids)},
        describe=f"open {'DM' if len(uids) == 1 else 'group DM'} with {names}",
        done=lambda r: (
            f"{(r.get('channel') or {}).get('id')}  {'DM' if len(uids) == 1 else 'group DM'} with {names}"
        ),
    )


def cmd_invite(ctx, a):
    cid = ctx.resolve_conv(a.channel)
    uids = [ctx.resolve_user(u) for u in a.users]
    names = ", ".join("@" + ctx.user_name(u) for u in uids)
    write_call(
        ctx,
        a,
        "conversations.invite",
        {"channel": cid, "users": ",".join(uids)},
        describe=f"invite {names} to {ctx.conv_label(cid)}",
        done=lambda r: f"invited {names} to {ctx.conv_label(cid)}",
    )


def cmd_upload(ctx, a):
    if a.path == "-":
        data = sys.stdin.buffer.read()
        name = a.name or "stdin.txt"
    else:
        try:
            with open(a.path, "rb") as f:
                data = f.read()
        except OSError as e:
            raise SlackError(f"cannot read {a.path}: {e.strerror}") from None
        name = a.name or os.path.basename(a.path)
    if not data:
        raise UsageError("refusing to upload an empty file")
    cid = ctx.resolve_conv(a.channel, for_write=True) if a.channel else None
    cid, parent = resolve_thread(ctx, a.thread, cid)
    if cid and ID_USER_RE.match(cid):
        raise SlackError("upload needs an existing conversation; open the DM first with: slack open @user")
    comment = None
    if a.comment or a.comment_file:
        comment = read_text([a.comment] if a.comment else [], a.comment_file, "comment")
    mentions, warnings = text_checks(ctx, comment, a.allow_broadcast) if comment else ([], [])
    for w in warnings:
        if not w.startswith("no provenance footer"):
            warn("warning: " + w)
    step1 = {
        k: v for k, v in {"filename": name, "length": len(data), "alt_txt": a.alt}.items() if v is not None
    }
    complete = {
        k: v
        for k, v in {
            "files": [{"id": "<file_id from step 1>", "title": a.title or name}],
            "channel_id": cid,
            "thread_ts": parent,
            "initial_comment": comment,
        }.items()
        if v is not None
    }
    if a.dry_run:
        report = {
            "dry_run": True,
            "action": "upload file",
            "file": {"path": a.path, "name": name, "bytes": len(data)},
            "destination": f"{ctx.conv_label(cid)} ({cid})" if cid else "none (private file, not shared)",
            "thread": f"{parent} <{ctx.permalink(cid, parent)}>" if parent else None,
            "mentions": mentions,
            "steps": [
                {"method": "files.getUploadURLExternal", "payload": step1},
                {"POST": "<upload_url>", "bytes": len(data)},
                {"method": "files.completeUploadExternal", "payload": complete},
            ],
        }
        if ctx.json:
            return emit_json(report)
        out("DRY RUN - nothing was uploaded")
        for k in ("destination", "thread"):
            if report[k]:
                out(f"{k + ':':<12} {report[k]}")
        out(f"{'file:':<12} {a.path} as {name!r} ({len(data)} bytes)")
        out("steps:")
        out(json.dumps(report["steps"], ensure_ascii=False, indent=2))
        return
    r1 = ctx.client.call("files.getUploadURLExternal", step1)
    ctx.client.upload_bytes(r1["upload_url"], data)
    complete["files"][0]["id"] = r1["file_id"]
    r2 = ctx.client.call("files.completeUploadExternal", complete)
    f = (r2.get("files") or [{}])[0]
    if ctx.json:
        return emit_json(
            {
                "ok": True,
                "file": f.get("id"),
                "permalink": f.get("permalink"),
                "channel": cid,
                "thread_ts": parent,
            }
        )
    where = f" to {ctx.conv_label(cid)}" if cid else " (private, not shared)"
    out(f"uploaded {f.get('id')}{where} <{f.get('permalink')}>")


def parse_kv(pairs):
    params = {}
    json_body = False
    for p in pairs:
        m = re.match(r"^([\w.\-\[\]]+)(:=|=)(.*)$", p, re.DOTALL)
        if not m:
            raise UsageError(f"expected key=value or key:=json, got {p!r}", "api")
        key, op, val = m.groups()
        if val.startswith("@") and len(val) > 1 and os.path.exists(val[1:]):
            with open(val[1:], encoding="utf-8") as f:
                val = f.read()
        if op == ":=":
            params[key] = parse_json_arg(val, key)
            json_body = True
        else:
            params[key] = val
    return params, json_body


def cmd_api(ctx, a):
    params, json_body = parse_kv(a.params)
    json_body = json_body or a.json_body
    write = not READ_METHOD_RE.search(a.method)
    if a.dry_run:
        report = {
            "dry_run": True,
            "method": a.method,
            "write": write,
            "content_type": "json" if json_body else "form",
            "payload": params,
        }
        return emit_json(report)
    r = ctx.client.call(a.method, params, json_body=json_body, allow_error=True)
    emit_json(r)
    if not r.get("ok"):
        raise SlackError(format_api_error(a.method, r))


# --------------------------------------------------------------------------
# Help and argument parsing
# --------------------------------------------------------------------------

GLOBAL_HELP = """\
Global flags (any position):
  --json      normalized JSON on stdout (every read command; writes print the API response)
  --refresh   refetch cached users/channels/usergroups (cache: ~/.cache/slack-cli, 6-24h TTL)
  --long      multi-line message bodies instead of one line per message
  -h, --help  help for a command (same as: slack help <command>)"""

COMMANDS = {}


def command(name, summary, usage, aliases=()):
    def deco(fn):
        COMMANDS[name] = {"fn": fn, "summary": summary, "usage": usage, "aliases": aliases}
        for al in aliases:
            COMMANDS[al] = {"fn": fn, "summary": summary, "usage": usage, "alias_of": name}
        return fn

    return deco


GROUPS = [
    (
        "Read",
        [
            "search",
            "search-files",
            "history",
            "thread",
            "unreads",
            "file",
            "canvas read",
            "list read",
            "reactions",
            "pins",
            "bookmarks",
            "scheduled",
            "permalink",
        ],
    ),
    (
        "People and conversations",
        ["whoami", "users", "user", "channels", "conversations", "members", "usergroups", "emoji"],
    ),
    (
        "Write (only on an explicit request; all support --dry-run)",
        [
            "send",
            "schedule",
            "unschedule",
            "edit",
            "delete",
            "react",
            "unreact",
            "upload",
            "create-channel",
            "open",
            "invite",
            "canvas create|edit|sections",
            "list create|add|update",
        ],
    ),
    ("Raw", ["api"]),
]

MAIN_HELP = """\
slack - Slack Web API from the command line, for Michael and his coding agents.

Usage: slack <command> [args] [--json] [--refresh]
       slack help <command>

{groups}

{global_help}

References:
  conversations  #name, name (fuzzy), C/G/D ID, permalink, or @user / email for a DM
  users          @handle, display or real name (case-insensitive, fuzzy), email, U ID, or <@U..>
  messages       a permalink (reply links with ?thread_ts= work), or: <channel> <ts>
  times          2d, 5h, 30m, 1w, today, yesterday, YYYY-MM-DD, YYYY-MM-DDTHH:MM, epoch ts

Text output: one message per line as
  [ts time] author: text [markers]  <permalink>
where ⏎ marks a line break, "» " marks the message a permalink pointed at, and bot
content from blocks, attachments, and files is included.

Auth: the xoxp user token of the internal slack-cli app, read from the sops-nix secret
~/.config/sops-nix/secrets/keys/slack-token. Never read that file yourself; use
`slack api <method> key=value` for anything not covered here.

Out of scope (needs undocumented APIs or a browser xoxc token): native Slack drafts,
unread thread replies (Threads view), saved items / Later, huddles, and activity.
"""


def main_help():
    groups = []
    for title, names in GROUPS:
        groups.append(title + ":")
        for n in names:
            key = n.split()[0]
            summary = COMMANDS[key]["summary"] if key in COMMANDS else ""
            if key in ("canvas", "list"):
                summary = {
                    "canvas read": "read a canvas as text",
                    "list read": "read the items of a Slack List",
                    "canvas create|edit|sections": "create or edit a canvas; find section IDs",
                    "list create|add|update": "create a List, add or update items",
                }[n]
            groups.append(f"  {n:<28} {summary}")
        groups.append("")
    return MAIN_HELP.format(groups="\n".join(groups).rstrip(), global_help=GLOBAL_HELP)


def command_help(name):
    c = COMMANDS[name]
    real = c.get("alias_of", name)
    text = f"slack {real} - {c['summary']}\n\n{c['usage'].rstrip()}\n\n{GLOBAL_HELP}\n"
    if COMMANDS[real].get("aliases"):
        text += f"\nAliases: {', '.join(COMMANDS[real]['aliases'])}\n"
    return text


class Parser(argparse.ArgumentParser):
    def __init__(self, command_name, **kw):
        super().__init__(prog=f"slack {command_name}", add_help=False, allow_abbrev=False, **kw)
        self.command_name = command_name

    def error(self, message):
        raise UsageError(message, self.command_name)


def add_dry(p):
    p.add_argument("--dry-run", action="store_true")


def add_send_opts(p):
    p.add_argument("dest", nargs="?")
    p.add_argument("text", nargs="*")
    p.add_argument("--file", "-f")
    p.add_argument("--thread", "-t")
    p.add_argument("--broadcast", action="store_true")
    p.add_argument("--allow-broadcast", action="store_true")
    p.add_argument("--no-unfurl", action="store_true")
    add_dry(p)


def build_parser(name):
    p = Parser(name)
    if name == "search":
        p.add_argument("query", nargs="+")
        p.add_argument("--count", "-n", type=int, default=20)
        p.add_argument("--cursor")
        p.add_argument("--page", type=int, default=1)
        p.add_argument("--sort", choices=["timestamp", "score"], default="timestamp")
        p.add_argument("--asc", action="store_true")
        p.add_argument("--public", action="store_true")
        p.add_argument("--context", action="store_true")
        p.add_argument("--keyword", action="store_true")
        p.add_argument("--legacy", action="store_true")
    elif name == "search-files":
        p.add_argument("query", nargs="+")
        p.add_argument("--count", "-n", type=int, default=20)
        p.add_argument("--page", type=int, default=1)
        p.add_argument("--sort", choices=["timestamp", "score"], default="timestamp")
        p.add_argument("--asc", action="store_true")
    elif name == "history":
        p.add_argument("channel")
        p.add_argument("--since")
        p.add_argument("--until")
        p.add_argument("--limit", "-n", type=int, default=50)
        p.add_argument("--all", action="store_true")
        p.add_argument("--cursor")
        p.add_argument("--replies", action="store_true")
    elif name == "thread":
        p.add_argument("ref", nargs="+")
        p.add_argument("--limit", "-n", type=int)
    elif name == "unreads":
        p.add_argument("--channel", "-c", action="append")
        p.add_argument("--types")
        p.add_argument("--limit", "-n", type=int, default=20)
        p.add_argument("--mark", action="store_true")
        add_dry(p)
    elif name == "users":
        p.add_argument("query", nargs="*")
        p.add_argument("--all", action="store_true")
        p.add_argument("--limit", "-n", type=int)
    elif name == "user":
        p.add_argument("user", nargs="+")
    elif name == "channels":
        p.add_argument("query", nargs="*")
        p.add_argument("--member", action="store_true")
        p.add_argument("--archived", action="store_true")
    elif name == "conversations":
        p.add_argument("--types")
        p.add_argument("--archived", action="store_true")
    elif name in ("members", "pins", "bookmarks"):
        p.add_argument("channel")
    elif name == "usergroups":
        p.add_argument("--all", action="store_true")
    elif name == "emoji":
        p.add_argument("query", nargs="?")
    elif name == "file":
        p.add_argument("ref")
        p.add_argument("outfile", nargs="?")
        p.add_argument("--out", "-o")
        p.add_argument("--info", action="store_true")
        p.add_argument("--save", action="store_true")
        p.add_argument("--html", action="store_true")
        p.add_argument("--ids", action="store_true")
    elif name == "canvas":
        p.add_argument("action", choices=["read", "sections", "create", "edit"])
        p.add_argument("canvas", nargs="?")
        p.add_argument("text", nargs="*")
        p.add_argument("--html", action="store_true")
        p.add_argument("--ids", action="store_true")
        p.add_argument("--type")
        p.add_argument("--contains")
        p.add_argument("--title")
        p.add_argument("--channel")
        p.add_argument("--file", "-f")
        p.add_argument(
            "--op",
            choices=[
                "insert_at_end",
                "insert_at_start",
                "insert_after",
                "insert_before",
                "replace",
                "delete",
                "rename",
            ],
            default="insert_at_end",
        )
        p.add_argument("--section")
        add_dry(p)
    elif name == "list":
        p.add_argument("action", choices=["read", "create", "add", "update"])
        p.add_argument("list", nargs="?")
        p.add_argument("--limit", "-n", type=int)
        p.add_argument("--archived", action="store_true")
        p.add_argument("--schema")
        p.add_argument("--todo", action="store_true")
        p.add_argument("--field", action="append")
        p.add_argument("--cells")
        p.add_argument("--row")
        p.add_argument("--parent")
        add_dry(p)
    elif name in ("send", "schedule"):
        add_send_opts(p)
        if name == "schedule":
            p.add_argument("--at", required=True)
    elif name == "scheduled":
        p.add_argument("channel", nargs="?")
    elif name == "unschedule":
        p.add_argument("channel")
        p.add_argument("id")
        add_dry(p)
    elif name == "edit":
        p.add_argument("ref", nargs="+")
        p.add_argument("--file", "-f")
        p.add_argument("--allow-broadcast", action="store_true")
        add_dry(p)
    elif name in ("delete", "permalink", "reactions"):
        p.add_argument("ref", nargs="+")
        if name == "delete":
            add_dry(p)
    elif name in ("react", "unreact"):
        p.add_argument("args", nargs="+")
        p.add_argument("--remove", action="store_true")
        add_dry(p)
    elif name == "create-channel":
        p.add_argument("name")
        p.add_argument("--private", action="store_true")
        add_dry(p)
    elif name == "open":
        p.add_argument("users", nargs="+")
        add_dry(p)
    elif name == "invite":
        p.add_argument("channel")
        p.add_argument("users", nargs="+")
        add_dry(p)
    elif name == "upload":
        p.add_argument("path")
        p.add_argument("--channel", "-c")
        p.add_argument("--thread", "-t")
        p.add_argument("--comment")
        p.add_argument("--comment-file")
        p.add_argument("--title")
        p.add_argument("--name")
        p.add_argument("--alt")
        p.add_argument("--allow-broadcast", action="store_true")
        add_dry(p)
    elif name == "api":
        p.add_argument("method")
        p.add_argument("params", nargs="*")
        p.add_argument("--json-body", action="store_true")
        add_dry(p)
    return p


# --- command registrations ---------------------------------------------------

command(
    "whoami",
    "show the authenticated user, team, and token scopes",
    """\
Usage: slack whoami

Calls auth.test. Lists the token's scopes and any scopes from manifest.json the
token lacks (those need an app reinstall).""",
)(cmd_whoami)

command(
    "search",
    "search messages (public, private, DMs; Slack search operators)",
    """\
Usage: slack search <query...> [--count N] [--cursor C] [--sort timestamp|score] [--asc]
                    [--public] [--context] [--keyword] [--legacy [--page N]]

Searches everything you can see: public and private channels, DMs and group DMs.
Uses Slack's Real-time Search API (assistant.search.context). When the token lacks
the search:read.* scopes, it falls back to search.messages with a warning.
--sort score ranks by relevance, semantically on plans that support it (--keyword
turns that off); timestamp is keyword search, newest first.
--context also prints the messages around each hit. --public searches only public
channels. --legacy forces search.messages, whose --page paginates.
Operators: in:#channel  in:@user  from:@user  to:@user  before:YYYY-MM-DD  after:YYYY-MM-DD
           on:YYYY-MM-DD  during:month  has:link  has:pin  is:thread  "exact phrase"  -word
in:#name and from:@name are resolved fuzzily first (in:#general -> in:#0-general).
Defaults: --count 20 (max 100), newest first. Reply results show [in thread TS].

Examples:
  slack search 'in:#3-prod-alerts after:2026-10-20 backup'
  slack search 'why did we pick postfix' --sort score --context
  slack search 'from:@thomas deploy' --count 50 --json""",
)(cmd_search)

command(
    "search-files",
    "search files, canvases, and lists by name/content",
    """\
Usage: slack search-files <query...> [--count N] [--page N] [--sort timestamp|score] [--asc]

Uses search.files. Filter by type with operators such as type:canvases, type:lists,
type:images, type:pdfs, type:snippets, plus in:#channel and from:@user.
Read a result with: slack file <ID>   (canvases: slack canvas read <ID>)""",
)(cmd_search_files)

command(
    "history",
    "read channel or DM history with reply counts",
    """\
Usage: slack history <conversation> [--since T] [--until T] [--limit N] [--all] [--cursor C] [--replies]

Oldest first. Default --limit 50 (the newest 50 in the window). --all paginates the
whole window. When more exists, the last line gives a --cursor for older messages.
--replies also fetches every thread in the window and prints replies indented (↳).
Threads show as [thread: N replies, last TIME]; open one with: slack thread <permalink>

Examples:
  slack history '#3-prod-alerts' --since 1d
  slack history @thomas --limit 20
  slack history C0BL18MQNMB --since 2026-10-01 --until 2026-10-08 --all --json""",
)(cmd_history)

command(
    "thread",
    "read a whole thread from a permalink (reply links included)",
    """\
Usage: slack thread <permalink> [--limit N]
       slack thread <conversation> <ts> [--limit N]

Always prints the whole thread, parent first. A reply permalink (?thread_ts=...)
or a reply ts opens its parent thread; "» " marks the message the link pointed at
(JSON: "linked": true). Full pagination unless --limit is given.""",
)(cmd_thread)

command(
    "unreads",
    "unread messages in your channels, DMs, and group DMs",
    """\
Usage: slack unreads [--channel C]... [--types public,private,dm,group] [--limit N] [--mark [--dry-run]]

Lists your conversations, reads last_read with conversations.info in parallel, then
fetches messages newer than last_read. Your own messages and join/leave notices are
skipped. --limit is per conversation (default 20) and keeps the OLDEST unread
messages; "N+" means more are unread (the last line says how to read the rest).
--mark marks each shown conversation read through the newest message shown
(conversations.mark), so unseen messages stay unread. Only use --mark when
Michael asks to mark things read; --mark --dry-run shows what it would mark.
Limit: unread thread replies (the Threads view) have no public API and are not shown.""",
)(cmd_unreads)

command(
    "users",
    "search or list users by name, handle, title, or email",
    """\
Usage: slack users [query...] [--all] [--limit N]

Case-insensitive fuzzy match over handle, display name, real name, email, and title.
Without a query, lists everyone (deactivated users only with --all). Slack Connect
users appear once they have been seen in a message or looked up by email/ID.""",
)(cmd_users)

command(
    "user",
    "show a user's profile (ID, mention, title, tz, status)",
    """\
Usage: slack user <@handle | name | email | U-ID>

Prints the mention syntax (<@U...>) to use in messages. Email needs users:read.email.""",
    aliases=("whois",),
)(cmd_user)

command(
    "channels",
    "find channels by name (fuzzy); all channels you can see",
    """\
Usage: slack channels [query...] [--member] [--archived]

Lists public and private channels (not DMs; see: slack conversations). Matches names,
previous names, topic, and purpose. Cached for 6h; --refresh refetches.""",
)(cmd_channels)

command(
    "conversations",
    "list your conversations, including DMs and group DMs",
    """\
Usage: slack conversations [--types public,private,dm,group] [--archived]

Uses users.conversations, so only conversations you are a member of.""",
)(cmd_conversations)

command(
    "members",
    "list a channel's members",
    """\
Usage: slack members <conversation>""",
)(cmd_members)

command(
    "usergroups",
    "list user groups (@team handles) and their members",
    """\
Usage: slack usergroups [--all]

Needs usergroups:read. Mention a group in a message with <!subteam^ID>.""",
)(cmd_usergroups)

command(
    "emoji",
    "list custom emoji",
    """\
Usage: slack emoji [substring]

Needs emoji:read.""",
)(cmd_emoji)

command(
    "file",
    "show or download a file; print text files directly",
    """\
Usage: slack file <F-ID | file permalink | url_private | message permalink> [outfile]
                  [--out PATH] [--info] [--save]

Runs files.info, then downloads url_private with the token.
- text-like files (text/*, JSON, code, snippets) print to stdout unless --out/--save
- other files save to --out, or to $TMPDIR/slack-cli-files/<ID>/<name>; the path is printed
- canvases print as text (same as: slack canvas read)
- --info prints metadata only
A message permalink picks that message's file (if it has several, they are listed).""",
)(cmd_file)

command(
    "canvas",
    "read, create, edit canvases; find section IDs",
    """\
Usage: slack canvas read <canvas-ID | permalink> [--ids] [--html]
       slack canvas sections <canvas> [--type h1,h2,any_header,...] [--contains TEXT]
       slack canvas create --title TITLE [MARKDOWN... | --file F | -] [--channel C] [--dry-run]
       slack canvas edit <canvas> [--op OP] [--section ID] [MARKDOWN... | --file F | -] [--dry-run]

read downloads the canvas and converts it to Markdown-ish text; --ids prefixes blocks
with their section ID ({temp:C:...}) where the canvas exposes one.
sections calls canvases.sections.lookup (default: all headers) and prints section IDs.
edit ops: insert_at_end (default), insert_at_start, insert_after/insert_before
(--section), replace (--section; without it the WHOLE canvas is replaced), delete
(--section), rename (text is the new title).
--channel on create adds the canvas as a channel tab.
Needs canvases:read / canvases:write.""",
)(cmd_canvas)

command(
    "list",
    "Slack Lists: read items, create a list, add or update items",
    """\
Usage: slack list read <list-ID | permalink> [--limit N] [--archived]
       slack list create <NAME> [--schema JSON|@file] [--todo] [--dry-run]
       slack list add <list> [--field COLUMN=VALUE]... [--cells JSON|@file] [--parent REC] [--dry-run]
       slack list update <list> --row REC [--field COLUMN=VALUE]... [--cells JSON|@file] [--dry-run]

COLUMN is the column name, key, or ID (see `list read` header). --field converts
values by column type: text, number, rating, select (option label or value;
comma-separated for multi), user (@names), channel, date (YYYY-MM-DD or 2d etc.),
checkbox (true/false), email, phone. For other types pass raw cells with --cells.
Needs lists:read / lists:write and a paid plan.

Note: `list create` takes the name as its argument:  slack list create 'Bug triage'""",
)(cmd_list)

command(
    "send",
    "send a message or thread reply",
    """\
Usage: slack send <conversation> <text... | - | --file F> [--thread TS|PERMALINK]
                  [--broadcast] [--allow-broadcast] [--no-unfurl] [--dry-run]
       slack send --thread <permalink> <text...>

Only send when Michael explicitly asked to send this message.
- Text comes from the arguments (joined by spaces), '-' (stdin), or --file PATH / --file -.
  Prefer --file for multi-line text: no shell-quoting accidents.
- --thread takes a ts or any permalink; a reply permalink posts into its parent thread.
  With a permalink the destination can be omitted.
- --broadcast also posts the thread reply to the channel.
- @here/@channel/@everyone (<!here> etc.) are refused unless --allow-broadcast.
- --dry-run prints the destination, thread, resolved mentions, warnings, and the exact
  chat.postMessage payload, and sends nothing.
- Prints the permalink of the sent message.
Use Slack mrkdwn: *bold* _italic_ `code` > quote <url|label> <@U...> mentions.

Example:
  slack send --thread 'https://x.slack.com/archives/C1/p1700000000000100' --file /tmp/reply.txt --dry-run
""",
)(cmd_send)

command(
    "schedule",
    "schedule a message",
    """\
Usage: slack schedule <conversation> --at TIME <text... | - | --file F> [--thread TS|PERMALINK]
                      [--broadcast] [--allow-broadcast] [--dry-run]

TIME: +30m, +2h, 1d (from now), YYYY-MM-DDTHH:MM (local time), or epoch. Max 120 days.
Same safety checks as send. List with `slack scheduled`, delete with `slack unschedule`.""",
)(cmd_schedule)

command(
    "scheduled",
    "list scheduled messages",
    """\
Usage: slack scheduled [conversation]""",
)(cmd_scheduled)

command(
    "unschedule",
    "delete a scheduled message",
    """\
Usage: slack unschedule <conversation> <scheduled-message-ID> [--dry-run]""",
)(cmd_unschedule)

command(
    "edit",
    "edit one of your own messages",
    """\
Usage: slack edit <permalink | conversation ts> <new text... | - | --file F> [--dry-run]

Refuses messages that are not yours. --dry-run shows the old and new text.""",
)(cmd_edit)

command(
    "delete",
    "delete one of your own messages",
    """\
Usage: slack delete <permalink | conversation ts> [--dry-run]

Refuses messages that are not yours. Deletion cannot be undone.""",
)(cmd_delete)

command(
    "permalink",
    "get the permalink for a message",
    """\
Usage: slack permalink <conversation> <ts>""",
)(cmd_permalink)

command(
    "react",
    "add (or --remove) an emoji reaction",
    """\
Usage: slack react <permalink | conversation ts> <emoji-name> [--remove] [--dry-run]

Only react when Michael explicitly asked. The emoji name may include colons.""",
)(cmd_react)

command(
    "unreact",
    "remove your emoji reaction",
    """\
Usage: slack unreact <permalink | conversation ts> <emoji-name> [--dry-run]""",
)(lambda ctx, a: cmd_react(ctx, a, remove=True))

command(
    "reactions",
    "show who reacted to a message",
    """\
Usage: slack reactions <permalink | conversation ts>

Needs reactions:read.""",
)(cmd_reactions)

command(
    "pins",
    "list pinned items in a conversation",
    """\
Usage: slack pins <conversation>

Needs pins:read.""",
)(cmd_pins)

command(
    "bookmarks",
    "list a channel's bookmarks",
    """\
Usage: slack bookmarks <conversation>

Needs bookmarks:read.""",
)(cmd_bookmarks)

command(
    "create-channel",
    "create a channel",
    """\
Usage: slack create-channel <name> [--private] [--dry-run]""",
)(cmd_create_channel)

command(
    "open",
    "open (or find) a DM or group DM",
    """\
Usage: slack open <@user> [@user ...] [--dry-run]

Prints the conversation ID. One user opens a DM; 2-8 users a group DM.""",
    aliases=("dm",),
)(cmd_open)

command(
    "invite",
    "invite users to a channel",
    """\
Usage: slack invite <conversation> <@user> [@user ...] [--dry-run]""",
)(cmd_invite)

command(
    "upload",
    "upload a file, optionally to a channel or thread",
    """\
Usage: slack upload <path | -> [--channel C] [--thread TS|PERMALINK] [--comment TEXT | --comment-file F]
                    [--title T] [--name N] [--alt TEXT] [--dry-run]

Uses files.getUploadURLExternal -> upload -> files.completeUploadExternal.
Without --channel/--thread the file stays private to you. Needs files:write.""",
)(cmd_upload)

command(
    "api",
    "raw Web API call with JSON output (reads AND writes)",
    """\
Usage: slack api <method> [key=value ...] [key:=JSON ...] [--json-body] [--dry-run]

Calls any Web API method with the CLI's token and prints the JSON response; exits
non-zero when ok is false. key=@path reads the value from a file. key:=JSON sends
a JSON body (needed for nested arguments). This can write: treat write methods
(chat.*, reactions.add, conversations.mark, ...) like send - explicit request only.
--dry-run prints the request without sending it.

Examples:
  slack api conversations.info channel=C0BL18MQNMB
  slack api conversations.replies channel=C0BL18MQNMB ts=1792923163.393359 limit=5""",
)(cmd_api)


def preprocess(argv):
    """Pull global flags out of argv (stopping at --)."""
    flags = {"json": False, "refresh": False, "long": False, "help": False}
    rest = []
    passthrough = False
    for arg in argv:
        if passthrough:
            rest.append(arg)
        elif arg == "--":
            passthrough = True
            rest.append(arg)
        elif arg in ("--json", "--refresh", "--long"):
            flags[arg[2:]] = True
        elif arg in ("-h", "--help"):
            flags["help"] = True
        else:
            rest.append(arg)
    return flags, rest


def run(argv):
    flags, args = preprocess(argv)
    if not args or args[0] == "help":
        topic = args[1] if len(args) > 1 else None
        if topic and topic not in COMMANDS:
            raise UsageError(f"unknown command: {topic}")
        sys.stdout.write(command_help(topic) if topic else main_help())
        return 0
    if args[0] in ("--version", "version"):
        out(f"slack-cli {VERSION}")
        return 0
    name = args[0]
    if name not in COMMANDS:
        close = difflib.get_close_matches(name, list(COMMANDS), n=1)
        hint = f"; did you mean '{close[0]}'?" if close else ""
        raise UsageError(f"unknown command: {name}{hint}")
    if flags["help"]:
        sys.stdout.write(command_help(name))
        return 0
    real = COMMANDS[name].get("alias_of", name)
    parser = build_parser(real)
    try:
        a = parser.parse_args(args[1:]) if real == "api" else parser.parse_intermixed_args(args[1:])
    except UsageError as e:
        e.command = e.command or real
        raise
    ctx = Ctx(json_out=flags["json"], refresh=flags["refresh"], long=flags["long"])
    try:
        COMMANDS[name]["fn"](ctx, a)
    except UsageError as e:
        e.command = e.command or real
        raise
    finally:
        ctx.close()
    return 0


def main():
    try:
        sys.stdout.reconfigure(errors="replace")
        sys.stderr.reconfigure(errors="replace")
    except AttributeError:
        pass
    try:
        code = run(sys.argv[1:])
        sys.stdout.flush()
        return code
    except UsageError as e:
        hint = f"slack help {e.command}" if e.command else "slack help"
        print(f"slack: usage error: {e} (see: {hint})", file=sys.stderr)
        return 2
    except SlackError as e:
        print(f"slack: error: {e}", file=sys.stderr)
        return 1
    except BrokenPipeError:
        try:
            sys.stdout = open(os.devnull, "w")
        except OSError:
            pass
        return 0
    except KeyboardInterrupt:
        print("slack: interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
