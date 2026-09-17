"""Offline wiring checks. Native parser/SMTP qualification is a separate gate."""

from pathlib import Path
import re
import sqlite3
import unittest

ROOT = Path(__file__).resolve().parent
SQL = (ROOT / "../../apps/stalwart-edge/policy.sql").read_text().strip()


class StaticContract(unittest.TestCase):
    def test_shared_query_is_not_copied(self):
        ingress = (ROOT / "ingress.tf").read_text()
        self.assertIn('trimspace(file("${path.module}/../../apps/stalwart-edge/policy.sql"))', ingress)
        self.assertIn(r'\"${local.recipient_query}\", [rcpt]) == 1', ingress)
        self.assertNotIn('"', SQL)
        self.assertNotIn('\\', SQL)
        self.assertRegex(ingress, r'''if\s*= "rcpt_domain == 'manafishrov\.com'"''')
        self.assertNotIn("SELECT EXISTS", ingress)

    def test_only_internal_domain_and_two_listeners(self):
        config = "\n".join(p.read_text() for p in ROOT.glob("*.tf"))
        resources = re.findall(r'resource "([^"]+)" "([^"]+)"', config)
        self.assertEqual([name for kind, name in resources if kind == "stalwart_domain"], ["internal"])
        self.assertEqual({name for kind, name in resources if kind == "stalwart_network_listener"}, {"smtp", "https"})
        self.assertFalse(any(kind.startswith(("stalwart_directory_", "stalwart_account", "stalwart_mailing_list", "stalwart_mta_route_local", "stalwart_mta_route_mx")) for kind, _ in resources))

    def test_guard_and_hook_are_independent(self):
        ingress = (ROOT / "ingress.tf").read_text()
        self.assertIn('require ["envelope", "reject"];', ingress)
        self.assertIn('if not envelope :domain :is "to" "manafishrov.com"', ingress)
        self.assertIn('reject "550 5.7.1', ingress)
        self.assertIn('stalwart_sieve_system_script.rcpt_domain_guard.name', ingress)
        self.assertRegex(ingress, r'temp_fail_on_error\s*= true')
        self.assertRegex(ingress, r'timeout\s*= 5000')
        self.assertIn('"http://127.0.0.1:8090/rcpt"', ingress)
        self.assertRegex(ingress, r'rewrite\s*= \{ else = "false", match = \[\] \}')

    def test_no_secret_values_or_direct_mx_delivery(self):
        delivery = (ROOT / "delivery.tf").read_text()
        self.assertIn('"EnvironmentVariable"', delivery)
        self.assertIn('"STALWART_RESEND_API_KEY"', delivery)
        self.assertEqual(len(re.findall(r'allow_invalid_certs\s*= false', delivery)), 2)
        self.assertEqual(len(re.findall(r'implicit_tls\s*= true', delivery)), 2)
        self.assertIn("'postmaster@manafishrov.com'", delivery)
        self.assertNotIn('resource "stalwart_mta_route_mx"', delivery)

    def test_query_returns_one_bound_integer_and_denies_unknowns(self):
        with sqlite3.connect(":memory:") as db:
            db.executescript("""
                CREATE TABLE policy_sources(name TEXT PRIMARY KEY);
                CREATE TABLE policy_domains(name TEXT PRIMARY KEY, source TEXT);
                CREATE TABLE policy_recipients(address TEXT PRIMARY KEY, domain TEXT, source TEXT, verified_at REAL);
                INSERT INTO policy_sources VALUES('manafishrov');
                INSERT INTO policy_domains VALUES('manafishrov.com','manafishrov');
                INSERT INTO policy_recipients VALUES('support@manafishrov.com','manafishrov.com','manafishrov',1);
            """)
            for address, expected in [
                ("support@manafishrov.com", 1),
                ("support+tag@manafishrov.com", 0),
                ("missing@manafishrov.com", 0),
                ("support@sub.manafishrov.com", 0),
                ("machine@system.edge.asgard.michaelbrusegard.com", 0),
                ("support' OR 1=1 --@manafishrov.com", 0),
                ("support@manafishrov.com@outside.example", 0),
            ]:
                with self.subTest(address=address):
                    rows = db.execute(SQL, (address,)).fetchall()
                    self.assertEqual(rows, [(expected,)])
                    self.assertIs(type(rows[0][0]), int)
            db.execute("DELETE FROM policy_recipients")
            self.assertEqual(db.execute(SQL, ("support@manafishrov.com",)).fetchall(), [(0,)])


if __name__ == "__main__":
    unittest.main()
