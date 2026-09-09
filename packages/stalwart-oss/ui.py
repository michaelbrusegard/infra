"""Browser acceptance for WebUI 1.0.10 with the marketing-menu removal.

Optional development tool: Python Playwright plus Chromium, never a server runtime
requirement. Call inside the disposable server's loopback-only network namespace.
The caller supplies existing domain/user object IDs and an ordinary fixture admin
API key (English locale, OSS edition, authenticate, scimAccess, domain/account Get+Update and
API-key Create/Get permissions). This deliberately tests API-key session preseed,
NOT OIDC login. No backend routes or browser responses are mocked.

Only audited AGPL WebUI contracts are used: stores/authStore.ts sessionStorage,
pages/AdminPanel.tsx initialization, and components/forms/{DynamicForm,FieldWidget}.
The helper changes the disposable domain and user and leaves them changed. It does
not create a credential, restore state, use live tabs, or retain a browser profile.
"""

from __future__ import annotations

import ipaddress
import json
from pathlib import Path
import re
import time
from urllib.parse import quote, urlsplit


class UiCheckError(RuntimeError):
    """The real browser acceptance check failed (never a skipped success)."""


def _label_pattern(label: str):
    # FieldWidget appends marker spans without a text-space; CSS margins only
    # make them look separated. Thus textContent can be "Label(optional)".
    return re.compile(r"^" + re.escape(label) + r"\s*(?:\*|\(optional\))?\s*$")


def run_ui_checks(
    base_url: str,
    admin_api_key: str,
    domain_name: str,
    *,
    domain_id: str,
    account_id: str,
    external_id: str = "ui-native-scim-acceptance",
    screenshot_path: str | Path | None = None,
    chromium_executable: str | Path | None = None,
    timeout_ms: int = 30_000,
) -> dict[str, object]:
    """Exercise native domain/user saves and API-key permission selection.

    base_url is an origin with a literal loopback IP, e.g. http://127.0.0.1:8080.
    account_id is the disposable USER object's ID, not the admin/JMAP account ID.
    external_id must differ from the user's existing value. The domain is toggled
    and ultimately enabled; the user's External Identifier is saved and reloaded.
    screenshot_path, if supplied, must resolve below /tmp and is written only after
    every assertion passes. The screenshot shows the actual permission picker.

    Raises UiCheckError for missing Playwright/browser, unreachable UI, login
    redirects, gated controls, denied permissions, or unsuccessful native saves.
    Return values contain only acceptance facts, never the fixture credential.
    """
    parsed = urlsplit(base_url)
    try:
        loopback = ipaddress.ip_address(parsed.hostname or "").is_loopback
        port = parsed.port
    except ValueError as exc:
        raise UiCheckError("base_url must use a literal loopback IP") from exc
    if (
        not loopback
        or parsed.scheme not in {"http", "https"}
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
    ):
        raise UiCheckError("Only a loopback HTTP(S) origin is accepted")
    if not all((admin_api_key, domain_name, domain_id, account_id, external_id)):
        raise UiCheckError(
            "Fixture credential, domain, object IDs and external_id are required"
        )
    if timeout_ms <= 0:
        raise UiCheckError("timeout_ms must be positive")
    default_port = 443 if parsed.scheme == "https" else 80
    host = f"[{parsed.hostname}]" if ":" in parsed.hostname else parsed.hostname
    authority = f"{host}:{port}" if port is not None and port != default_port else host
    origin = f"{parsed.scheme}://{authority}"
    allowed_origin = (parsed.scheme, parsed.hostname, port or default_port)
    screenshot = None
    if screenshot_path is not None:
        screenshot = Path(screenshot_path).resolve()
        if not screenshot.is_relative_to(Path("/tmp")) or screenshot == Path("/tmp"):
            raise UiCheckError("Screenshots must resolve to a file below /tmp")
        if screenshot.suffix.lower() != ".png" or not screenshot.parent.is_dir():
            raise UiCheckError(
                "Screenshot must be a .png file in an existing /tmp directory"
            )

    try:
        from playwright.sync_api import expect, sync_playwright
    except ImportError as exc:
        raise UiCheckError(
            "Optional UI checks require Python Playwright and Chromium"
        ) from exc

    def require(condition, message):
        if not condition:
            raise UiCheckError(message)

    def same_origin(url):
        parts = urlsplit(url)
        return (
            parts.scheme,
            parts.hostname,
            parts.port or (443 if parts.scheme == "https" else 80),
        ) == allowed_origin

    # Persist only the same fields as stock authStore.ts. No fabricated session,
    # permission list, schema, edition or JMAP account data is supplied.
    auth = {
        "state": {
            "accessToken": admin_api_key,
            "refreshToken": None,
            "tokenExpiresAt": int(time.time() * 1000) + 3_600_000,
            "tokenEndpoint": None,
            "endSessionEndpoint": None,
            "activeAccountId": None,
        },
        "version": 0,
    }
    saves = []
    blocked_requests = []
    try:
        with sync_playwright() as playwright:
            launch = {"headless": True}
            if chromium_executable is not None:
                launch["executable_path"] = str(chromium_executable)
            # launch() creates a temporary browser profile; never connect_over_cdp
            # or launch_persistent_context against a human's profile.
            browser = playwright.chromium.launch(**launch)
            try:
                context = browser.new_context(
                    locale="en-US",
                    viewport={"width": 1440, "height": 1100},
                    service_workers="block",
                )
                context.set_default_timeout(timeout_ms)
                context.set_default_navigation_timeout(timeout_ms)
                # Fail with the actual credential status rather than a later
                # timeout waiting for a form that authentication never loaded.
                authenticated = context.request.get(
                    origin + "/api/account",
                    headers={"Authorization": "Bearer " + admin_api_key},
                    max_redirects=0,
                    timeout=timeout_ms,
                )
                require(
                    authenticated.status == 200,
                    f"Fixture admin authentication failed: HTTP {authenticated.status}",
                )
                authenticated.dispose()

                def restrict_network(route):
                    if same_origin(route.request.url):
                        route.continue_()
                    else:
                        # Do not collect URLs, headers or bodies containing secrets.
                        blocked_requests.append("off-origin request")
                        route.abort("blockedbyclient")

                context.route("**/*", restrict_network)
                context.add_init_script(
                    "if (location.origin === " + json.dumps(origin) + ") {"
                    "sessionStorage.setItem('stalwart-auth', "
                    + json.dumps(json.dumps(auth))
                    + ");}"
                )
                page = context.new_page()

                def open_view(view):
                    response = page.goto(
                        origin + "/admin/" + view, wait_until="domcontentloaded"
                    )
                    require(
                        response is not None and response.ok,
                        "Stock WebUI document unavailable",
                    )

                def field(label):
                    # Stock labels have no htmlFor. The enclosing field div owns
                    # the label container, help text and control (FieldWidget.tsx).
                    label_node = page.locator("label").filter(
                        has_text=_label_pattern(label)
                    )
                    expect(label_node).to_have_count(1)
                    wrapper = label_node.locator("../..")
                    expect(wrapper).to_be_visible()
                    require(
                        wrapper.locator(
                            "xpath=ancestor-or-self::*[contains(concat(' ', normalize-space(@class), ' '), ' opacity-60 ')]"
                        ).count()
                        == 0,
                        f"{label} is Enterprise-disabled",
                    )
                    return wrapper

                def no_scim_gate():
                    expect(
                        page.get_by_text(
                            "This feature requires an Enterprise license.", exact=True
                        )
                    ).not_to_be_visible()
                    # Neither SCIM controls nor the account menu should upsell.
                    expect(page.get_by_role("dialog")).not_to_be_visible()

                def save_native(object_type, object_id, property_name, expected_value):
                    method = object_type + "/set"

                    def is_save(response):
                        if response.request.method != "POST" or not same_origin(
                            response.url
                        ):
                            return False
                        try:
                            payload = response.request.post_data_json
                        except Exception:
                            return False
                        if not isinstance(payload, dict):
                            return False
                        return any(
                            call[0] == method
                            and call[1]
                            .get("update", {})
                            .get(object_id, {})
                            .get(property_name)
                            == expected_value
                            for call in payload.get("methodCalls", [])
                        )

                    with page.expect_response(is_save, timeout=timeout_ms) as pending:
                        page.get_by_role("button", name="Save", exact=True).click()
                    response = pending.value
                    require(response.ok, f"{method} failed at HTTP layer")
                    calls = response.request.post_data_json["methodCalls"]
                    call_id = next(
                        c[2]
                        for c in calls
                        if c[0] == method and object_id in c[1].get("update", {})
                    )
                    results = response.json().get("methodResponses", [])
                    result = next((r for r in results if r[2] == call_id), None)
                    require(
                        result is not None
                        and result[0] == method
                        and object_id in result[1].get("updated", {}),
                        f"{method} did not confirm the fixture object was updated",
                    )
                    # Wait for stock UI's successful-save navigation before opening
                    # another form (otherwise its dirty-form guard may intercept).
                    expect(page).to_have_url(
                        re.compile(
                            r"/"
                            + re.escape(object_type)
                            + (r"/User" if object_type == "x:Account" else "")
                            + r"$"
                        )
                    )
                    saves.append(
                        {
                            "method": method,
                            "property": property_name,
                            "value": expected_value,
                        }
                    )

                domain_view = "Management/x:Domain/" + quote(domain_id, safe="")
                with page.expect_response(
                    lambda r: urlsplit(r.url).path == "/api/account"
                ) as account_response:
                    open_view(domain_view)
                info_response = account_response.value
                require(info_response.ok, "Fixture API key cannot fetch /api/account")
                require(
                    info_response.request.header_value("authorization")
                    == f"Bearer {admin_api_key}",
                    "Stock UI did not send the fixture API key through normal bearer authentication",
                )
                info = info_response.json()
                require(
                    info.get("edition") == "oss",
                    "Fixture must report OSS, not a spoofed edition",
                )
                require(
                    "scimAccess" in info.get("permissions", []),
                    "Fixture admin lacks scimAccess",
                )
                require(
                    info.get("locale", "").replace("_", "-").lower().startswith("en"),
                    "Fixture admin must use an English locale",
                )

                # Read the real form before changing it. The switch may begin in
                # either state; always exercise a write, ultimately leaving true.
                expect(field("Domain Name").locator("input")).to_have_value(domain_name)
                # TopBar.tsx exposes its compiled package version in the logo tooltip.
                page.locator("header a").first.hover()
                expect(page.get_by_role("tooltip")).to_have_text(
                    "Stalwart WebUI v1.0.10"
                )
                page.mouse.move(800, 600)
                switch = field("Allow SCIM Provisioning").get_by_role("switch")
                expect(switch).to_be_visible()
                expect(switch).to_be_enabled()
                initial = switch.get_attribute("aria-checked") == "true"
                values = [False, True] if initial else [True]
                for value in values:
                    switch.click()
                    expect(switch).to_have_attribute("aria-checked", str(value).lower())
                    no_scim_gate()
                    save_native("x:Domain", domain_id, "allowScimProvisioning", value)
                    open_view(domain_view)
                    switch = field("Allow SCIM Provisioning").get_by_role("switch")
                    expect(switch).to_have_attribute("aria-checked", str(value).lower())

                user_view = "Management/x:Account/User/" + quote(account_id, safe="")
                open_view(user_view)
                identifier = field("External Identifier").locator("input")
                expect(identifier).to_be_visible()
                expect(identifier).to_be_editable()
                require(
                    identifier.input_value() != external_id,
                    "external_id must differ from the fixture's current value",
                )
                identifier.fill(external_id)
                identifier.press("Tab")  # StringField's buffered input commits on blur.
                no_scim_gate()
                save_native("x:Account", account_id, "externalId", external_id)
                open_view(user_view)
                expect(field("External Identifier").locator("input")).to_have_value(
                    external_id
                )

                # The cosmetic patch removes the marketing entry without changing
                # edition reporting, permissions or unrelated feature gates.
                page.locator("header").get_by_role("button").last.click()
                expect(page.get_by_role("menu")).to_be_visible()
                expect(
                    page.get_by_role("menuitem", name="Try Enterprise", exact=True)
                ).to_have_count(0)
                page.keyboard.press("Escape")

                # Exercise the real credential editor, but do not create another
                # secret. The fixture admin's own key is never displayed here.
                open_view("Account/x:ApiKey/new")
                mode = page.get_by_role("combobox").filter(
                    has_text="Same permissions as account"
                )
                expect(mode).to_be_enabled()
                mode.click()
                page.get_by_role(
                    "option", name="Replace all permissions", exact=True
                ).click()
                page.get_by_role("button", name="Select options...", exact=True).click()
                option = page.get_by_role(
                    "checkbox",
                    name="Provision users and groups through the SCIM endpoint",
                    exact=True,
                )
                expect(option).to_be_visible()
                expect(option).to_be_enabled()
                option.check()
                expect(option).to_be_checked()
                # This popup is Radix Popover (role=dialog), not EnterpriseUpsell;
                # verify the Enterprise text directly while the picker is open.
                expect(
                    page.get_by_text(
                        "This feature requires an Enterprise license.", exact=True
                    )
                ).not_to_be_visible()
                require(
                    not blocked_requests,
                    "Stock UI attempted an off-origin request; fixture must be self-contained",
                )
                if screenshot is not None:
                    page.screenshot(path=str(screenshot), full_page=True)
                context.close()
            finally:
                browser.close()
    except Exception as exc:
        # Never echo the API key if a browser/transport exception includes it.
        raise UiCheckError(
            str(exc).replace(admin_api_key, "[fixture credential redacted]")
        ) from None

    return {
        "webui_version": "1.0.10",
        "auth": "fixture-api-key-session-preseed; OIDC not tested",
        "edition": "oss",
        "native_saves": saves,
        "scim_access_selectable": True,
        "screenshot": str(screenshot) if screenshot is not None else None,
    }
