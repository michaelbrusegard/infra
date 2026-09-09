// SPDX-License-Identifier: AGPL-3.0-only
//! Independent in-process SCIM implementation for the sanitized OSS registry.
//!
//! Wiring: copy this directory to `crates/http/src/independent_scim`, declare
//! `#[cfg(feature = "independent-scim")] pub mod independent_scim;` in http's lib.rs,
//! then call `independent_scim::handle(self, req, &session).await` for /scim and
//! descendants AFTER the existing endpoint-policy check, BEFORE other routing.
//! No management API credentials, external adapter, extra database, or SEL imports.
//!
//! Authentication contract: anonymous GET discovery only; all other endpoints accept
//! Bearer credentials through the existing HTTP authenticator (Basic is rejected).
//! Authenticate + ScimAccess + the corresponding SysAccount{Get,Create,Update,Destroy}
//! permission must be present on the resulting credential-scoped token. Tenant/domain
//! scoping is additionally enforced by storage. API key issuance remains native.
//!
//! Account/membership mutations and suspension state commit in a native store batch.
//! The parent registry epoch hook is required to guard membership predicates against
//! concurrent non-SCIM writers. Capability parity still requires end-to-end testing.

pub mod protocol;
mod storage;

use crate::auth::authenticate::{Authenticator, HttpHeaders};
use common::{Server, auth::AccessToken};
use http_body_util::BodyExt;
use http_proto::{HttpRequest, HttpResponse, HttpSessionData, form_urlencoded};
use hyper::{Method, StatusCode, header};
use protocol::Error;
use registry::schema::enums::Permission;
use serde_json::{Value, json};
use std::collections::BTreeMap;
use storage::{Snapshot, authorize, error, parse_id};

const MAX_BODY: usize = 1024 * 1024;
const MAX_PAGE: usize = 200;

#[derive(Default)]
struct ResponseMetadata {
    etag: Option<String>,
    location: Option<String>,
}
fn project_resource(
    resource: &Value,
    attributes: Option<&str>,
    excluded: Option<&str>,
    metadata: &mut ResponseMetadata,
) -> Result<Value, Error> {
    metadata.etag = resource
        .pointer("/meta/version")
        .and_then(Value::as_str)
        .map(str::to_owned);
    metadata.location = resource
        .pointer("/meta/location")
        .and_then(Value::as_str)
        .map(str::to_owned);
    protocol::project(resource, attributes, excluded)
}

fn project_read(
    resource: &Value,
    attributes: Option<&str>,
    excluded: Option<&str>,
) -> Result<Value, Error> {
    if resource
        .get("members")
        .and_then(Value::as_array)
        .is_some_and(|members| members.len() > MAX_PAGE)
    {
        let requested = attributes
            .map(|attributes| {
                attributes.split(',').any(|name| {
                    name.trim().eq_ignore_ascii_case("members")
                        || name.trim().to_ascii_lowercase().starts_with("members.")
                })
            })
            .unwrap_or_else(|| {
                !excluded.is_some_and(|excluded| {
                    excluded
                        .split(',')
                        .any(|name| name.trim().eq_ignore_ascii_case("members"))
                })
            });
        let mut without_members = resource.clone();
        without_members
            .as_object_mut()
            .expect("SCIM resource")
            .remove("members");
        let projected = protocol::project(&without_members, attributes, excluded)?;
        if requested {
            return Err(error(
                400,
                Some("tooMany"),
                "Group has more than 200 members; exclude members and query User.groups",
            ));
        }
        Ok(projected)
    } else {
        protocol::project(resource, attributes, excluded)
    }
}

/// Consume one native HTTP request. The host router has already checked endpoint policy.
/// Returned errors are SCIM documents; credentials and request bodies are never logged here.
pub async fn handle(
    server: &Server,
    mut req: HttpRequest,
    session: &HttpSessionData,
) -> HttpResponse {
    // Use the configured public origin, never an untrusted Host/forwarded header.
    let decoded_path = match percent_encoding::percent_decode_str(req.uri().path()).decode_utf8() {
        Ok(path) => path.into_owned(),
        Err(_) => return failure(error(400, Some("invalidPath"), "Invalid UTF-8 path")),
    };
    let (base, path) = match route(&decoded_path) {
        Some(route) => (route.0.to_owned(), route.1.to_owned()),
        None => return failure(error(404, None, "SCIM endpoint not found")),
    };
    let base = server
        .registry()
        .public_url()
        .map(|url| format!("{}{base}", url.trim_end_matches('/')))
        .unwrap_or(base);
    if req.method() == Method::OPTIONS {
        return HttpResponse::new(StatusCode::NO_CONTENT)
            .with_header(header::ALLOW, allowed_methods(&path))
            .with_no_store();
    }
    let params = match parameters(req.uri().query().unwrap_or_default()) {
        Ok(params) => params,
        Err(err) => return failure(err),
    };
    let mut discovery = None;
    if req.method() == Method::GET {
        if let Some(mut document) = protocol::discovery(&path, &base) {
            if params.contains_key("filter") {
                return failure(error(403, None, "Discovery filtering is forbidden"));
            }
            if path == "ServiceProviderConfig" {
                document["bulk"] =
                    json!({"supported":true,"maxOperations":1000,"maxPayloadSize":MAX_BODY});
                document["sort"] = json!({"supported":true});
                document["etag"] = json!({"supported":true});
            }
            if !req.headers().contains_key(header::AUTHORIZATION) {
                return response(StatusCode::OK, document);
            }
            discovery = Some(document);
        }
    }
    if req.method() == Method::GET
        && discovery.is_none()
        && matches!(
            path.split('/').next(),
            Some("Schemas" | "ResourceTypes" | "ServiceProviderConfig")
        )
    {
        return failure(if params.contains_key("filter") {
            error(403, None, "Discovery filtering is forbidden")
        } else {
            error(404, None, "Discovery resource not found")
        });
    }
    // Check the scheme before calling the shared authenticator; it normally accepts Basic.
    if !req
        .authorization()
        .is_some_and(|(scheme, _)| scheme.eq_ignore_ascii_case("bearer"))
    {
        return failure(error(401, None, "A native Bearer API key is required"))
            .with_header(header::WWW_AUTHENTICATE, "Bearer");
    }
    let (_in_flight, token) = match server.authenticate_headers(&req, session).await {
        Ok(auth) => auth,
        Err(err) => return authentication_failure(&err),
    };
    let permission = match *req.method() {
        Method::GET => Permission::SysAccountGet,
        Method::POST if path == ".search" || path.ends_with("/.search") => {
            Permission::SysAccountGet
        }
        Method::POST if path == "Bulk" => Permission::ScimAccess,
        Method::POST => Permission::SysAccountCreate,
        Method::PUT | Method::PATCH => Permission::SysAccountUpdate,
        Method::DELETE => Permission::SysAccountDestroy,
        _ => return failure_at(error(405, None, "Method not allowed"), &path),
    };
    if let Err(err) = authorize(&token, permission) {
        return failure(err);
    }
    if let Some(document) = discovery {
        return response(StatusCode::OK, document);
    }
    if protocol::discovery(&path, &base).is_some() {
        return failure_at(error(405, None, "Discovery is read-only"), &path);
    }
    if path == "Me" || path.starts_with("Me/") {
        return failure(error(501, None, "The Me endpoint is not implemented"));
    }
    let method = req.method().clone();
    let none_match = match request_header(&req, header::IF_NONE_MATCH) {
        Ok(value) => value,
        Err(err) => return failure(err),
    };
    let mut metadata = ResponseMetadata::default();
    match dispatch(
        server,
        &mut req,
        &token,
        &base,
        &path,
        params,
        &mut metadata,
    )
    .await
    {
        Ok(document) => {
            if method == Method::DELETE {
                return HttpResponse::new(StatusCode::NO_CONTENT).with_no_store();
            }
            let etag = metadata.etag;
            if method == Method::GET
                && none_match.as_deref().is_some_and(|header| {
                    etag.as_deref()
                        .is_some_and(|etag| etag_matches(header, etag, true))
                })
            {
                return HttpResponse::new(StatusCode::NOT_MODIFIED)
                    .with_etag_opt(etag)
                    .with_no_store();
            }
            let created = method == Method::POST && matches!(path.as_str(), "Users" | "Groups");
            let location = metadata.location;
            let mut result = response(
                if created {
                    StatusCode::CREATED
                } else {
                    StatusCode::OK
                },
                document,
            )
            .with_etag_opt(etag);
            if created && let Some(location) = location {
                result = result.with_location(location);
            }
            result
        }
        Err(err) => failure_at(err, &path),
    }
}

fn allowed_methods(path: &str) -> &'static str {
    if path == "Bulk" || path == ".search" || path.ends_with("/.search") {
        "POST, OPTIONS"
    } else if matches!(path, "Users" | "Groups") {
        "GET, POST, OPTIONS"
    } else if path.starts_with("Users/") || path.starts_with("Groups/") {
        "GET, PUT, PATCH, DELETE, OPTIONS"
    } else {
        "GET, OPTIONS"
    }
}
fn failure_at(err: Error, path: &str) -> HttpResponse {
    let method_not_allowed = err.status == 405;
    let response = failure(err);
    if method_not_allowed {
        response.with_header(header::ALLOW, allowed_methods(path))
    } else {
        response
    }
}

async fn dispatch(
    server: &Server,
    req: &mut HttpRequest,
    token: &AccessToken,
    base: &str,
    path: &str,
    mut params: BTreeMap<String, String>,
    metadata: &mut ResponseMetadata,
) -> Result<Value, Error> {
    if path == "Bulk" {
        if req.method() != Method::POST {
            return Err(error(405, None, "Bulk requires POST"));
        }
        return bulk(server, token, base, &body(req).await?).await;
    }
    let parts = path.split('/').collect::<Vec<_>>();
    let collection = match parts.first().copied().unwrap_or_default() {
        "Users" => Some("Users"),
        "Groups" => Some("Groups"),
        "" | ".search" => None,
        _ => return Err(error(404, None, "SCIM endpoint not found")),
    };
    let search = path == ".search" || (parts.len() == 2 && parts[1] == ".search");
    if parts.len() > 2 {
        return Err(error(404, None, "SCIM endpoint not found"));
    }
    if search {
        if req.method() != Method::POST {
            return Err(error(405, None, "Search requires POST"));
        }
        let document = body(req).await?;
        let object = document
            .as_object()
            .ok_or_else(|| error(400, Some("invalidSyntax"), "Search body must be an object"))?;
        if document.get("schemas")
            != Some(&json!([
                "urn:ietf:params:scim:api:messages:2.0:SearchRequest"
            ]))
        {
            return Err(error(
                400,
                Some("invalidValue"),
                "Expected the SearchRequest schema",
            ));
        }
        for (key, value) in object {
            if key == "schemas" {
                continue;
            }
            let value = match value {
                Value::String(s) => s.clone(),
                Value::Number(n) if key == "startIndex" || key == "count" => n.to_string(),
                Value::Array(a) if key == "attributes" || key == "excludedAttributes" => a
                    .iter()
                    .map(|v| {
                        v.as_str().ok_or_else(|| {
                            error(400, Some("invalidValue"), "Attributes must be strings")
                        })
                    })
                    .collect::<Result<Vec<_>, _>>()?
                    .join(","),
                _ => return Err(error(400, Some("invalidValue"), "Invalid search parameter")),
            };
            if params.insert(key.clone(), value).is_some() {
                return Err(error(
                    400,
                    Some("invalidValue"),
                    "Duplicate search parameter",
                ));
            }
        }
    }
    for key in params.keys() {
        if !matches!(
            key.as_str(),
            "filter"
                | "startIndex"
                | "count"
                | "attributes"
                | "excludedAttributes"
                | "sortBy"
                | "sortOrder"
                | "cursor"
        ) {
            return Err(error(400, Some("invalidValue"), "Unknown query parameter"));
        }
    }
    let attributes = params.get("attributes").map(String::as_str);
    let excluded = params.get("excludedAttributes").map(String::as_str);
    let id = if parts.len() == 2 && !search {
        Some(parse_id(parts[1])?)
    } else {
        None
    };
    // The dispatcher checked the operation grant; internal mutation reads need no Get grant.
    let snapshot = Snapshot::load(server, token).await?;
    let if_match = request_header(req, header::IF_MATCH)?;
    let if_none_match = request_header(req, header::IF_NONE_MATCH)?;
    if req.method() == Method::POST && !search {
        if id.is_some() {
            return Err(error(405, None, "POST requires a collection"));
        }
        let kind = collection.ok_or_else(|| error(405, None, "POST requires Users or Groups"))?;
        let input = body(req).await?;
        let normalized = if kind == "Users" {
            protocol::normalize_user(&input)?
        } else {
            protocol::normalize_group(&input)?
        };
        let id = snapshot
            .mutate(
                server,
                token,
                kind,
                None,
                Some(&normalized),
                if_match.as_deref(),
            )
            .await?;
        let snapshot = Snapshot::load(server, token).await?;
        let account = snapshot
            .account(id, kind)
            .ok_or_else(|| error(409, None, "Created account changed concurrently"))?;
        return project_resource(
            &snapshot.render(account, base),
            attributes,
            excluded,
            metadata,
        );
    }
    if let Some(id) = id {
        let kind = collection.ok_or_else(|| error(404, None, "Resource not found"))?;
        let account = snapshot
            .account(id, kind)
            .ok_or_else(|| error(404, None, "Resource not found"))?;
        snapshot.assert_match(account, if_match.as_deref())?;
        if req.method() != Method::GET
            && if_none_match
                .as_deref()
                .is_some_and(|header| etag_matches(header, &snapshot.etag(account), true))
        {
            return Err(error(412, None, "Resource matches If-None-Match"));
        }
        let current = snapshot.render(account, base);
        metadata.etag = Some(snapshot.etag(account));
        metadata.location = current
            .pointer("/meta/location")
            .and_then(Value::as_str)
            .map(str::to_owned);
        match *req.method() {
            Method::GET => project_read(&current, attributes, excluded),
            Method::DELETE => {
                snapshot
                    .mutate(server, token, kind, Some(id), None, if_match.as_deref())
                    .await?;
                Ok(Value::Null)
            }
            Method::PUT | Method::PATCH => {
                let input = body(req).await?;
                if id.id() == u64::from(token.account_id())
                    && input.get("active") == Some(&Value::Bool(false))
                {
                    return Err(error(
                        403,
                        None,
                        "A provisioning principal cannot deactivate itself",
                    ));
                }
                let changed = if req.method() == Method::PATCH {
                    protocol::apply_patch(&current, &input)?
                } else {
                    input
                };
                if id.id() == u64::from(token.account_id())
                    && changed.get("active") == Some(&Value::Bool(false))
                {
                    return Err(error(
                        403,
                        None,
                        "A provisioning principal cannot deactivate itself",
                    ));
                }
                let normalized = if kind == "Users" {
                    protocol::normalize_user(&changed)?
                } else {
                    protocol::normalize_group(&changed)?
                };
                if id.id() == u64::from(token.account_id())
                    && normalized.get("active") == Some(&Value::Bool(false))
                {
                    return Err(error(
                        403,
                        None,
                        "A provisioning principal cannot deactivate itself",
                    ));
                }
                snapshot
                    .mutate(
                        server,
                        token,
                        kind,
                        Some(id),
                        Some(&normalized),
                        if_match.as_deref(),
                    )
                    .await?;
                let refreshed = Snapshot::load(server, token).await?;
                let account = refreshed
                    .account(id, kind)
                    .ok_or_else(|| error(404, None, "Resource no longer exists"))?;
                project_resource(
                    &refreshed.render(account, base),
                    attributes,
                    excluded,
                    metadata,
                )
            }
            _ => Err(error(405, None, "Method not allowed")),
        }
    } else {
        if req.method() != Method::GET && !search {
            return Err(error(405, None, "Method not allowed"));
        }
        let filter = params
            .get("filter")
            .map(|f| protocol::Filter::parse_public(f))
            .transpose()?;
        if let (Some(filter), Some(kind)) = (&filter, collection) {
            filter.validate_resource_type(kind)?;
        }
        let terms = filter
            .as_ref()
            .and_then(|filter| filter.equality_terms())
            .unwrap_or_default();
        let indexed = snapshot.indexed_candidates(server, token, &terms).await?;
        let nonindexed = terms
            .iter()
            .any(|(name, _)| matches!(name.as_str(), "displayname" | "name.formatted" | "active"));
        let candidate_filters = terms
            .iter()
            .filter(|(name, _)| {
                !matches!(name.as_str(), "displayname" | "name.formatted" | "active")
            })
            .map(|(name, value)| protocol::Filter::parse_public(&format!("{name} eq {value}")))
            .collect::<Result<Vec<_>, _>>()?;
        let mut start = unsigned_parameter(&params, "startIndex", 1)?.max(1);
        let count = unsigned_parameter(&params, "count", 100)?.min(MAX_PAGE);
        let sort_by = params
            .get("sortBy")
            .map(|s| s.to_ascii_lowercase())
            .unwrap_or_else(|| "id".into());
        if !matches!(sort_by.as_str(), "id" | "username")
            || (sort_by == "username" && collection == Some("Groups"))
        {
            return Err(error(
                400,
                Some("invalidValue"),
                "Supported sort keys are id and userName (Users only)",
            ));
        }
        let order = params
            .get("sortOrder")
            .map(|s| s.to_ascii_lowercase())
            .unwrap_or_else(|| "ascending".into());
        if !matches!(order.as_str(), "ascending" | "descending") {
            return Err(error(400, Some("invalidValue"), "Invalid sortOrder"));
        }
        let cursor_context = cursor_context(snapshot.epoch, token.account_id(), path, &params);
        if let Some(cursor) = params.get("cursor").filter(|cursor| !cursor.is_empty()) {
            if params.contains_key("startIndex") {
                return Err(error(
                    400,
                    Some("invalidValue"),
                    "cursor and startIndex cannot be combined",
                ));
            }
            start = cursor_offset(cursor, &cursor_context)?
                .checked_add(1)
                .ok_or_else(|| error(400, Some("invalidCursor"), "Cursor offset overflow"))?;
        }
        let mut resources = snapshot
            .accounts
            .iter()
            .filter(|account| {
                indexed
                    .as_ref()
                    .is_none_or(|ids| ids.contains(&account.id.id()))
            })
            .filter(|a| collection.is_none_or(|kind| snapshot.account(a.id.id(), kind).is_some()))
            .map(|a| snapshot.render(a, base))
            .filter(|resource| {
                candidate_filters
                    .iter()
                    .all(|filter| filter.matches(resource))
            })
            .collect::<Vec<_>>();
        if nonindexed && resources.len() > MAX_PAGE {
            return Err(error(
                400,
                Some("tooMany"),
                "Nonindexed filters require at most 200 candidates; narrow the filter",
            ));
        }
        resources.retain(|resource| {
            filter
                .as_ref()
                .is_none_or(|filter| filter.matches(resource))
        });
        resources.sort_by(|a, b| {
            let comparison = if sort_by == "username" {
                match (a["userName"].as_str(), b["userName"].as_str()) {
                    (Some(a), Some(b)) => a.to_lowercase().cmp(&b.to_lowercase()),
                    (Some(_), None) => std::cmp::Ordering::Less,
                    (None, Some(_)) => std::cmp::Ordering::Greater,
                    (None, None) => std::cmp::Ordering::Equal,
                }
            } else {
                a["id"].as_str().cmp(&b["id"].as_str())
            };
            let comparison = comparison.then_with(|| a["id"].as_str().cmp(&b["id"].as_str()));
            if order == "descending" {
                comparison.reverse()
            } else {
                comparison
            }
        });
        let total = resources.len();
        let resources = resources
            .into_iter()
            .skip(start.saturating_sub(1))
            .take(count)
            .map(|resource| project_read(&resource, attributes, excluded))
            .collect::<Result<Vec<_>, _>>()?;
        let end = start.saturating_sub(1).saturating_add(resources.len());
        let mut response = json!({"schemas": ["urn:ietf:params:scim:api:messages:2.0:ListResponse"],
            "totalResults": total, "startIndex": start, "itemsPerPage": resources.len(), "Resources": resources});
        if count > 0 && end < total {
            response["nextCursor"] = json!(format!("{cursor_context}.{end}"));
        }
        if count > 0 && start > 1 {
            response["previousCursor"] = json!(format!(
                "{cursor_context}.{}",
                start.saturating_sub(1).saturating_sub(count)
            ));
        }
        Ok(response)
    }
}

/// Bulk is a sequence of independently atomic native operations, as specified by
/// SCIM; it is not a transaction across the entire request. No internal HTTP/JMAP calls.
async fn bulk(
    server: &Server,
    token: &AccessToken,
    base: &str,
    request: &Value,
) -> Result<Value, Error> {
    if request.get("schemas")
        != Some(&json!([
            "urn:ietf:params:scim:api:messages:2.0:BulkRequest"
        ]))
    {
        return Err(error(
            400,
            Some("invalidValue"),
            "Expected BulkRequest schema",
        ));
    }
    let operations = request["Operations"]
        .as_array()
        .ok_or_else(|| error(400, Some("invalidSyntax"), "Operations must be an array"))?;
    if operations.len() > 1000 {
        return Err(error(
            413,
            None,
            "Bulk requests are limited to 1000 operations",
        ));
    }
    let fail_after = match request.get("failOnErrors") {
        None => None,
        Some(value) => Some(value.as_u64().ok_or_else(|| {
            error(
                400,
                Some("invalidValue"),
                "failOnErrors must be a nonnegative integer",
            )
        })?),
    }
    .filter(|limit| *limit != 0);
    let mut declared = std::collections::BTreeSet::new();
    for operation in operations {
        if !operation.is_object() {
            return Err(error(
                400,
                Some("invalidSyntax"),
                "Bulk operation must be an object",
            ));
        }
        if let Some(id) = operation.get("bulkId") {
            let id = id.as_str().filter(|id| !id.is_empty()).ok_or_else(|| {
                error(
                    400,
                    Some("invalidValue"),
                    "bulkId must be a nonempty string",
                )
            })?;
            if !declared.insert(id.to_owned()) {
                return Err(error(400, Some("invalidValue"), "Duplicate bulkId"));
            }
        }
    }
    let mut resolved: BTreeMap<String, Option<String>> = BTreeMap::new();
    let mut pending = (0..operations.len()).collect::<Vec<_>>();
    let mut results = vec![None; operations.len()];
    let mut errors = 0u64;
    while !pending.is_empty() && fail_after.is_none_or(|limit| errors < limit) {
        let mut deferred = Vec::new();
        let mut progressed = false;
        for index in pending {
            if fail_after.is_some_and(|limit| errors >= limit) {
                break;
            }
            let operation = &operations[index];
            let mut operation = operation.clone();
            let dependencies = bulk_dependencies(&operation);
            if dependencies
                .iter()
                .any(|id| declared.contains(id) && !resolved.contains_key(id))
            {
                deferred.push(index);
                continue;
            }
            let result = if dependencies
                .iter()
                .any(|id| resolved.get(id).is_none_or(Option::is_none))
            {
                Err(error(
                    400,
                    Some("invalidValue"),
                    "Unresolved or failed bulkId dependency",
                ))
            } else {
                substitute_bulk_ids(&mut operation, &resolved);
                bulk_operation(server, token, base, &operation).await
            };
            progressed = true;
            let mut item = json!({"method":operations[index]["method"]});
            let bulk_id = operations[index].get("bulkId").and_then(Value::as_str);
            if let Some(id) = bulk_id {
                item["bulkId"] = json!(id);
            }
            match result {
                Ok((status, id, resource)) => {
                    item["status"] = json!(status.to_string());
                    item["location"] = json!(format!(
                        "{base}/{}/{}",
                        operation["path"]
                            .as_str()
                            .unwrap_or_default()
                            .trim_start_matches('/')
                            .split('/')
                            .next()
                            .unwrap_or_default(),
                        id
                    ));
                    if let Some(version) = resource.pointer("/meta/version") {
                        item["version"] = version.clone();
                    }
                    if let Some(bulk_id) = bulk_id {
                        resolved.insert(bulk_id.to_owned(), Some(id));
                    }
                }
                Err(err) => {
                    errors += 1;
                    item["status"] = json!(err.status.to_string());
                    item["response"] = error_document(&err);
                    if let Some(bulk_id) = bulk_id {
                        resolved.insert(bulk_id.to_owned(), None);
                    }
                }
            }
            results[index] = Some(item);
        }
        if !progressed && !deferred.is_empty() {
            for index in deferred {
                if fail_after.is_some_and(|limit| errors >= limit) {
                    break;
                }
                let err = error(
                    400,
                    Some("invalidValue"),
                    "Cyclic or unresolved bulkId dependency",
                );
                let mut item = json!({"method":operations[index]["method"],"status":"400","response":error_document(&err)});
                if let Some(id) = operations[index].get("bulkId") {
                    item["bulkId"] = id.clone();
                }
                results[index] = Some(item);
                errors += 1;
            }
            break;
        }
        pending = deferred;
    }
    Ok(
        json!({"schemas":["urn:ietf:params:scim:api:messages:2.0:BulkResponse"],"Operations":results.into_iter().flatten().collect::<Vec<_>>()}),
    )
}
fn bulk_dependencies(operation: &Value) -> Vec<String> {
    let mut result = Vec::new();
    if let Some(path) = operation["path"].as_str() {
        for part in path.split('/') {
            if let Some(id) = part.strip_prefix("bulkId:") {
                result.push(id.to_owned());
            }
        }
    }
    for member in operation
        .pointer("/data/members")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        if let Some(id) = member["value"]
            .as_str()
            .and_then(|value| value.strip_prefix("bulkId:"))
        {
            result.push(id.to_owned());
        }
    }
    result
}
fn substitute_bulk_ids(operation: &mut Value, resolved: &BTreeMap<String, Option<String>>) {
    if let Some(path) = operation["path"].as_str() {
        let path = path
            .split('/')
            .map(|part| {
                part.strip_prefix("bulkId:")
                    .and_then(|id| resolved.get(id))
                    .and_then(Option::as_deref)
                    .unwrap_or(part)
            })
            .collect::<Vec<_>>()
            .join("/");
        operation["path"] = json!(path);
    }
    if let Some(members) = operation
        .pointer_mut("/data/members")
        .and_then(Value::as_array_mut)
    {
        for member in members {
            if let Some(id) = member["value"]
                .as_str()
                .and_then(|value| value.strip_prefix("bulkId:"))
                .and_then(|id| resolved.get(id))
                .and_then(Option::as_ref)
                .cloned()
            {
                member["value"] = json!(id);
            }
        }
    }
}
async fn bulk_operation(
    server: &Server,
    token: &AccessToken,
    base: &str,
    operation: &Value,
) -> Result<(u16, String, Value), Error> {
    let method = operation["method"]
        .as_str()
        .ok_or_else(|| error(400, Some("invalidValue"), "Bulk method required"))?;
    let path = operation["path"]
        .as_str()
        .filter(|path| path.starts_with('/'))
        .ok_or_else(|| {
            error(
                400,
                Some("invalidPath"),
                "Bulk path must be relative to the SCIM root",
            )
        })?;
    let parts = path.trim_start_matches('/').split('/').collect::<Vec<_>>();
    let kind = parts[0];
    if !matches!(kind, "Users" | "Groups") || parts.len() > 2 {
        return Err(error(
            400,
            Some("invalidPath"),
            "Invalid Bulk resource path",
        ));
    }
    let id = if parts.len() == 2 {
        Some(parse_id(parts[1])?)
    } else {
        None
    };
    if (method == "POST") != id.is_none() {
        return Err(error(
            400,
            Some("invalidPath"),
            "Bulk method and resource path do not match",
        ));
    }
    if method == "POST" && operation.get("bulkId").and_then(Value::as_str).is_none() {
        return Err(error(400, Some("invalidValue"), "POST requires bulkId"));
    }
    authorize(
        token,
        match method {
            "POST" => Permission::SysAccountCreate,
            "PUT" | "PATCH" => Permission::SysAccountUpdate,
            "DELETE" => Permission::SysAccountDestroy,
            _ => return Err(error(405, None, "Invalid Bulk method")),
        },
    )?;
    let snapshot = Snapshot::load(server, token).await?;
    let version = operation
        .get("version")
        .map(|v| {
            v.as_str()
                .ok_or_else(|| error(400, Some("invalidValue"), "version must be a string"))
        })
        .transpose()?;
    let normalized = if method == "DELETE" {
        None
    } else {
        let mut document = operation["data"].clone();
        if method == "PATCH" {
            let account = snapshot
                .account(id.expect("update path"), kind)
                .ok_or_else(|| error(404, None, "Resource not found"))?;
            document = protocol::apply_patch(&snapshot.render(account, base), &document)?;
        }
        Some(if kind == "Users" {
            protocol::normalize_user(&document)?
        } else {
            protocol::normalize_group(&document)?
        })
    };
    let id = snapshot
        .mutate(server, token, kind, id, normalized.as_ref(), version)
        .await?;
    if method == "DELETE" {
        return Ok((204, id.to_string(), Value::Null));
    }
    let snapshot = Snapshot::load(server, token).await?;
    let account = snapshot
        .account(id, kind)
        .ok_or_else(|| error(409, None, "Account changed concurrently"))?;
    Ok((
        if method == "POST" { 201 } else { 200 },
        id.to_string(),
        snapshot.render(account, base),
    ))
}

// Cursors carry no authorization. They bind an offset to the principal, registry
// snapshot and query; every resumed request reauthenticates and reapplies domain scope.
fn cursor_context(
    epoch: Option<u64>,
    principal: u32,
    path: &str,
    params: &BTreeMap<String, String>,
) -> String {
    use std::hash::{Hash, Hasher};
    let mut hash = std::collections::hash_map::DefaultHasher::new();
    path.trim_end_matches("/.search")
        .trim_end_matches(".search")
        .hash(&mut hash);
    for (key, value) in params {
        if !matches!(
            key.as_str(),
            "cursor" | "startIndex" | "count" | "attributes" | "excludedAttributes"
        ) {
            key.hash(&mut hash);
            value.hash(&mut hash);
        }
    }
    format!(
        "v1.{}.{principal:x}.{:016x}",
        epoch
            .map(|value| format!("{value:016x}"))
            .unwrap_or_else(|| "initial".into()),
        hash.finish()
    )
}
fn cursor_offset(cursor: &str, context: &str) -> Result<usize, Error> {
    cursor
        .strip_prefix(context)
        .and_then(|value| value.strip_prefix('.'))
        .and_then(|value| value.parse().ok())
        .ok_or_else(|| {
            error(
                400,
                Some("invalidCursor"),
                "Cursor does not match this principal, query, or current registry snapshot",
            )
        })
}

fn request_header(req: &HttpRequest, name: header::HeaderName) -> Result<Option<String>, Error> {
    let values = req
        .headers()
        .get_all(name)
        .iter()
        .map(|value| {
            value
                .to_str()
                .map(str::to_owned)
                .map_err(|_| error(400, Some("invalidSyntax"), "Invalid conditional header"))
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok((!values.is_empty()).then(|| values.join(",")))
}
fn etag_matches(header: &str, etag: &str, weak: bool) -> bool {
    header.split(',').any(|value| {
        let value = value.trim();
        value == "*"
            || (if weak {
                value.strip_prefix("W/").unwrap_or(value)
            } else {
                value
            }) == etag
    })
}

fn route(path: &str) -> Option<(&str, &str)> {
    let path = path.strip_suffix('/').unwrap_or(path);
    for base in ["/scim/v2", "/scim"] {
        if path == base {
            return Some((base, ""));
        }
        if let Some(rest) = path.strip_prefix(base).and_then(|p| p.strip_prefix('/')) {
            return Some((base, rest));
        }
    }
    None
}

fn parameters(query: &str) -> Result<BTreeMap<String, String>, Error> {
    let mut params = BTreeMap::new();
    for (key, value) in form_urlencoded::parse(query.as_bytes()) {
        if params
            .insert(key.into_owned(), value.into_owned())
            .is_some()
        {
            return Err(error(
                400,
                Some("invalidValue"),
                "Duplicate query parameter",
            ));
        }
    }
    Ok(params)
}

fn unsigned_parameter(
    params: &BTreeMap<String, String>,
    key: &str,
    default: usize,
) -> Result<usize, Error> {
    params.get(key).map_or(Ok(default), |value| {
        value.parse().map_err(|_| {
            error(
                400,
                Some("invalidValue"),
                format!("{key} must be a nonnegative integer"),
            )
        })
    })
}

async fn body(req: &mut HttpRequest) -> Result<Value, Error> {
    let content_type = req
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.split(';').next())
        .unwrap_or_default()
        .trim();
    if !content_type.eq_ignore_ascii_case("application/scim+json")
        && !content_type.eq_ignore_ascii_case("application/json")
    {
        return Err(error(415, None, "Expected application/scim+json"));
    }
    if req.headers().contains_key(header::CONTENT_ENCODING) {
        return Err(error(415, None, "Encoded request bodies are unsupported"));
    }
    let mut bytes = Vec::new();
    while let Some(frame) = req.frame().await {
        let frame =
            frame.map_err(|_| error(400, Some("invalidSyntax"), "Failed to read request body"))?;
        if let Some(data) = frame.data_ref() {
            if bytes.len().saturating_add(data.len()) > MAX_BODY {
                return Err(error(413, None, "SCIM request exceeds 1 MiB"));
            }
            bytes.extend_from_slice(data);
        }
    }
    serde_json::from_slice::<StrictJson>(&bytes)
        .map(|document| document.0)
        .map_err(|_| {
            error(
                400,
                Some("invalidSyntax"),
                "Invalid JSON or duplicate attribute",
            )
        })
}

// Reject duplicate keys while decoding, before serde_json::Value can erase them.
// SCIM attribute names are case-insensitive, including nested object attributes.
struct StrictJson(Value);

impl<'de> serde::Deserialize<'de> for StrictJson {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct Visitor;
        impl<'de> serde::de::Visitor<'de> for Visitor {
            type Value = StrictJson;
            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("JSON without duplicate attributes")
            }
            fn visit_map<A: serde::de::MapAccess<'de>>(
                self,
                mut map: A,
            ) -> Result<StrictJson, A::Error> {
                let mut result = serde_json::Map::new();
                let mut seen = std::collections::BTreeSet::new();
                while let Some(key) = map.next_key::<String>()? {
                    if !seen.insert(key.to_ascii_lowercase()) {
                        return Err(serde::de::Error::custom("duplicate SCIM attribute"));
                    }
                    result.insert(key, map.next_value::<StrictJson>()?.0);
                }
                Ok(StrictJson(Value::Object(result)))
            }
            fn visit_seq<A: serde::de::SeqAccess<'de>>(
                self,
                mut seq: A,
            ) -> Result<StrictJson, A::Error> {
                let mut result = Vec::new();
                while let Some(value) = seq.next_element::<StrictJson>()? {
                    result.push(value.0);
                }
                Ok(StrictJson(Value::Array(result)))
            }
            fn visit_bool<E: serde::de::Error>(self, value: bool) -> Result<StrictJson, E> {
                Ok(StrictJson(json!(value)))
            }
            fn visit_i64<E: serde::de::Error>(self, value: i64) -> Result<StrictJson, E> {
                Ok(StrictJson(json!(value)))
            }
            fn visit_u64<E: serde::de::Error>(self, value: u64) -> Result<StrictJson, E> {
                Ok(StrictJson(json!(value)))
            }
            fn visit_f64<E: serde::de::Error>(self, value: f64) -> Result<StrictJson, E> {
                serde_json::Number::from_f64(value)
                    .map(|value| StrictJson(Value::Number(value)))
                    .ok_or_else(|| serde::de::Error::custom("nonfinite number"))
            }
            fn visit_str<E: serde::de::Error>(self, value: &str) -> Result<StrictJson, E> {
                Ok(StrictJson(json!(value)))
            }
            fn visit_string<E: serde::de::Error>(self, value: String) -> Result<StrictJson, E> {
                Ok(StrictJson(Value::String(value)))
            }
            fn visit_unit<E: serde::de::Error>(self) -> Result<StrictJson, E> {
                Ok(StrictJson(Value::Null))
            }
        }
        deserializer.deserialize_any(Visitor)
    }
}

fn response(status: StatusCode, value: Value) -> HttpResponse {
    HttpResponse::new(status)
        .with_content_type("application/scim+json")
        .with_binary_body(value.to_string().into_bytes())
        .with_no_store()
}

fn authentication_failure(err: &trc::Error) -> HttpResponse {
    use jmap::api::ToRequestError;
    let native = err.to_request_error();
    let detail = match native.status {
        401 => "Bearer authentication failed",
        403 => "Native authentication policy denied access",
        429 => "Native HTTP rate or concurrency limit exceeded",
        _ => "Native authentication request failed",
    };
    let mut response = failure(error(native.status, None, detail));
    if native.status == 401 {
        response = response.with_header(header::WWW_AUTHENTICATE, "Bearer");
    }
    if let Some(retry) = native.retry_after {
        response = response.with_header(header::RETRY_AFTER, retry.to_string());
    }
    if let Some(policy) = native.rate_limit_policy_header() {
        response = response.with_header("RateLimit-Policy", policy);
    }
    if let Some(state) = native.rate_limit_state_header() {
        response = response.with_header("RateLimit", state);
    }
    response
}

fn error_document(err: &Error) -> Value {
    let mut document = json!({"schemas": ["urn:ietf:params:scim:api:messages:2.0:Error"],
        "status": err.status.to_string(), "detail": err.detail});
    if let Some(kind) = err.scim_type {
        document["scimType"] = json!(kind);
    }
    document
}
fn failure(err: Error) -> HttpResponse {
    response(
        StatusCode::from_u16(err.status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
        error_document(&err),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejected_methods_advertise_endpoint_methods() {
        let response = failure_at(error(405, None, "Method not allowed"), "Users");
        assert_eq!(
            response
                .headers()
                .and_then(|headers| headers.get(header::ALLOW))
                .and_then(|value| value.to_str().ok()),
            Some("GET, POST, OPTIONS")
        );
        assert_eq!(
            allowed_methods("Users/42"),
            "GET, PUT, PATCH, DELETE, OPTIONS"
        );
        assert_eq!(allowed_methods("ServiceProviderConfig"), "GET, OPTIONS");
        assert_eq!(allowed_methods("Users/.search"), "POST, OPTIONS");
    }

    #[test]
    fn authentication_keeps_native_limit_and_policy_classification() {
        let limited = authentication_failure(
            &trc::LimitEvent::TooManyRequests
                .into_err()
                .ctx(trc::Key::Expires, 5u64),
        );
        assert_eq!(limited.status(), StatusCode::TOO_MANY_REQUESTS);
        assert_eq!(
            limited
                .headers()
                .and_then(|headers| headers.get(header::RETRY_AFTER))
                .and_then(|value| value.to_str().ok()),
            Some("5")
        );
        let denied = authentication_failure(&trc::SecurityEvent::Unauthorized.into_err());
        assert_eq!(denied.status(), StatusCode::FORBIDDEN);
        let failed = authentication_failure(
            &trc::AuthEvent::Failed
                .into_err()
                .details("credential-marker-must-not-escape"),
        );
        assert_eq!(failed.status(), StatusCode::UNAUTHORIZED);
        let http_proto::HttpResponseBody::Binary(body) = failed.body() else {
            panic!("SCIM JSON body")
        };
        assert!(!String::from_utf8_lossy(body).contains("credential-marker-must-not-escape"));
    }

    #[test]
    fn group_members_limit_respects_projection() {
        let group = json!({"schemas":[protocol::GROUP_SCHEMA],"id":"test","displayName":"Large Group", "members":(0..201).map(|id| json!({"value":id.to_string(),"type":"User"})).collect::<Vec<_>>()});
        assert_eq!(
            project_read(&group, None, None)
                .err()
                .and_then(|err| err.scim_type),
            Some("tooMany")
        );
        assert!(
            project_read(&group, None, Some("members"))
                .unwrap()
                .get("members")
                .is_none()
        );
        assert!(
            project_read(&group, Some("displayName"), None)
                .unwrap()
                .get("members")
                .is_none()
        );
    }
    #[test]
    fn strong_match_and_cursor_bindings_are_not_ambiguous() {
        assert!(!etag_matches("W/\"v1\"", "\"v1\"", false));
        assert!(etag_matches("W/\"v1\"", "\"v1\"", true));
        let params = BTreeMap::from([("filter".into(), "active eq true".into())]);
        let context = cursor_context(Some(9), 42, "Users", &params);
        let cursor = format!("{context}.2");
        assert_eq!(cursor_offset(&cursor, &context).ok(), Some(2));
        assert!(cursor_offset(&cursor, &cursor_context(Some(10), 42, "Users", &params)).is_err());
        assert!(cursor_offset(&cursor, &cursor_context(Some(9), 43, "Users", &params)).is_err());
    }
    #[test]
    fn bulk_ids_resolve_members_but_not_external_identifiers() {
        let mut operation = json!({"path":"/Groups","data":{"externalId":"bulkId:user","members":[{"value":"bulkId:user"}]}});
        assert_eq!(bulk_dependencies(&operation), vec!["user"]);
        substitute_bulk_ids(
            &mut operation,
            &BTreeMap::from([("user".into(), Some("native-id".into()))]),
        );
        assert_eq!(operation["data"]["members"][0]["value"], "native-id");
        assert_eq!(operation["data"]["externalId"], "bulkId:user");
    }

    #[test]
    fn decoder_rejects_duplicates_before_value_conversion() {
        for input in [
            r#"{"active":true,"active":false}"#,
            r#"{"name":{"formatted":"A","FORMATTED":"B"}}"#,
        ] {
            assert!(serde_json::from_str::<StrictJson>(input).is_err());
        }
        let parsed =
            serde_json::from_str::<StrictJson>(r#"{"active":false,"values":[null,1,1.5,"hello"]}"#)
                .unwrap_or_else(|_| panic!("valid JSON"));
        assert_eq!(parsed.0["active"], false);
        assert_eq!(parsed.0["values"][0], Value::Null);
    }

    #[test]
    fn routes_are_segment_bounded() {
        assert_eq!(route("/scim/v2/Users"), Some(("/scim/v2", "Users")));
        assert_eq!(route("/scim/Groups/"), Some(("/scim", "Groups")));
        assert_eq!(route("/scim-other/Users"), None);
    }
    #[test]
    fn repeated_parameters_are_not_ambiguous() {
        assert!(parameters("count=1&count=200").is_err());
        let params = parameters("count=0&startIndex=1").unwrap_or_else(|_| panic!("valid query"));
        assert_eq!(unsigned_parameter(&params, "count", 100).ok(), Some(0));
        assert_eq!(
            unsigned_parameter(
                &parameters("count=-1").unwrap_or_else(|_| panic!("valid query")),
                "count",
                100
            )
            .ok(),
            None
        );
    }
}
