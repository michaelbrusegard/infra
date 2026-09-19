# Company RustFS provider compatibility

The runner exports `MADMIN_API_VERSION=v3`. RustFS 1.0.0-beta.12 exposes
MinIO's v3 admin API, while provider 3.43.0 uses madmin-go/v4 4.10.5 and
defaults to v4. That client only falls back after HTTP 426; RustFS returns
`NotImplemented` instead. `tofu validate` cannot detect this incompatibility.

Disposable qualification on 2026-09-18 used the released provider 3.43.0,
OpenTofu 1.11.5, and RustFS image digest
`sha256:41fe89380f4120a337790c02af192c3fe7bb55c3edc2e6e9357b487b47c6ab21`:

- Default API selection failed IAM creation/refresh with `NotImplemented`.
- Explicit v3 passed creation, refresh, policy updates and secret rotation
  without resource replacement.
- Existing state from provider 3.38.5 produced a zero-change plan under 3.43.0.
- A fresh create, no-change plan and destroy cycle passed.

The setting belongs on the **runner/provider process**, not the controller or
RustFS service. Deploy it before upgrading the provider. Production plans
require explicit review; the disposable tests do not authorize IAM mutations.
No production credentials or backup tooling changed for this qualification.
