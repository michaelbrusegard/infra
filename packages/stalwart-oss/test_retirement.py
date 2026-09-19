"""Regression-test the archived legacy reconciler's credential retirement."""

import json
import os
import textwrap
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import mock_open, patch


class CredentialRetirement(unittest.TestCase):
    def test_only_explicit_empty_credentials_survive_existing_account_updates(self):
        path = Path(
            os.environ.get(
                "STALWART_RECONCILER_FILE",
                Path(__file__).resolve().parent / "fixtures/legacy-reconciler.yaml",
            )
        )
        source = path.read_text().split("    rewrite_plan() {", 1)[1]
        source = textwrap.dedent(
            source.split("python3 - <<'PY'\n", 1)[1].split("\n    PY", 1)[0]
        )
        accounts = {
            "retired": {
                "credentials": {},
                "permissions": {
                    "@type": "Merge",
                    "disabledPermissions": {"authenticate": True},
                },
            },
            "admin": {
                "credentials": {"0": {"@type": "Password", "secret": "fixture-only"}}
            },
            "shared": {"aliases": {}},
            "new": {
                "credentials": {"0": {"@type": "Password", "secret": "fixture-only"}}
            },
        }
        plan = [
            {
                "@type": "create",
                "object": "Domain",
                "value": {"domain": {"name": "mail.test"}},
            },
            {
                "@type": "create",
                "object": "Account",
                "value": {
                    name: {"name": name, "domainId": "#domain", **spec}
                    for name, spec in accounts.items()
                },
            },
        ]
        live = {
            "Domain": [{"id": "domain-id", "name": "mail.test"}],
            "Account": [
                {"id": name, "emailAddress": f"{name}@mail.test"}
                for name in ("retired", "admin", "shared")
            ],
        }

        def query(arguments, **_kwargs):
            self.assertEqual(arguments[:2], ["stalwart-cli", "query"])
            return SimpleNamespace(
                returncode=0,
                stdout="\n".join(json.dumps(row) for row in live.get(arguments[2], [])),
            )

        files = mock_open(read_data="\n".join(json.dumps(row) for row in plan))
        with patch("builtins.open", files), patch("subprocess.run", side_effect=query):
            exec(compile(source, str(path), "exec"), {})
        output = [
            json.loads(line) for line in files().write.call_args.args[0].splitlines()
        ]
        updates = {
            row["id"]: row["value"] for row in output if row["@type"] == "update"
        }
        self.assertEqual(updates["retired"]["credentials"], {})
        self.assertEqual(
            updates["retired"]["permissions"], accounts["retired"]["permissions"]
        )
        self.assertNotIn("credentials", updates["admin"])
        self.assertNotIn("credentials", updates["shared"])
        self.assertNotIn("name", updates["retired"])
        self.assertEqual(updates["retired"]["domainId"], "domain-id")
        creates = [row for row in output if row["@type"] == "create"]
        self.assertEqual(len(creates), 1)
        self.assertEqual(
            creates[0]["value"]["new"]["credentials"], accounts["new"]["credentials"]
        )


if __name__ == "__main__":
    unittest.main()
