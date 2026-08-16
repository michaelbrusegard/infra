# Hermes Agent

## Browser takeover

The browser image exposes noVNC only on the pod loopback interface. Access it
through Kubernetes port forwarding; there is intentionally no Service or
Ingress for the takeover endpoint.

```sh
kubectl -n hermes-agent port-forward pod/hermes-agent-0 6080:6080
```

Then open:

```text
http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale
```

Use takeover for sign-in, MFA, CAPTCHA, account recovery, and final review of
consequential forms. Close the port forward when finished. The display is not
password protected because it is bound to pod-local loopback and relies on
Kubernetes authentication and authorization for access.

## Browser hardening

uBlock Origin Lite is force-installed from the Chrome Web Store with its
first-run page disabled. It reduces ads, trackers, overlays, and unnecessary
requests, but it is not a CAPTCHA solver. If it breaks a site, use noVNC to
change that site's filtering level rather than disabling the blocker globally.

NopeCHA is intentionally not installed in the persistent signed-in profile.
Its current extension is closed source and requires broad access to every page
and frame, so a compromise would expose account, checkout, and payment pages.
CAPTCHA, MFA, and account-recovery boundaries use human takeover instead.

The browser runs as a non-root user with a read-only root filesystem, dropped
capabilities, no privilege escalation, and the runtime-default seccomp profile.
Chromium still needs `--no-sandbox` in this container because neither its SUID
nor user-namespace sandbox can initialize under these restrictions.

## Browser concurrency

Hermes uses one persistent Chrome profile so authenticated state survives pod
restarts. Each browser task owns a root tab and its popup descendants. Browser
commands are serialized around target discovery to prevent concurrent tasks
from claiming or controlling one another's tabs. At most six browser tasks may
hold tab groups at once; additional tasks receive a retryable limit error.

The shared profile means account and cart state still belongs to every task.
Do not run concurrent workflows against the same signed-in service when they
could modify the same cart, draft, or account state.
