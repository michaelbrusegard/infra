"""Source-transformation checks, NOT proof of native runtime/concurrency safety.

The live fixture must separately cover protected membership addition/removal, a
toggle between JIT policy reads and commit, both orderings of ordinary/SCIM
writes, and ACL grants racing deletion and task cleanup.
"""

# SPDX-License-Identifier: AGPL-3.0-only

import base64
import copy
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location(
    "native_hook", Path(__file__).with_name("apply-native.py")
)
HOOK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HOOK)


class NativePackaging(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = os.environ.get("STALWART_SOURCE_DIR")
        if not source:
            raise RuntimeError("Set STALWART_SOURCE_DIR to the pinned v1.0.3 source")
        cls.temporary = tempfile.TemporaryDirectory(prefix="stalwart-source-test-")
        cls.root = Path(cls.temporary.name) / "source"
        shutil.copytree(source, cls.root)
        for path in cls.root.rglob("*"):
            if not path.is_symlink():
                path.chmod(path.stat().st_mode | 0o200)
        subprocess.run(
            ["python3", str(cls.root / "resources/scripts/ossify.py"), str(cls.root)],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        cls.baseline = Path(cls.temporary.name) / "unpatched"
        shutil.copytree(cls.root, cls.baseline)
        schema = cls.root / "resources/schema"
        cls.schema_bytes = {
            name: (schema / name).read_bytes()
            for name in ("schema.json.gz", "schema_oss.json.gz")
        }
        cls.full_schema = json.loads(
            gzip.decompress(cls.schema_bytes["schema.json.gz"])
        )
        cls.oss_schema = json.loads(
            gzip.decompress(cls.schema_bytes["schema_oss.json.gz"])
        )
        cls.edition_source = (
            cls.root / "crates/http/src/auth/permissions.rs"
        ).read_bytes()
        HOOK.apply(cls.root, Path(__file__).with_name("native"))

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_only_implemented_schema_capabilities_are_exposed(self):
        actual = json.loads(
            gzip.decompress(
                (
                    self.root / "resources/schema/schema.independent-scim.json.gz"
                ).read_bytes()
            )
        )
        # Removing exactly the native SCIM capabilities yields the OSS schema.
        reduced = copy.deepcopy(actual)
        for kind, name in (
            ("x:Domain", "allowScimProvisioning"),
            ("x:UserAccount", "externalId"),
            ("x:GroupAccount", "externalId"),
        ):
            expected = copy.deepcopy(
                self.full_schema["fields"][kind]["properties"][name]
            )
            self.assertIs(expected.pop("enterprise"), True)
            self.assertEqual(expected, reduced["fields"][kind]["properties"].pop(name))
            self.assertNotIn(name, self.oss_schema["fields"][kind]["properties"])
            placed = [
                (section["title"], field)
                for section in reduced["forms"][kind]["sections"]
                for field in section["fields"]
                if field["name"] == name
            ]
            upstream = [
                (section["title"], field)
                for section in self.full_schema["forms"][kind]["sections"]
                for field in section["fields"]
                if field["name"] == name
            ]
            self.assertEqual(upstream, placed)
            for section in reduced["forms"][kind]["sections"]:
                section["fields"] = [
                    field for field in section["fields"] if field["name"] != name
                ]
        permissions = [item["name"] for item in reduced["enums"]["Permission"]]
        index = permissions.index("scimAccess")
        self.assertEqual("liveDeliveryTest", permissions[index - 1])
        self.assertNotIn("enterprise", reduced["enums"]["Permission"][index])
        del reduced["enums"]["Permission"][index]
        self.assertEqual(self.oss_schema, reduced)
        for name, contents in self.schema_bytes.items():
            self.assertEqual(
                contents, (self.root / "resources/schema" / name).read_bytes()
            )
        self.assertEqual(
            self.edition_source,
            (self.root / "crates/http/src/auth/permissions.rs").read_bytes(),
        )

    def test_schema_cache_key_matches_archive(self):
        archive = (
            self.root / "resources/schema/schema.independent-scim.json.gz"
        ).read_bytes()
        expected = (
            base64.urlsafe_b64encode(hashlib.sha256(archive).digest())
            .decode()
            .rstrip("=")
        )
        self.assertEqual(
            expected,
            (
                self.root / "resources/schema/schema.independent-scim.json.sha256"
            ).read_text(),
        )
        source = (self.root / "crates/http/src/api/mod.rs").read_text()
        self.assertIn(
            '#[cfg(all(not(feature = "enterprise"), not(feature = "independent-scim")))]',
            source,
        )
        self.assertIn("schema.independent-scim.json.gz", source)

    def test_proprietary_implementation_is_absent(self):
        for path in self.root.rglob("*.rs"):
            self.assertNotIn(
                "SPDX-License-Identifier: LicenseRef-SEL", path.read_text(), str(path)
            )
        for name in ("scim", "scim-proto"):
            self.assertNotIn(
                "pub mod", (self.root / f"crates/{name}/src/lib.rs").read_text()
            )

    def test_source_hooks_are_feature_scoped(self):
        request = (self.root / "crates/http/src/request.rs").read_text()
        self.assertIn(
            '#[cfg(feature = "independent-scim")]\n            "scim"', request
        )
        directory = (self.root / "crates/common/src/cache/directory.rs").read_text()
        self.assertEqual(
            directory.count(
                "if self.scim_domain_authoritative(Id::from(domain.id)).await?"
            ),
            2,
        )
        self.assertEqual(
            directory.count(
                "if self.scim_domain_authoritative(Id::from(alias_domain.id)).await?"
            ),
            4,
        )
        self.assertNotIn("if domain.scim_authoritative", directory)
        self.assertNotIn("if alias_domain.scim_authoritative", directory)
        self.assertIn("Provisioned identity no longer exists", directory)
        defaults = (self.root / "crates/common/src/manager/defaults.rs").read_text()
        self.assertIn('env!("STALWART_NATIVE_WEBUI_ARCHIVE")', defaults)
        self.assertIn('not(feature = "independent-scim")', defaults)
        self.assertIn(
            '#[cfg(feature = "independent-scim")]\n'
            '                    oauth_scopes: Map::new(vec!["groups".into()]),',
            defaults,
        )

    def test_registry_epoch_is_in_both_native_mutation_batches(self):
        source = (self.root / "crates/store/src/registry/write.rs").read_text()
        self.assertIn('b"independent-scim/account-epoch/v1"', source)
        self.assertIn("subspace: crate::Subspace::System,", source)
        self.assertIn("self.assign_id().serialize()", source)
        self.assertEqual(
            source.count("self.advance_independent_scim_epoch(&mut batch)"), 2
        )
        for writer in ("self.store()", "self.0\n            .store"):
            self.assertIn(
                "self.advance_independent_scim_epoch(&mut batch);\n\n        "
                + writer
                + "\n            .write_batch(&mut batch)",
                source,
            )
        manifest = (self.root / "crates/common/Cargo.toml").read_text()
        self.assertIn('independent-scim = ["store/independent-scim"]', manifest)
        manifest = (self.root / "crates/store/Cargo.toml").read_text()
        self.assertIn('independent-scim = ["registry/independent-scim"]', manifest)

    def test_epoch_capture_precedes_validation_and_preserves_caller_guard(self):
        source = (self.root / "crates/store/src/registry/write.rs").read_text()
        capture = (
            "self.assert_independent_scim_epoch(&mut batch, expected_epoch)\n"
            "            .await?;"
        )
        self.assertEqual(source.count(capture), 2)
        write = source.split("    async fn write_inner(", 1)[1]
        self.assertLess(write.index(capture), write.index("match write {"))
        delete = source.split("    async fn delete(", 1)[1]
        self.assertLess(delete.index(capture), delete.index("// Fetch object"))
        self.assertLess(delete.index(capture), delete.index("self.linked_objects"))
        self.assertIn("expected_epoch: Option<Option<u64>>", source)
        self.assertIn("Some(epoch) => epoch,", source)
        self.assertIn("None => self.independent_scim_epoch().await?", source)
        self.assertIn("self.write_inner(write, Some(epoch)).await", source)

    def test_registry_scim_fields_are_feature_scoped(self):
        schema = self.root / "crates/registry/src/schema"
        gate = '#[cfg(feature = "independent-scim")]'
        properties = (schema / "properties.rs").read_text()
        self.assertIn(gate + "\n    AllowScimProvisioning = 421,", properties)
        self.assertIn(gate + "\n    ExternalId = 472,", properties)
        self.assertIn(
            gate + "\n    ScimAccess = 221,", (schema / "enums.rs").read_text()
        )
        structs = (schema / "structs.rs").read_text()
        self.assertIn(
            gate + '\n    #[serde(rename = "allowScimProvisioning")]', structs
        )
        self.assertEqual(
            structs.count(gate + '\n    #[serde(rename = "externalId")]'), 2
        )
        manifest = (self.root / "crates/registry/Cargo.toml").read_text()
        self.assertIn("independent-scim = []", manifest)
        # The generated impls gain gated items only; the OSS build is unchanged.
        for name in ("structs_impl.rs", "enums_impl.rs", "properties_impl.rs"):
            patched = (schema / name).read_text().count(gate)
            self.assertGreater(patched, 0, name)
            self.assertEqual(
                0,
                (self.baseline / "crates/registry/src/schema" / name)
                .read_text()
                .count(gate),
            )

    def test_dropped_upstream_covered_hooks_stay_unpatched(self):
        # The DomainCache flag, domain toggle invalidation and group token
        # expansion were dropped: nothing reads a cached SCIM policy, and
        # upstream invalidate_grantee evicts group members on ACL changes.
        for path in (
            "crates/common/src/auth/mod.rs",
            "crates/common/src/cache/principals.rs",
            "crates/common/src/cache/invalidate.rs",
        ):
            self.assertEqual(
                (self.baseline / path).read_bytes(), (self.root / path).read_bytes()
            )
        invalidate = (self.root / "crates/common/src/cache/invalidate.rs").read_text()
        grantee = invalidate.split("    pub async fn invalidate_grantee(", 1)[1].split(
            "    pub async fn invalidate_caches(", 1
        )[0]
        self.assertIn("Ok(Some(grantee)) if !grantee.is_user_account()", grantee)
        self.assertIn(
            ".equal(Property::MemberGroupIds, u64::from(grantee_id))", grantee
        )
        storage = (
            self.root / "crates/http/src/independent_scim/storage.rs"
        ).read_text()
        self.assertIn(
            "independent_scim_revoke_account_grants(server, id.document_id()).await",
            storage,
        )

    def test_jit_final_guard_and_protected_membership_source_contract(self):
        source = (self.root / "crates/common/src/cache/directory.rs").read_text()
        self.assertEqual(source.count(".write_directory_account(RegistryWrite::"), 4)
        self.assertNotIn(".write(RegistryWrite::", source)
        guard = source.split("    async fn write_directory_account(", 1)[1].split(
            "    pub async fn synchronize_account(", 1
        )[0]
        self.assertIn('#[cfg(not(feature = "independent-scim"))]', guard)
        self.assertIn("self.registry().write(write).await", guard)
        capture = "let epoch = self.registry().independent_scim_epoch().await?;"
        self.assertLess(
            guard.index(capture),
            guard.index("self.scim_domain_authoritative(domain_id)"),
        )
        self.assertLess(
            guard.index(capture), guard.index("self.scim_group_authoritative(*id)")
        )
        self.assertIn(
            "self.registry().write_with_independent_scim_epoch(write, epoch).await",
            guard,
        )
        self.assertIn(
            "!old_members.contains(id) && self.scim_group_authoritative(*id).await?",
            guard,
        )
        self.assertIn(
            "!new.member_group_ids.contains(id) && self.scim_group_authoritative(*id).await?",
            guard,
        )
        self.assertIn(
            "current.contains(&id) || !self.scim_group_authoritative(id).await?", source
        )
        self.assertIn(
            "if !members.contains(id) && self.scim_group_authoritative(*id).await? {\n"
            "                members.push(*id);",
            source,
        )
        self.assertIn(
            "current_user.member_group_ids.as_slice(), member_group_ids,", source
        )
        self.assertIn(
            "self.scim_directory_memberships(&[], member_group_ids).await?", source
        )
        self.assertIn("object::<registry::schema::structs::Domain>(domain_id)", source)
        self.assertIn("object::<Account>(group_id).await?", source)

    def test_acl_grant_existence_and_native_outbox_source_contract(self):
        source = (self.root / "crates/store/src/write/batch.rs").read_text()
        grant = source.split("    pub fn acl_grant(", 1)[1].split(
            "    pub fn acl_revoke(", 1
        )[0]
        self.assertIn('#[cfg(feature = "independent-scim")]', grant)
        self.assertIn("[owner.unwrap_or(u32::MAX), grant_account_id]", grant)
        self.assertIn("ObjectType::Account as u16", grant)
        self.assertIn("super::assert::AssertValue::Some", grant)
        self.assertIn("if owner.is_none()", grant)
        self.assertIn("super::assert::AssertValue::None", grant)
        self.assertLess(
            grant.index("self.assert_value("),
            grant.index("self.ops.push(Operation::Value"),
        )
        task = (
            self.root / "crates/services/src/task_manager/tasks/destroy_account.rs"
        ).read_text()
        body = task.split(
            "async fn destroy_account(server: &Server, task: &TaskDestroyAccount)", 1
        )[1]
        revoke = body.index(
            "independent_scim_revoke_account_grants(server, account_id).await?"
        )
        self.assertLess(body.index("return Ok(Outcome::Done("), revoke)
        self.assertLess(revoke, body.index(".remove_grantee_references("))
        self.assertLess(revoke, body.index(".danger_destroy_account(account_id)"))
        self.assertIn('#[cfg(feature = "independent-scim")]', body[:revoke])
        cleanup = task.split("pub async fn independent_scim_revoke_account_grants", 1)[
            1
        ].split("async fn destroy_account(server:", 1)[0]
        self.assertIn("server.revoke_account_grants(account_id)", cleanup)
        self.assertIn("RegistryQuery::new(ObjectType::Account)", cleanup)
        self.assertIn("CacheInvalidation::AccessToken(account_id)", cleanup)
        self.assertIn("CacheInvalidation::AccessToken(account.document_id())", cleanup)
        self.assertIn("server.invalidate_caches(invalidation).await", cleanup)
        self.assertIn("invalidation.await?;\n    cleanup_result.map(|_| ())", task)
        self.assertIn(
            "cancelled_partial_cleanup_is_recovered_by_the_next_global_sweep", task
        )
        main = (self.root / "crates/main/Cargo.toml").read_text()
        self.assertIn('"services/independent-scim"', main)
        services = (self.root / "crates/services/Cargo.toml").read_text()
        self.assertIn('independent-scim = ["common/independent-scim"]', services)

    def test_patch_bundle_has_disjoint_existing_targets(self):
        targets = [
            line.removeprefix("+++ b/")
            for patch in sorted(HOOK.PATCH_DIRECTORY.glob("*.patch"))
            for line in patch.read_text().splitlines()
            if line.startswith("+++ b/")
        ]
        self.assertTrue(targets)
        self.assertEqual(len(targets), len(set(targets)))
        for target in targets:
            self.assertTrue((self.baseline / target).is_file(), target)

    def test_late_patch_mismatch_leaves_entire_source_unchanged(self):
        with tempfile.TemporaryDirectory(prefix="stalwart-patch-failure-") as directory:
            root = Path(directory) / "source"
            shutil.copytree(self.baseline, root)
            target = root / "crates/common/src/manager/defaults.rs"
            original = target.read_text()
            changed = original.replace(
                "webui/releases/download/v2", "unexpected/releases/download/v2"
            )
            self.assertNotEqual(original, changed)
            target.write_text(changed)

            def contents():
                return {
                    path.relative_to(root): path.read_bytes()
                    for path in root.rglob("*")
                    if path.is_file()
                }

            before = contents()
            with self.assertRaisesRegex(
                RuntimeError, "Pinned-source integration mismatch"
            ):
                HOOK.apply(root, Path(__file__).with_name("native"))
            self.assertEqual(before, contents())
            self.assertFalse((root / "crates/http/src/independent_scim").exists())

    def test_reapplication_is_rejected_before_mutation(self):
        manifest = self.root / "crates/main/Cargo.toml"
        before = manifest.read_bytes()
        with self.assertRaisesRegex(RuntimeError, "already applied"):
            HOOK.apply(self.root, Path(__file__).with_name("native"))
        self.assertEqual(before, manifest.read_bytes())


if __name__ == "__main__":
    unittest.main()
