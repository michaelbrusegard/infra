# Mail qualification fixtures

`legacy-reconciler.yaml` preserves the retired ingress bootstrap for regression
tests; it is not an active deployment.

`legacy-auth-verdict.sieve` preserves the superseded header-score bridge's
regression fixture. It is not mounted into the edge or part of the Postfix path.

`spam-rules-v3.0.1.json` contains only `SpamTag` and `SpamRule` from Stalwart's
[v3.0.1 release](https://github.com/stalwartlabs/spam-filter/releases/tag/v3.0.1).
The downloaded `spam-filter-rules.json.gz` has SHA-256
`84501f4d3db0aa47f2ec73d5e13df9cf04522253b513c89f73adb889fd01ceb0`.
These 403 tags and 66 rules exactly matched the read-only backend inventory used
for qualification. They contain no account IDs, messages, credentials, or trained
classifier data. The original Reject action is deliberately retained: the fixture
must explicitly convert unsafe actions before exercising backend filtering.

The spam rules are Copyright (C) 2024, Stalwart Labs LLC, used under the upstream
MIT licensing option; see `LICENSE-spam-rules-MIT`.
