// SPDX-License-Identifier: AGPL-3.0-only
//! Native SCIM persistence. Every visible mutation is one registry-store batch.
//!
//! Required host hook: every native registry write must set epoch_key() to a fresh
//! non-expiring value (u64::MAX expiry followed by assign_id().to_be_bytes())
//! IN ITS OWN WRITE BATCH. This
//! protects enumeration predicates against native writers, not just SCIM writers.
//! Account revisions protect individual rows; the epoch protects membership ranges.
//! Deletion requires registry and task/data stores to be the same native store.
//!
//! SCIM permissions authorize server-owned defaults and exact saved-state restoration,
//! never arbitrary client-supplied roles/permissions. No elevated token is constructed.

use super::protocol::Error;
use common::{
    Server, auth::AccessToken, cache::invalidate::CacheInvalidationBuilder, ipc::CacheInvalidation,
};
use registry::{
    schema::{
        enums::{AccountType, Locale, Permission, TimeZone},
        prelude::{OBJ_FILTER_TENANT, Object, ObjectInner, ObjectType, Property},
        structs::{
            Account, Authentication, Domain, EmailAlias, GroupAccount, Permissions,
            PermissionsList, Role, Task, TaskDestroyAccount, TaskStatus, UserAccount, UserRoles,
        },
    },
    types::{
        EnumImpl, ObjectImpl,
        datetime::UTCDateTime,
        id::ObjectId,
        index::{IndexBuilder, IndexKey, IndexValue},
        list::List,
    },
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};
use store::{
    SerializeInfallible, ValueKey,
    registry::{RegistryObject, RegistryQuery},
    write::{BatchBuilder, InMemoryClass, RegistryClass, ValueClass, assert::AssertValue},
};
use types::id::Id;

pub(super) fn error(
    status: u16,
    scim_type: Option<&'static str>,
    detail: impl Into<String>,
) -> Error {
    Error {
        status,
        scim_type,
        detail: detail.into(),
    }
}
const RETRY_SNAPSHOT: &str = "SCIM internal snapshot conflict";
fn internal() -> Error {
    error(500, None, "Native registry operation failed")
}
pub(super) fn authorize(token: &AccessToken, permission: Permission) -> Result<(), Error> {
    if token.has_permission(Permission::Authenticate)
        && token.has_permission(Permission::ScimAccess)
        && token.has_permission(permission)
    {
        Ok(())
    } else {
        Err(error(
            403,
            None,
            "Authenticate, ScimAccess, and the native account operation permission are required",
        ))
    }
}
pub(super) fn epoch_key() -> ValueClass {
    ValueClass::InMemory(InMemoryClass::Key(
        store::registry::write::INDEPENDENT_SCIM_EPOCH_KEY.to_vec(),
    ))
}
fn state_key(id: Id) -> ValueClass {
    let mut key = b"independent-scim/suspended/v1/".to_vec();
    key.extend_from_slice(&id.id().to_be_bytes());
    ValueClass::InMemory(InMemoryClass::Key(key))
}
async fn read_epoch(server: &Server) -> Result<Option<u64>, Error> {
    server
        .registry()
        .store()
        .get_value::<NativeEpoch>(ValueKey::from(epoch_key()))
        .await
        .map(|value| value.map(|value| value.0))
        .map_err(|_| internal())
}
#[derive(Clone, Serialize, Deserialize)]
struct SavedState {
    permissions: Permissions,
}

struct NativeEpoch(u64);
impl store::Deserialize for NativeEpoch {
    fn deserialize(bytes: &[u8]) -> trc::Result<Self> {
        if bytes.len() != 16 || bytes[..8] != u64::MAX.to_be_bytes() {
            return Err(trc::StoreEvent::DataCorruption.into_err());
        }
        <u64 as store::Deserialize>::deserialize(&bytes[8..]).map(Self)
    }
}
impl store::Deserialize for SavedState {
    fn deserialize(bytes: &[u8]) -> trc::Result<Self> {
        if bytes.len() < 8 || bytes[..8] != u64::MAX.to_be_bytes() {
            return Err(trc::StoreEvent::DataCorruption.into_err());
        }
        serde_json::from_slice(&bytes[8..]).map_err(|_| trc::StoreEvent::DataCorruption.into_err())
    }
}
fn durable_value(payload: &[u8]) -> Vec<u8> {
    let mut value = u64::MAX.to_be_bytes().to_vec();
    value.extend_from_slice(payload);
    value
}

pub(super) struct Snapshot {
    pub accounts: Vec<RegistryObject<Account>>,
    pub domains: Vec<RegistryObject<Domain>>,
    pub epoch: Option<u64>,
    suspended: BTreeMap<Id, SavedState>,
    active: BTreeMap<Id, bool>,
}
fn scope(account: &Account) -> (Id, Option<Id>) {
    match account {
        Account::User(a) => (a.domain_id, a.member_tenant_id),
        Account::Group(a) => (a.domain_id, a.member_tenant_id),
    }
}
fn object(account: &RegistryObject<Account>) -> Object {
    Object {
        inner: ObjectInner::Account(account.object.clone()),
        revision: account.revision,
    }
}
fn group_display_name(group: &GroupAccount) -> &str {
    group
        .description
        .as_deref()
        .filter(|value| !value.is_empty())
        .unwrap_or(&group.name)
}
fn set_group_display_name(group: &mut GroupAccount, display: &str, creating: bool) {
    if creating || group_display_name(group) != display {
        group.description = Some(display.to_owned());
    }
}
fn group_slug(display: &str) -> String {
    let mut slug = String::new();
    let mut separator = false;
    for ch in display.chars() {
        if ch.is_ascii_alphanumeric() {
            if separator && !slug.is_empty() {
                slug.push('-');
            }
            separator = false;
            slug.push(ch.to_ascii_lowercase());
        } else {
            separator = true;
        }
    }
    if slug.is_empty() {
        slug.push_str("group");
    }
    slug.truncate(64);
    while slug.ends_with('-') {
        slug.pop();
    }
    slug
}
fn suffixed_slug(slug: &str, suffix: u32) -> String {
    if suffix == 0 {
        return slug.to_owned();
    }
    let suffix = format!("-{suffix}");
    let base = &slug[..slug.len().min(64usize.saturating_sub(suffix.len()))];
    format!("{}{suffix}", base.trim_end_matches('-'))
}
async fn derive_group_name(server: &Server, domain: Id, display: &str) -> Result<String, Error> {
    let slug = group_slug(display);
    for suffix in 0..1000 {
        let name = suffixed_slug(&slug, suffix);
        let mut key = name.as_bytes().to_vec();
        key.extend_from_slice(&domain.id().to_be_bytes());
        if server
            .registry()
            .primary_key(None, Property::Email, key)
            .await
            .map_err(|_| internal())?
            .is_none()
        {
            return Ok(name);
        }
    }
    Err(error(
        409,
        Some("uniqueness"),
        "No free group address variant within the collision limit",
    ))
}

fn account_value(account: Account) -> Object {
    Object {
        inner: ObjectInner::Account(account),
        revision: 0,
    }
}
fn suspended_permissions(original: &Permissions) -> Permissions {
    let mut permissions = match original {
        Permissions::Inherit => Permissions::Merge(PermissionsList::default()),
        other => other.clone(),
    };
    let (Permissions::Merge(list) | Permissions::Replace(list)) = &mut permissions else {
        unreachable!()
    };
    list.enabled_permissions
        .inner_mut()
        .retain(|permission| *permission != Permission::Authenticate);
    if !list
        .disabled_permissions
        .contains(&Permission::Authenticate)
    {
        list.disabled_permissions.push(Permission::Authenticate);
    }
    permissions
}
fn suspend(user: &mut UserAccount) {
    // Suspension owns only Authenticate. Roles, unrelated grants/denials, and
    // Merge/Replace mode stay intact; Inherit needs a temporary Merge wrapper.
    user.permissions = suspended_permissions(&user.permissions);
}
fn is_suspended(user: &UserAccount) -> bool {
    match &user.permissions {
        Permissions::Merge(list) | Permissions::Replace(list) => {
            list.disabled_permissions
                .contains(&Permission::Authenticate)
                && !list.enabled_permissions.contains(&Permission::Authenticate)
        }
        Permissions::Inherit => false,
    }
}
fn restore_active(user: &mut UserAccount, saved: &SavedState) -> Result<(), Error> {
    if !is_suspended(user) {
        return Err(error(
            409,
            None,
            "Authenticate was changed outside SCIM while suspended",
        ));
    }
    if user.permissions == suspended_permissions(&saved.permissions) {
        // Exact mode and ordering restoration when there were no local edits.
        user.permissions = saved.permissions.clone();
    } else {
        // Local roles and unrelated permission edits are not owned by SCIM. Keep
        // them and restore only the two Authenticate bits we changed.
        let (was_enabled, was_disabled) = match &saved.permissions {
            Permissions::Inherit => (false, false),
            Permissions::Merge(list) | Permissions::Replace(list) => (
                list.enabled_permissions.contains(&Permission::Authenticate),
                list.disabled_permissions
                    .contains(&Permission::Authenticate),
            ),
        };
        let (Permissions::Merge(list) | Permissions::Replace(list)) = &mut user.permissions else {
            unreachable!()
        };
        list.enabled_permissions
            .inner_mut()
            .retain(|permission| *permission != Permission::Authenticate);
        list.disabled_permissions
            .inner_mut()
            .retain(|permission| *permission != Permission::Authenticate);
        if was_enabled {
            list.enabled_permissions.push(Permission::Authenticate);
        }
        if was_disabled {
            list.disabled_permissions.push(Permission::Authenticate);
        }
    }
    Ok(())
}
// The OSS effective-permission rule: union enabled and disabled permissions over
// reachable roles, then subtract disabled. Replace suppresses role inheritance.
fn effective_authenticate(
    user: &UserAccount,
    defaults: &[Id],
    roles: &BTreeMap<Id, Role>,
) -> Result<bool, Error> {
    effective_permission(user, defaults, roles, Permission::Authenticate)
}
fn effective_permission(
    user: &UserAccount,
    defaults: &[Id],
    roles: &BTreeMap<Id, Role>,
    permission: Permission,
) -> Result<bool, Error> {
    let (mut enabled, mut disabled, inherit) = match &user.permissions {
        Permissions::Inherit => (false, false, true),
        Permissions::Merge(list) => (
            list.enabled_permissions.contains(&permission),
            list.disabled_permissions.contains(&permission),
            true,
        ),
        Permissions::Replace(list) => (
            list.enabled_permissions.contains(&permission),
            list.disabled_permissions.contains(&permission),
            false,
        ),
    };
    let mut pending = if inherit {
        defaults.to_vec()
    } else {
        Vec::new()
    };
    let mut visited = BTreeSet::new();
    while let Some(id) = pending.pop() {
        if visited.insert(id) {
            let role = roles
                .get(&id)
                .ok_or_else(|| error(409, None, "Native role no longer exists"))?;
            enabled |= role.enabled_permissions.contains(&permission);
            disabled |= role.disabled_permissions.contains(&permission);
            pending.extend(role.role_ids.iter().copied());
        }
    }
    Ok(enabled && !disabled)
}
fn enum_value<E: EnumImpl>(input: &str) -> Option<E> {
    let find = |input: &str| {
        (0..E::COUNT)
            .filter_map(|i| E::from_id(i as u16))
            .find(|value| value.as_str().eq_ignore_ascii_case(input))
    };
    find(input).or_else(|| find(&input.replace('_', "-").replace('@', "-")))
}

// RegistryStore::list hardcodes the configuration subspace, whereas accounts,
// domains and roles live in the directory subspace. Query the native ID index
// and use get(), which selects the correct subspace and computes row revisions.
async fn native_rows<T: ObjectImpl + From<Object>>(
    server: &Server,
) -> Result<Vec<RegistryObject<T>>, Error> {
    let ids = server
        .registry()
        .query::<Vec<Id>>(RegistryQuery::new(T::OBJECT))
        .await
        .map_err(|_| internal())?;
    let mut rows = Vec::with_capacity(ids.len());
    for id in ids {
        let id = ObjectId::new(T::OBJECT, id);
        if let Some(object) = server.registry().get(id).await.map_err(|_| internal())? {
            rows.push(RegistryObject {
                id,
                revision: object.revision,
                object: T::from(object),
            });
        }
    }
    // The caller's surrounding epoch fence detects inserts/deletes during this scan.
    Ok(rows)
}

impl Snapshot {
    pub async fn load(server: &Server, token: &AccessToken) -> Result<Self, Error> {
        authorize(token, Permission::ScimAccess)?;
        if server.registry().is_bootstrap_mode() {
            return Err(error(403, None, "SCIM is unavailable during bootstrap"));
        }
        for _ in 0..3 {
            let epoch = read_epoch(server).await?;
            let domains = native_rows::<Domain>(server)
                .await?
                .into_iter()
                .filter(|d| {
                    d.object.allow_scim_provisioning
                        && token
                            .tenant_id()
                            .is_none_or(|t| d.object.member_tenant_id == Some(Id::from(t)))
                })
                .collect::<Vec<_>>();
            let accounts = native_rows::<Account>(server)
                .await?
                .into_iter()
                .filter(|entry| {
                    let (domain, tenant) = scope(&entry.object);
                    token
                        .tenant_id()
                        .is_none_or(|t| tenant == Some(Id::from(t)))
                        && domains
                            .iter()
                            .any(|d| d.id.id() == domain && d.object.member_tenant_id == tenant)
                })
                .collect::<Vec<_>>();
            // Read roles from the guarded registry, not the eventually invalidated auth
            // cache: otherwise an epoch could describe a pre-invalidation permission view.
            let authentication = server
                .registry()
                .object::<Authentication>(Id::singleton())
                .await
                .map_err(|_| internal())?
                .unwrap_or_default();
            let roles_by_id = native_rows::<Role>(server)
                .await?
                .into_iter()
                .map(|entry| (entry.id.id(), entry.object))
                .collect::<BTreeMap<_, _>>();
            let mut suspended = BTreeMap::new();
            let mut active = BTreeMap::new();
            for entry in &accounts {
                if let Account::User(user) = &entry.object {
                    if let Some(state) = server
                        .registry()
                        .store()
                        .get_value::<SavedState>(ValueKey::from(state_key(entry.id.id())))
                        .await
                        .map_err(|_| internal())?
                    {
                        suspended.insert(entry.id.id(), state);
                    }
                    let roles = match &user.roles {
                        UserRoles::User => authentication.default_user_role_ids.as_slice(),
                        UserRoles::Admin if user.member_tenant_id.is_some() => {
                            authentication.default_tenant_role_ids.as_slice()
                        }
                        UserRoles::Admin => authentication.default_admin_role_ids.as_slice(),
                        UserRoles::Custom(roles) => roles.role_ids.as_slice(),
                    };
                    active.insert(
                        entry.id.id(),
                        effective_authenticate(user, roles, &roles_by_id)?,
                    );
                }
            }
            if read_epoch(server).await? == epoch {
                return Ok(Self {
                    accounts,
                    domains,
                    epoch,
                    suspended,
                    active,
                });
            }
        }
        Err(error(
            409,
            None,
            "Registry changed during enumeration; retry",
        ))
    }
    pub fn account(&self, id: Id, kind: &str) -> Option<&RegistryObject<Account>> {
        self.accounts.iter().find(|a| {
            a.id.id() == id
                && matches!(
                    (&a.object, kind),
                    (Account::User(_), "Users") | (Account::Group(_), "Groups")
                )
        })
    }
    /// Intersect public indexed equality terms using the native registry indexes.
    /// The snapshot remains the authoritative domain/tenant boundary and supplies
    /// reverse memberships. Null comparisons fall back to the bounded semantic pass.
    pub async fn indexed_candidates(
        &self,
        server: &Server,
        token: &AccessToken,
        terms: &[(String, Value)],
    ) -> Result<Option<BTreeSet<Id>>, Error> {
        let mut result: Option<BTreeSet<Id>> = None;
        for (path, value) in terms {
            let Some(text) = value.as_str() else {
                continue;
            };
            let ids = match path.as_str() {
                "id" => Some(parse_id(text).ok().into_iter().collect::<BTreeSet<_>>()),
                "externalid" => Some(
                    server
                        .registry()
                        .query::<Vec<Id>>(
                            RegistryQuery::new(ObjectType::Account)
                                .with_tenant(token.tenant_id())
                                .equal(Property::ExternalId, text),
                        )
                        .await
                        .map_err(|_| internal())?
                        .into_iter()
                        .collect(),
                ),
                "groups.value" => {
                    let ids = if let Ok(id) = parse_id(text) {
                        server
                            .registry()
                            .query::<Vec<Id>>(
                                RegistryQuery::new(ObjectType::Account)
                                    .with_tenant(token.tenant_id())
                                    .equal(Property::MemberGroupIds, id.id()),
                            )
                            .await
                            .map_err(|_| internal())?
                    } else {
                        Vec::new()
                    };
                    Some(ids.into_iter().collect())
                }
                "members.value" => {
                    let mut ids = BTreeSet::new();
                    if let Ok(id) = parse_id(text)
                        && let Some(entry) = self.account(id, "Users")
                        && let Account::User(user) = &entry.object
                    {
                        ids.extend(user.member_group_ids.iter().copied());
                    }
                    Some(ids)
                }
                "username" | "emails.value" => {
                    let mut ids = BTreeSet::new();
                    if let Some((name, domain_name)) = text.rsplit_once('@') {
                        for domain in self.domains.iter().filter(|domain| {
                            domain.object.name.to_lowercase() == domain_name.to_lowercase()
                        }) {
                            let mut key = name.to_lowercase().into_bytes();
                            key.extend_from_slice(&domain.id.id().id().to_be_bytes());
                            if let Some(id) = server
                                .registry()
                                .primary_key(None, Property::Email, key)
                                .await
                                .map_err(|_| internal())?
                                && id.object() == ObjectType::Account
                            {
                                ids.insert(id.id());
                            }
                        }
                        // Native preexisting names need not have been lowercased by SCIM.
                        // Do not lose these resources because the native PK is case-sensitive.
                        let matches = |name: &str, domain_id: Id| {
                            name != name.to_lowercase()
                                && self.domain(domain_id).is_ok_and(|domain| {
                                    format!("{name}@{}", domain.object.name).to_lowercase()
                                        == text.to_lowercase()
                                })
                        };
                        for entry in &self.accounts {
                            if let Account::User(user) = &entry.object {
                                if matches(&user.name, user.domain_id)
                                    || (path == "emails.value"
                                        && user.aliases.values().any(|alias| {
                                            alias.enabled && matches(&alias.name, alias.domain_id)
                                        }))
                                {
                                    ids.insert(entry.id.id());
                                }
                            }
                        }
                    }
                    Some(ids)
                }
                _ => None,
            };
            if let Some(ids) = ids {
                if let Some(result) = &mut result {
                    result.retain(|id| ids.contains(id));
                } else {
                    result = Some(ids);
                }
            }
        }
        if read_epoch(server).await? != self.epoch {
            return Err(error(
                409,
                None,
                "Registry changed during indexed search; retry",
            ));
        }
        Ok(result)
    }

    pub fn etag(&self, account: &RegistryObject<Account>) -> String {
        use sha2::Digest;
        // External versions describe SCIM content, not the coarse internal lock.
        // The canonical relative locations make this independent of proxy origins.
        let resource = self.render_unversioned(account, "");
        let digest = sha2::Sha256::digest(resource.to_string().as_bytes());
        let hex = digest
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>();
        format!("\"{hex}\"")
    }
    pub fn assert_match(
        &self,
        account: &RegistryObject<Account>,
        header: Option<&str>,
    ) -> Result<(), Error> {
        if let Some(header) = header {
            let etag = self.etag(account);
            if !header.split(',').any(|item| {
                let item = item.trim();
                item == "*" || item == etag
            }) {
                return Err(error(412, None, "Resource version does not match If-Match"));
            }
        }
        Ok(())
    }
    fn domain(&self, id: Id) -> Result<&RegistryObject<Domain>, Error> {
        self.domains
            .iter()
            .find(|domain| domain.id.id() == id)
            .ok_or_else(|| {
                error(
                    400,
                    Some("invalidValue"),
                    "Domain is not opted into SCIM provisioning",
                )
            })
    }
    fn address(&self, address: &str, tenant: Option<Id>) -> Result<(String, Id), Error> {
        let (name, domain) = address
            .rsplit_once('@')
            .ok_or_else(|| error(400, Some("invalidValue"), "Expected a full email address"))?;
        let domain = self
            .domains
            .iter()
            .find(|d| {
                d.object.member_tenant_id == tenant
                    && (d.object.name.eq_ignore_ascii_case(domain)
                        || d.object
                            .aliases
                            .iter()
                            .any(|alias| alias.eq_ignore_ascii_case(domain)))
            })
            .ok_or_else(|| {
                error(
                    400,
                    Some("invalidValue"),
                    "Email domain is not opted into SCIM provisioning in this tenant",
                )
            })?;
        Ok((name.to_owned(), domain.id.id()))
    }
    pub fn render(&self, entry: &RegistryObject<Account>, base: &str) -> Value {
        let mut resource = self.render_unversioned(entry, base);
        resource["meta"]["version"] = json!(self.etag(entry));
        resource
    }
    fn render_unversioned(&self, entry: &RegistryObject<Account>, base: &str) -> Value {
        let id = entry.id.id().to_string();
        let (kind, schema, created, mut resource) = match &entry.object {
            Account::User(a) => {
                let domain = self.domain(a.domain_id).expect("snapshot domain invariant");
                let username = format!("{}@{}", a.name, domain.object.name);
                let groups = a.member_group_ids.iter().filter_map(|id| {
                    let entry = self.account(*id, "Groups")?;
                    let Account::Group(group) = &entry.object else { return None; };
                    Some(json!({"value":id.to_string(), "$ref":format!("{base}/Groups/{id}"), "type":"direct", "display":group_display_name(group)}))
                }).collect::<Vec<_>>();
                let mut emails = vec![json!({"value":username,"primary":true,"type":"work"})];
                for alias in a.aliases.values().filter(|a| a.enabled) {
                    if let Ok(domain) = self.domain(alias.domain_id) {
                        emails.push(json!({"value":format!("{}@{}",alias.name,domain.object.name),"primary":false,"type":"work"}));
                    }
                }
                let mut value = json!({"userName":username,"displayName":a.description.as_deref().unwrap_or_default(),"name":{"formatted":a.description.as_deref().unwrap_or_default()},"emails":emails,"groups":groups,"active":self.active.get(&entry.id.id()).copied().unwrap_or(false),"locale":a.locale,"preferredLanguage":a.locale});
                if let Some(tz) = &a.time_zone {
                    value["timezone"] = json!(tz);
                }
                if let Some(external) = &a.external_id {
                    value["externalId"] = json!(external);
                }
                ("User", super::protocol::USER_SCHEMA, a.created_at, value)
            }
            Account::Group(a) => {
                let group_id = entry.id.id();
                let members = self.accounts.iter().filter_map(|entry| match &entry.object {
                    Account::User(user) if user.member_group_ids.contains(&group_id) => {
                        let mut member = json!({"value":entry.id.id().to_string(),"$ref":format!("{base}/Users/{}",entry.id.id()),"type":"User"});
                        if let Some(description) = &user.description { member["display"] = json!(description); }
                        Some(member)
                    },
                    _ => None,
                }).collect::<Vec<_>>();
                let mut value = json!({"displayName":group_display_name(a),"members":members});
                if let Some(external) = &a.external_id {
                    value["externalId"] = json!(external);
                }
                ("Group", super::protocol::GROUP_SCHEMA, a.created_at, value)
            }
        };
        resource["schemas"] = json!([schema]);
        resource["id"] = json!(id);
        for key in ["groups", "members", "emails"] {
            if let Some(values) = resource.get_mut(key).and_then(Value::as_array_mut) {
                values.sort_by(|a, b| {
                    let primary = b
                        .get("primary")
                        .and_then(Value::as_bool)
                        .unwrap_or(false)
                        .cmp(&a.get("primary").and_then(Value::as_bool).unwrap_or(false));
                    primary.then_with(|| a["value"].as_str().cmp(&b["value"].as_str()))
                });
            }
        }
        resource["meta"] = json!({"resourceType":kind,"location":format!("{base}/{kind}s/{id}"),"created":created});
        resource
    }

    /// Create, replace, or delete a native account and any affected membership rows.
    /// None document denotes DELETE; None id denotes CREATE. The epoch is asserted
    /// in the same batch as all indexes, rows, saved state, and destruction task.
    pub async fn mutate(
        &self,
        server: &Server,
        token: &AccessToken,
        kind: &str,
        id: Option<Id>,
        document: Option<&Value>,
        if_match: Option<&str>,
    ) -> Result<Id, Error> {
        let original_version = id
            .and_then(|id| self.account(id, kind))
            .map(|account| self.etag(account));
        let mut fresh = None;
        for attempt in 0..4 {
            let snapshot = fresh.as_ref().unwrap_or(self);
            match snapshot
                .mutate_once(server, token, kind, id, document, if_match)
                .await
            {
                Err(err) if err.detail == RETRY_SNAPSHOT => {
                    if attempt == 3 {
                        return Err(error(409, None, "Registry remains busy; retry the request"));
                    }
                    let snapshot = Snapshot::load(server, token).await?;
                    if let Some(id) = id {
                        let account = snapshot
                            .account(id, kind)
                            .ok_or_else(|| error(404, None, "Resource not found"))?;
                        snapshot.assert_match(account, if_match)?;
                        // Reusing a normalized PATCH is safe only when its public input
                        // view is unchanged. Local non-SCIM settings are cloned afresh.
                        if document.is_some()
                            && original_version.as_deref() != Some(snapshot.etag(account).as_str())
                        {
                            return Err(error(
                                409,
                                None,
                                "Resource changed concurrently; reapply the patch to its current version",
                            ));
                        }
                    }
                    fresh = Some(snapshot);
                }
                result => return result,
            }
        }
        unreachable!()
    }
    async fn mutate_once(
        &self,
        server: &Server,
        token: &AccessToken,
        kind: &str,
        id: Option<Id>,
        document: Option<&Value>,
        if_match: Option<&str>,
    ) -> Result<Id, Error> {
        let creating = id.is_none();
        let deleting = document.is_none();
        authorize(
            token,
            if creating {
                Permission::SysAccountCreate
            } else if deleting {
                Permission::SysAccountDestroy
            } else {
                Permission::SysAccountUpdate
            },
        )?;
        let old = id
            .map(|id| {
                self.account(id, kind)
                    .ok_or_else(|| error(404, None, "Resource not found"))
            })
            .transpose()?;
        if let Some(old) = old {
            self.assert_match(old, if_match)?;
        } else if if_match.is_some() {
            return Err(error(412, None, "If-Match requires an existing resource"));
        }
        if deleting && id.is_some_and(|id| id.id() == u64::from(token.account_id())) {
            return Err(error(
                403,
                None,
                "A provisioning principal cannot delete itself",
            ));
        }
        let mut state_change: Option<Option<SavedState>> = None;
        let mut changes: Vec<Change> = Vec::new();
        let id = if let Some(id) = id {
            id
        } else {
            let mut batch = BatchBuilder::new();
            batch.add_and_get(
                ValueClass::Registry(RegistryClass::IdCounter {
                    object_id: ObjectType::Account.to_id(),
                }),
                1,
            );
            let id = server
                .registry()
                .store()
                .write(batch.build_all())
                .await
                .map_err(|_| internal())?
                .last_counter_id()
                .map_err(|_| internal())?;
            let id = u32::try_from(id)
                .map_err(|_| error(507, None, "Native account ID space exhausted"))?;
            Id::from(id)
        };
        let mut account = if let Some(old) = old {
            old.object.clone()
        } else if kind == "Users" {
            let doc =
                document.ok_or_else(|| error(400, Some("invalidValue"), "Missing resource"))?;
            let username = doc["userName"]
                .as_str()
                .ok_or_else(|| error(400, Some("invalidValue"), "userName required"))?;
            // For global service principals, the target domain determines tenant ownership.
            let domain_name = username.rsplit_once('@').map(|v| v.1).unwrap_or_default();
            let domain = self
                .domains
                .iter()
                .find(|d| {
                    d.object.name.eq_ignore_ascii_case(domain_name)
                        || d.object
                            .aliases
                            .iter()
                            .any(|alias| alias.eq_ignore_ascii_case(domain_name))
                })
                .ok_or_else(|| {
                    error(
                        400,
                        Some("invalidValue"),
                        "Domain is not opted into SCIM provisioning",
                    )
                })?;
            Account::User(UserAccount {
                domain_id: domain.id.id(),
                member_tenant_id: domain.object.member_tenant_id,
                created_at: UTCDateTime::now(),
                ..UserAccount::default()
            })
        } else {
            let principal = server
                .registry()
                .object::<Account>(Id::from(token.account_id()))
                .await
                .map_err(|_| internal())?
                .ok_or_else(|| error(403, None, "Provisioning principal has no native domain"))?;
            let (domain, tenant) = scope(&principal);
            self.domain(domain)?;
            Account::Group(GroupAccount {
                domain_id: domain,
                member_tenant_id: tenant,
                created_at: UTCDateTime::now(),
                ..GroupAccount::default()
            })
        };
        let tenant = scope(&account).1;
        let mut wanted_members = BTreeSet::new();
        if let Some(doc) = document {
            match &mut account {
                Account::User(user) => {
                    let (name, domain) = self.address(
                        doc["userName"]
                            .as_str()
                            .ok_or_else(|| error(400, Some("invalidValue"), "userName required"))?,
                        tenant,
                    )?;
                    user.name = name;
                    user.domain_id = domain;
                    user.description = doc
                        .get("displayName")
                        .and_then(Value::as_str)
                        .filter(|v| !v.is_empty())
                        .map(str::to_owned);
                    user.external_id = doc
                        .get("externalId")
                        .and_then(Value::as_str)
                        .map(str::to_owned);
                    user.locale = if let Some(value) = doc.get("locale").and_then(Value::as_str) {
                        enum_value::<Locale>(value).ok_or_else(|| {
                            error(400, Some("invalidValue"), "Unknown native locale")
                        })?
                    } else {
                        Locale::EnUS
                    };
                    user.time_zone = doc
                        .get("timezone")
                        .and_then(Value::as_str)
                        .map(|tz| {
                            enum_value::<TimeZone>(tz).ok_or_else(|| {
                                error(400, Some("invalidValue"), "Unknown native timezone")
                            })
                        })
                        .transpose()?;
                    // Preserve native alias order/metadata and unrepresented disabled or
                    // out-of-scope aliases. Explicitly adding a disabled alias enables it.
                    let mut wanted = BTreeSet::new();
                    for email in doc["emails"]
                        .as_array()
                        .into_iter()
                        .flatten()
                        .filter(|email| email["primary"] != Value::Bool(true))
                    {
                        wanted.insert(
                            self.address(
                                email["value"].as_str().ok_or_else(|| {
                                    error(400, Some("invalidValue"), "Invalid alias")
                                })?,
                                tenant,
                            )?,
                        );
                    }
                    let mut aliases = List::default();
                    for alias in user.aliases.values() {
                        if wanted.remove(&(alias.name.clone(), alias.domain_id)) {
                            let mut alias = alias.clone();
                            alias.enabled = true;
                            aliases.push(alias);
                        } else if !alias.enabled || self.domain(alias.domain_id).is_err() {
                            aliases.push(alias.clone());
                        }
                    }
                    for (name, domain_id) in wanted {
                        aliases.push(EmailAlias {
                            enabled: true,
                            name,
                            domain_id,
                            description: None,
                        });
                    }
                    user.aliases = aliases;
                    let desired = doc["active"].as_bool().unwrap_or(true);
                    if !desired
                        && (creating
                            || self.active.get(&id) != Some(&false)
                            || self.suspended.contains_key(&id))
                    {
                        if id.id() == u64::from(token.account_id()) {
                            return Err(error(
                                403,
                                None,
                                "A provisioning principal cannot deactivate itself",
                            ));
                        }
                        if !self.suspended.contains_key(&id) {
                            state_change = Some(Some(SavedState {
                                permissions: user.permissions.clone(),
                            }));
                        } else if !is_suspended(user) {
                            return Err(error(
                                409,
                                None,
                                "Permissions changed outside SCIM while suspended",
                            ));
                        }
                        suspend(user);
                    } else if desired && let Some(saved) = self.suspended.get(&id) {
                        if !is_suspended(user) {
                            return Err(error(
                                409,
                                None,
                                "Permissions changed outside SCIM while suspended",
                            ));
                        }
                        restore_active(user, saved)?;
                        state_change = Some(None);
                    } else if desired && !creating && self.active.get(&id) == Some(&false) {
                        return Err(error(
                            409,
                            None,
                            "Account was disabled outside SCIM; prior role state is unknown",
                        ));
                    }
                }
                Account::Group(group) => {
                    let display = doc["displayName"]
                        .as_str()
                        .ok_or_else(|| error(400, Some("invalidValue"), "displayName required"))?;
                    // Description uniqueness spans the tenant, including locally managed
                    // groups outside opted-in domains. The epoch serializes this predicate.
                    for other in native_rows::<Account>(server).await? {
                        if other.id.id() != id
                            && let Account::Group(other) = &other.object
                        {
                            if other.member_tenant_id == tenant
                                && group_display_name(other).to_lowercase()
                                    == display.to_lowercase()
                            {
                                return Err(error(
                                    409,
                                    Some("uniqueness"),
                                    "Group displayName already exists in this tenant",
                                ));
                            }
                        }
                    }
                    if creating {
                        group.name = derive_group_name(server, group.domain_id, display).await?;
                    }
                    set_group_display_name(group, display, creating);
                    group.external_id = doc
                        .get("externalId")
                        .and_then(Value::as_str)
                        .map(str::to_owned);
                    for member in doc["members"].as_array().into_iter().flatten() {
                        let member_id = parse_id(member["value"].as_str().unwrap_or_default())
                            .map_err(|_| error(400, Some("invalidValue"), "Invalid member ID"))?;
                        let member = self
                            .account(member_id, "Users")
                            .filter(|a| scope(&a.object).1 == tenant)
                            .ok_or_else(|| {
                                error(
                                    400,
                                    Some("invalidValue"),
                                    "Member is not a visible User in this tenant",
                                )
                            })?;
                        wanted_members.insert(member.id.id());
                    }
                }
            }
        }
        if matches!(&account, Account::Group(_)) {
            // Native members outside the managed universe must never be silently removed.
            if !creating {
                for linked in server
                    .registry()
                    .linked_objects(ObjectId::new(ObjectType::Account, id))
                    .await
                    .map_err(|_| internal())?
                {
                    if linked.object() == ObjectType::Account
                        && self.account(linked.id(), "Users").is_none()
                    {
                        return Err(error(
                            409,
                            None,
                            "Group has members outside the authorized SCIM domain scope",
                        ));
                    }
                }
            }
            for entry in &self.accounts {
                if let Account::User(user) = &entry.object {
                    let has = user.member_group_ids.contains(&id);
                    let wanted = !deleting && wanted_members.contains(&entry.id.id());
                    if has != wanted {
                        let mut new = user.clone();
                        let mut members = new
                            .member_group_ids
                            .iter()
                            .copied()
                            .filter(|group| *group != id)
                            .collect::<Vec<_>>();
                        if wanted {
                            members.push(id);
                        }
                        new.member_group_ids = members.into();
                        changes.push(Change {
                            id: entry.id.id(),
                            old: Some(object(entry)),
                            new: Some(account_value(Account::User(new))),
                        });
                    }
                }
            }
        }
        if !deleting && !changes.is_empty() {
            authorize(token, Permission::SysAccountUpdate)?;
        }
        changes.push(Change {
            id,
            old: old.map(object),
            new: (!deleting).then(|| account_value(account.clone())),
        });
        if deleting {
            if !server.registry().store().is_same(server.store()) {
                return Err(error(
                    503,
                    None,
                    "Atomic account deletion requires the native registry and task store to be the same store",
                ));
            }
            let linked = server
                .registry()
                .linked_objects(ObjectId::new(ObjectType::Account, id))
                .await
                .map_err(|_| internal())?;
            for linked in linked {
                let removed_member = linked.object() == ObjectType::Account
                    && changes.iter().any(|change| change.id == linked.id());
                if !removed_member
                    && !matches!(
                        linked.object(),
                        ObjectType::PublicKey | ObjectType::MaskedEmail
                    )
                {
                    return Err(error(
                        409,
                        None,
                        "Account has native references that must be removed before deletion",
                    ));
                }
            }
        }
        let no_op = !creating && !deleting && state_change.is_none() && changes.iter().all(|change| {
            matches!((&change.old, &change.new), (Some(old), Some(new)) if old.inner == new.inner)
        });
        let mut batch = BatchBuilder::new();
        batch.assert_value(
            epoch_key(),
            self.epoch
                .map(AssertValue::U64)
                .unwrap_or(AssertValue::None),
        );
        if no_op {
            server
                .registry()
                .store()
                .write(batch.build_all())
                .await
                .map_err(|err| {
                    if err.is_assertion_failure() {
                        error(409, None, RETRY_SNAPSHOT)
                    } else {
                        internal()
                    }
                })?;
            return Ok(id);
        }
        let mut invalidation = CacheInvalidationBuilder::default();
        for change in &changes {
            let key = ValueClass::Registry(RegistryClass::Item {
                object_id: ObjectType::Account.to_id(),
                item_id: change.id.id(),
            });
            batch.assert_value(
                key,
                change
                    .old
                    .as_ref()
                    .map(|old| AssertValue::Hash(old.revision))
                    .unwrap_or(AssertValue::None),
            );
            if let Some(new) = &change.new {
                let mut errors = Vec::new();
                new.validate(&mut errors);
                if !errors.is_empty() {
                    return Err(error(
                        400,
                        Some("invalidValue"),
                        "Native account validation failed",
                    ));
                }
                let mut index = IndexBuilder::default();
                new.index(&mut index);
                for key in &index.keys {
                    if let IndexKey::ForeignKey {
                        object_id,
                        type_filter,
                    } = key
                    {
                        if object_id.object() == ObjectType::Account
                            && let Some(target) =
                                changes.iter().find(|change| change.id == object_id.id())
                        {
                            let target = target.new.as_ref().ok_or_else(|| {
                                error(409, None, "Mutation references a deleted account")
                            })?;
                            if let ObjectInner::Account(target) = &target.inner {
                                let typ = match target {
                                    Account::User(_) => AccountType::User,
                                    Account::Group(_) => AccountType::Group,
                                };
                                if type_filter != &IndexValue::None
                                    && type_filter != &IndexValue::U16(typ.to_id())
                                {
                                    return Err(error(
                                        400,
                                        Some("invalidValue"),
                                        "Incorrect account reference type",
                                    ));
                                }
                            }
                            continue;
                        }
                        let foreign = server
                            .registry()
                            .get(*object_id)
                            .await
                            .map_err(|_| internal())?
                            .ok_or_else(|| {
                                error(
                                    400,
                                    Some("invalidValue"),
                                    "Native reference no longer exists",
                                )
                            })?;
                        if object_id.object().flags() & OBJ_FILTER_TENANT != 0
                            && foreign.inner.member_tenant_id() != new.inner.member_tenant_id()
                        {
                            return Err(error(
                                400,
                                Some("invalidValue"),
                                "Cross-tenant native reference",
                            ));
                        }
                        batch.assert_value(
                            ValueClass::Registry(RegistryClass::Item {
                                object_id: object_id.object().to_id(),
                                item_id: object_id.id().id(),
                            }),
                            AssertValue::Hash(foreign.revision),
                        );
                        if type_filter != &IndexValue::None {
                            batch.assert_value(
                                ValueClass::Registry(RegistryClass::Index {
                                    object_id: object_id.object().to_id(),
                                    item_id: object_id.id().id(),
                                    index_id: Property::Type.to_id(),
                                    key: type_filter.serialize(),
                                }),
                                AssertValue::Some,
                            );
                        }
                    } else if let IndexKey::Unique {
                        property,
                        value_1,
                        value_2,
                        global,
                    } = key
                    {
                        let mut key = value_1.serialize();
                        key.extend(value_2.serialize());
                        if let Some(existing) = server
                            .registry()
                            .primary_key((!*global).then_some(ObjectType::Account), *property, key)
                            .await
                            .map_err(|_| internal())?
                        {
                            if existing != ObjectId::new(ObjectType::Account, change.id) {
                                return Err(error(
                                    409,
                                    Some("uniqueness"),
                                    "Native account name or alias already exists",
                                ));
                            }
                        }
                    }
                }
            }
            append_change(&mut batch, change)?;
            match (&change.old, &change.new) {
                (Some(old), Some(new)) => invalidation.process_update(change.id, old, new),
                (None, Some(new)) => invalidation.process_create(new),
                (Some(old), None) => invalidation.process_delete(change.id, old),
                _ => (),
            }
        }
        if let Some(state) = state_change {
            if let Some(state) = state {
                batch.set(
                    state_key(id),
                    durable_value(&serde_json::to_vec(&state).map_err(|_| internal())?),
                );
            } else {
                batch.clear(state_key(id));
            }
        }
        if deleting {
            batch.clear(state_key(id));
            let (domain_id, _) = scope(&account);
            let (name, typ) = match &account {
                Account::User(a) => (&a.name, AccountType::User),
                Account::Group(a) => (&a.name, AccountType::Group),
            };
            batch.schedule_task(Task::DestroyAccount(TaskDestroyAccount {
                account_domain_id: domain_id,
                account_id: id,
                account_name: name.clone(),
                account_type: typ,
                status: TaskStatus::now(),
            }));
            revoke_owned_acl(server, id, &mut batch, &mut invalidation).await?;
        }
        server.registry().advance_independent_scim_epoch(&mut batch);
        server
            .registry()
            .store()
            .write(batch.build_all())
            .await
            .map_err(|err| {
                if err.is_assertion_failure() {
                    error(409, None, RETRY_SNAPSHOT)
                } else {
                    internal()
                }
            })?;
        server
            .invalidate_caches(invalidation)
            .await
            .map_err(|_| internal())?;
        if deleting {
            server.notify_task_queue();
        }
        Ok(id)
    }
}
struct Change {
    id: Id,
    old: Option<Object>,
    new: Option<Object>,
}
fn append_change(batch: &mut BatchBuilder, change: &Change) -> Result<(), Error> {
    let mut before = IndexBuilder::default();
    let mut after = IndexBuilder::default();
    if let Some(old) = &change.old {
        old.index(&mut before);
    }
    if let Some(new) = &change.new {
        new.index(&mut after);
    }
    let object_id = ObjectType::Account.to_id();
    let item_id = change.id.id();
    batch
        .registry_index(
            object_id,
            item_id,
            before.keys.iter().filter(|key| !after.keys.contains(*key)),
            false,
        )
        .registry_index(
            object_id,
            item_id,
            after.keys.iter().filter(|key| !before.keys.contains(*key)),
            true,
        );
    if let Some(new) = &change.new {
        let value = new.inner.to_pickled_vec();
        if value.len() > 200_000 {
            return Err(error(
                413,
                None,
                "Native account exceeds registry payload limit",
            ));
        }
        batch
            .set(
                ValueClass::Registry(RegistryClass::Item { object_id, item_id }),
                value,
            )
            .set(
                ValueClass::Registry(RegistryClass::IndexId { object_id, item_id }),
                Vec::<u8>::new(),
            );
    } else {
        batch
            .clear(ValueClass::Registry(RegistryClass::Item {
                object_id,
                item_id,
            }))
            .clear(ValueClass::Registry(RegistryClass::IndexId {
                object_id,
                item_id,
            }));
    }
    Ok(())
}
async fn revoke_owned_acl(
    server: &Server,
    id: Id,
    batch: &mut BatchBuilder,
    invalidation: &mut CacheInvalidationBuilder,
) -> Result<(), Error> {
    use store::{
        Deserialize, IterateParams, query::acl::AclItem, write::key::DeserializeBigEndian,
    };
    let from = ValueKey {
        account_id: 0,
        collection: 0,
        document_id: 0,
        class: ValueClass::Acl(0),
    };
    let to = ValueKey {
        account_id: u32::MAX,
        collection: u8::MAX,
        document_id: u32::MAX,
        class: ValueClass::Acl(u32::MAX),
    };
    let mut items = Vec::new();
    server
        .store()
        .iterate(IterateParams::new(from, to), |key, value| {
            let item = AclItem::deserialize(key)?;
            if item.to_account_id == id.document_id() {
                items.push((
                    key.deserialize_be_u32(0)?,
                    item,
                    <u64 as store::Deserialize>::deserialize(value)?,
                ));
            }
            Ok(true)
        })
        .await
        .map_err(|_| internal())?;
    for (grant, item, permissions) in items {
        batch
            .with_account_id(id.document_id())
            .with_collection(item.to_collection)
            .with_document(item.to_document_id)
            .assert_value(ValueClass::Acl(grant), AssertValue::U64(permissions))
            .acl_revoke(grant);
        invalidation.invalidate(CacheInvalidation::AccessToken(grant));
    }
    Ok(())
}
pub(super) fn parse_id(value: &str) -> Result<Id, Error> {
    value
        .parse::<Id>()
        .ok()
        .filter(|id| id.to_string() == value && id.is_valid())
        .ok_or_else(|| error(404, None, "Resource not found"))
}
#[cfg(test)]
mod tests {
    use super::*;
    use registry::schema::structs::CustomRoles;
    #[test]
    fn content_versions_ignore_unrelated_writes_but_cover_membership_views() {
        let domain = Id::from(4u32);
        let alice = Id::from(10u32);
        let bob = Id::from(11u32);
        let group = Id::from(12u32);
        let mut snapshot = Snapshot {
            domains: vec![RegistryObject {
                id: ObjectId::new(ObjectType::Domain, domain),
                revision: 1,
                object: Domain {
                    name: "example.test".into(),
                    allow_scim_provisioning: true,
                    ..Domain::default()
                },
            }],
            accounts: vec![
                RegistryObject {
                    id: ObjectId::new(ObjectType::Account, alice),
                    revision: 2,
                    object: Account::User(UserAccount {
                        name: "alice".into(),
                        domain_id: domain,
                        description: Some("Alice".into()),
                        member_group_ids: vec![group].into(),
                        ..UserAccount::default()
                    }),
                },
                RegistryObject {
                    id: ObjectId::new(ObjectType::Account, bob),
                    revision: 3,
                    object: Account::User(UserAccount {
                        name: "bob".into(),
                        domain_id: domain,
                        description: Some("Bob".into()),
                        ..UserAccount::default()
                    }),
                },
                RegistryObject {
                    id: ObjectId::new(ObjectType::Account, group),
                    revision: 4,
                    object: Account::Group(GroupAccount {
                        name: "staff".into(),
                        domain_id: domain,
                        description: Some("Staff".into()),
                        ..GroupAccount::default()
                    }),
                },
            ],
            epoch: Some(1),
            suspended: BTreeMap::new(),
            active: BTreeMap::from([(alice, true), (bob, true)]),
        };
        let before = snapshot.etag(&snapshot.accounts[0]);
        let group_before = snapshot.etag(&snapshot.accounts[2]);
        if let Account::User(bob) = &mut snapshot.accounts[1].object {
            bob.description = Some("Unrelated edit".into());
        }
        snapshot.epoch = Some(2);
        snapshot.accounts[1].revision = 99;
        assert_eq!(snapshot.etag(&snapshot.accounts[0]), before);
        assert_eq!(snapshot.etag(&snapshot.accounts[2]), group_before);
        assert!(
            snapshot
                .assert_match(&snapshot.accounts[0], Some(&before))
                .is_ok()
        );
        assert!(
            snapshot.render(&snapshot.accounts[0], "/scim")["meta"]
                .get("lastModified")
                .is_none()
        );
        if let Account::User(bob) = &mut snapshot.accounts[1].object {
            bob.member_group_ids = vec![group].into();
        }
        snapshot.epoch = Some(3);
        assert_ne!(snapshot.etag(&snapshot.accounts[2]), group_before);
        assert_eq!(snapshot.etag(&snapshot.accounts[0]), before);
        if let Account::Group(group) = &mut snapshot.accounts[2].object {
            group.description = Some("Renamed group".into());
        }
        assert_ne!(snapshot.etag(&snapshot.accounts[0]), before);
        assert_eq!(
            snapshot
                .assert_match(&snapshot.accounts[0], Some(&before))
                .err()
                .map(|err| err.status),
            Some(412)
        );
    }

    #[test]
    fn id_roundtrip() {
        let id = Id::from(42u32);
        assert_eq!(parse_id(&id.to_string()).ok(), Some(id));
        assert!(parse_id("../Users/42").is_err());
    }
    #[test]
    fn locale_uses_native_registry() {
        assert_eq!(enum_value::<Locale>("EN-us"), Some(Locale::EnUS));
        assert_eq!(
            enum_value::<Locale>("ca-ES@valencia").map(|v| v.as_str()),
            Some("ca-ES-valencia")
        );
        assert!(enum_value::<Locale>("made-UP").is_none());
        assert!(enum_value::<TimeZone>("not/a/zone").is_none());
        assert_eq!(
            enum_value::<TimeZone>("America/Los_Angeles").map(|value| value.as_str()),
            Some("America/Los_Angeles")
        );
    }
    #[test]
    fn effective_authentication_inherits_roles_and_denials() {
        let root = Id::from(9u32);
        let child = Id::from(3u32);
        let mut roles = BTreeMap::new();
        roles.insert(
            root,
            Role {
                enabled_permissions: vec![Permission::Authenticate].into(),
                role_ids: vec![child].into(),
                ..Role::default()
            },
        );
        roles.insert(
            child,
            Role {
                disabled_permissions: vec![Permission::Authenticate].into(),
                ..Role::default()
            },
        );
        let mut user = UserAccount::default();
        assert_eq!(
            effective_authenticate(&user, &[root], &roles).ok(),
            Some(false)
        );
        user.permissions = Permissions::Replace(PermissionsList {
            enabled_permissions: vec![Permission::Authenticate].into(),
            ..PermissionsList::default()
        });
        assert_eq!(
            effective_authenticate(&user, &[root], &roles).ok(),
            Some(true)
        );
    }

    #[test]
    fn group_display_rename_preserves_address_and_slug_is_bounded() {
        assert_eq!(group_slug(" Sales -- EMEA!! "), "sales-emea");
        assert_eq!(group_slug("!!!"), "group");
        let slug = group_slug(&"x".repeat(100));
        assert_eq!(slug.len(), 64);
        assert_eq!(suffixed_slug(&slug, 123).len(), 64);
        assert!(suffixed_slug(&slug, 123).ends_with("-123"));
        let mut group = GroupAccount {
            name: "sales-emea".into(),
            description: Some("Sales EMEA".into()),
            ..GroupAccount::default()
        };
        set_group_display_name(&mut group, "New Name", false);
        assert_eq!(group.name, "sales-emea");
        assert_eq!(group_display_name(&group), "New Name");
    }

    #[test]
    fn suspension_preserves_entitlements_while_inactive_and_restores_exactly() {
        let defaults = [Id::from(9u32), Id::from(3u32)];
        let roles = BTreeMap::from([
            (
                defaults[0],
                Role {
                    enabled_permissions: vec![
                        Permission::Authenticate,
                        Permission::SysAccountGet,
                        Permission::SysAccountDestroy,
                    ]
                    .into(),
                    ..Role::default()
                },
            ),
            (
                defaults[1],
                Role {
                    disabled_permissions: vec![Permission::SysAccountDestroy].into(),
                    ..Role::default()
                },
            ),
        ]);
        for permissions in [
            Permissions::Inherit,
            Permissions::Merge(PermissionsList::default()),
            Permissions::Replace(PermissionsList::default()),
            Permissions::Merge(PermissionsList {
                enabled_permissions: vec![Permission::SysAccountGet, Permission::Authenticate]
                    .into(),
                disabled_permissions: vec![Permission::SysAccountDestroy].into(),
            }),
        ] {
            let mut user = UserAccount {
                permissions,
                roles: UserRoles::Custom(CustomRoles {
                    role_ids: defaults.to_vec().into(),
                }),
                ..UserAccount::default()
            };
            let original = user.clone();
            let saved = SavedState {
                permissions: user.permissions.clone(),
            };
            let encoded = serde_json::to_vec(&saved).unwrap();
            suspend(&mut user);
            assert!(is_suspended(&user));
            assert_eq!(user.roles, original.roles);
            let suspended = user.clone();
            suspend(&mut user);
            assert_eq!(user, suspended, "repeated active=false must be a no-op");
            for permission in (0..Permission::COUNT)
                .filter_map(|id| Permission::from_id(id as u16))
                .filter(|p| *p != Permission::Authenticate)
            {
                assert_eq!(
                    effective_permission(&user, &defaults, &roles, permission).ok(),
                    effective_permission(&original, &defaults, &roles, permission).ok(),
                    "{}",
                    permission.as_str()
                );
            }
            assert_eq!(
                effective_authenticate(&user, &defaults, &roles).ok(),
                Some(false)
            );
            let decoded: SavedState = serde_json::from_slice(&encoded).unwrap();
            restore_active(&mut user, &decoded).unwrap();
            assert_eq!(user, original);
        }
    }

    #[test]
    fn reactivation_keeps_manual_roles_and_unrelated_permission_edits() {
        let mut user = UserAccount::default();
        let saved = SavedState {
            permissions: user.permissions.clone(),
        };
        suspend(&mut user);
        user.roles = UserRoles::Admin;
        let Permissions::Merge(list) = &mut user.permissions else {
            panic!("temporary merge wrapper")
        };
        list.enabled_permissions.push(Permission::SysAccountGet);
        list.disabled_permissions
            .push(Permission::SysAccountDestroy);
        restore_active(&mut user, &saved).unwrap();
        assert_eq!(user.roles, UserRoles::Admin);
        let Permissions::Merge(list) = &user.permissions else {
            panic!("manual edits must retain Merge")
        };
        assert!(
            list.enabled_permissions
                .contains(&Permission::SysAccountGet)
        );
        assert!(
            list.disabled_permissions
                .contains(&Permission::SysAccountDestroy)
        );
        assert!(
            !list
                .disabled_permissions
                .contains(&Permission::Authenticate)
        );
        suspend(&mut user);
        user.permissions = Permissions::Inherit;
        let before = user.clone();
        assert_eq!(
            restore_active(&mut user, &saved)
                .err()
                .map(|err| err.status),
            Some(409)
        );
        assert_eq!(user, before);
    }
}
