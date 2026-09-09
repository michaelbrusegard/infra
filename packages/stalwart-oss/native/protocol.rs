// SPDX-License-Identifier: AGPL-3.0-only
//! Independent SCIM protocol implementation, based on RFC 7643/7644 and public
//! Stalwart attribute-mapping documentation. No proprietary implementation used.
//! Storage is responsible for domain/tenant policy, locale/timezone registries,
//! uniqueness, member existence, authorization, and server-generated metadata.
use serde_json::{Map, Value, json};
use std::cmp::Ordering;

pub const USER_SCHEMA: &str = "urn:ietf:params:scim:schemas:core:2.0:User";
pub const GROUP_SCHEMA: &str = "urn:ietf:params:scim:schemas:core:2.0:Group";
const PATCH_SCHEMA: &str = "urn:ietf:params:scim:api:messages:2.0:PatchOp";
const ENTERPRISE: &str = "urn:ietf:params:scim:schemas:extension:enterprise:2.0:User";
const MAX_TEXT: usize = 8192;
const MAX_DEPTH: usize = 24;
const MAX_NODES: usize = 20000;
const MAX_BYTES: usize = 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error {
    pub status: u16,
    pub scim_type: Option<&'static str>,
    pub detail: String,
}
impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.detail)
    }
}
impl std::error::Error for Error {}
fn err(kind: &'static str, detail: impl Into<String>) -> Error {
    Error {
        status: 400,
        scim_type: Some(kind),
        detail: detail.into(),
    }
}
fn invalid(detail: impl Into<String>) -> Error {
    err("invalidValue", detail)
}
fn get<'a>(v: &'a Value, key: &str) -> Option<&'a Value> {
    v.as_object()?
        .iter()
        .find(|(k, _)| k.eq_ignore_ascii_case(key))
        .map(|(_, v)| v)
}
fn key_of(m: &Map<String, Value>, key: &str) -> Option<String> {
    m.keys().find(|k| k.eq_ignore_ascii_case(key)).cloned()
}
fn bounded(v: &Value) -> Result<(), Error> {
    fn walk(v: &Value, depth: usize, nodes: &mut usize, bytes: &mut usize) -> Result<(), Error> {
        *nodes += 1;
        if depth > MAX_DEPTH || *nodes > MAX_NODES {
            return Err(invalid("Resource structure exceeds limits"));
        }
        match v {
            Value::Object(m) => {
                let mut keys = std::collections::HashSet::new();
                for (k, v) in m {
                    *bytes += k.len();
                    if !keys.insert(k.to_ascii_lowercase()) {
                        return Err(err("invalidSyntax", "Duplicate case-insensitive attribute"));
                    }
                    walk(v, depth + 1, nodes, bytes)?;
                }
            }
            Value::Array(a) => {
                for v in a {
                    walk(v, depth + 1, nodes, bytes)?;
                }
            }
            Value::String(s) => *bytes += s.len(),
            _ => *bytes += 8,
        }
        if *bytes > MAX_BYTES {
            return Err(invalid("Resource exceeds size limit"));
        }
        Ok(())
    }
    walk(v, 0, &mut 0, &mut 0)
}
fn text<'a>(v: &'a Value, name: &str, required: bool) -> Result<&'a str, Error> {
    let s = v
        .as_str()
        .ok_or_else(|| invalid(format!("{name} must be a string")))?;
    if required && s.trim().is_empty() {
        return Err(invalid(format!("{name} is required")));
    }
    Ok(s)
}
fn boolean(v: &Value) -> Result<bool, Error> {
    match v {
        Value::Bool(b) => Ok(*b),
        Value::String(s) if s == "true" => Ok(true),
        Value::String(s) if s == "false" => Ok(false),
        _ => Err(invalid("Expected a boolean")),
    }
}
fn email(v: &Value) -> Result<String, Error> {
    let s = text(v, "Email address", true)?.trim().to_ascii_lowercase();
    let (local, domain) = s
        .split_once('@')
        .ok_or_else(|| invalid("userName and aliases must be full email addresses"))?;
    if local.is_empty()
        || local.len() > 64
        || local.starts_with('.')
        || local.ends_with('.')
        || local.contains("..")
        || !local
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || b".!#$%&'*+/=?^_`{|}~-".contains(&c))
        || domain.is_empty()
        || domain.len() > 253
        || domain.split('.').any(|p| {
            p.is_empty()
                || p.len() > 63
                || p.starts_with('-')
                || p.ends_with('-')
                || !p.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'-')
        })
    {
        return Err(invalid("Invalid full email address"));
    }
    Ok(s)
}
fn user_primary(body: &Value) -> Result<String, Error> {
    let raw = text(
        get(body, "userName").unwrap_or(&Value::Null),
        "userName",
        true,
    )?
    .trim()
    .to_ascii_lowercase();
    if raw.contains('@') {
        return email(&Value::String(raw));
    }
    // Pocket ID keeps a short login name but supplies the mailbox identity as
    // one explicitly primary email. Accept only that unambiguous form and
    // require the local part to match, so this cannot silently retarget users.
    email(&Value::String(format!("{raw}@placeholder.invalid")))?;
    let items = get(body, "emails")
        .and_then(Value::as_array)
        .ok_or_else(|| invalid("A short userName requires one primary full email"))?;
    let mut primaries = items
        .iter()
        .filter(|item| {
            get(item, "primary")
                .map(boolean)
                .transpose()
                .ok()
                .flatten()
                == Some(true)
        })
        .map(|item| email(get(item, "value").unwrap_or(&Value::Null)));
    let primary = primaries
        .next()
        .transpose()?
        .ok_or_else(|| invalid("A short userName requires one primary full email"))?;
    if primaries.next().is_some() {
        return Err(invalid("A short userName requires one primary full email"));
    }
    if primary.split_once('@').map(|(local, _)| local) != Some(raw.as_str()) {
        return Err(invalid(
            "A short userName must match the primary email local part",
        ));
    }
    Ok(primary)
}
const IGNORED: &[&str] = &[
    "password",
    "phoneNumbers",
    "addresses",
    "photos",
    "ims",
    "title",
    "userType",
    "nickName",
    "profileUrl",
    "entitlements",
    "roles",
    "x509Certificates",
    ENTERPRISE,
];
fn canonical(name: &str, group: bool) -> Option<&'static str> {
    let fields: &[&str] = if group {
        &[
            "schemas",
            "id",
            "externalId",
            "meta",
            "displayName",
            "members",
            "description",
        ]
    } else {
        &[
            "schemas",
            "id",
            "externalId",
            "meta",
            "displayName",
            "userName",
            "name",
            "active",
            "emails",
            "locale",
            "preferredLanguage",
            "timezone",
            "groups",
        ]
    };
    fields
        .iter()
        .copied()
        .find(|s| s.eq_ignore_ascii_case(name))
        .or_else(|| {
            if !group {
                IGNORED
                    .iter()
                    .copied()
                    .find(|s| s.eq_ignore_ascii_case(name))
            } else {
                None
            }
        })
}
fn start(body: &Value, group: bool) -> Result<Value, Error> {
    bounded(body)?;
    let m = body
        .as_object()
        .ok_or_else(|| err("invalidSyntax", "Expected a resource object"))?;
    for k in m.keys() {
        if canonical(k, group).is_none() {
            return Err(err(
                "invalidSyntax",
                format!("Unknown resource attribute: {k}"),
            ));
        }
    }
    let schema = if group { GROUP_SCHEMA } else { USER_SCHEMA };
    let schemas = get(body, "schemas")
        .and_then(Value::as_array)
        .ok_or_else(|| err("invalidSyntax", "schemas must be an array"))?;
    if !schemas.iter().any(|v| v.as_str() == Some(schema)) || schemas.iter().any(|v| !v.is_string())
    {
        return Err(err("invalidSyntax", "Missing core resource schema"));
    }
    if schemas
        .iter()
        .any(|v| v.as_str() != Some(schema) && (group || v.as_str() != Some(ENTERPRISE)))
    {
        return Err(err("invalidSyntax", "Unrecognized resource schema"));
    }
    let mut result = json!({"schemas": [schema]});
    if let Some(v) = get(body, "externalId").filter(|v| !v.is_null()) {
        result["externalId"] = Value::String(text(v, "externalId", false)?.into());
    }
    Ok(result)
}
pub fn normalize_user(body: &Value) -> Result<Value, Error> {
    let mut result = start(body, false)?;
    let primary = user_primary(body)?;
    result["userName"] = json!(primary);
    let name = get(body, "name").filter(|v| !v.is_null());
    if let Some(name) = name {
        let fields = [
            "formatted",
            "givenName",
            "familyName",
            "middleName",
            "honorificPrefix",
            "honorificSuffix",
        ];
        let m = name
            .as_object()
            .ok_or_else(|| invalid("name must be an object"))?;
        for (k, v) in m {
            if !fields.iter().any(|s| k.eq_ignore_ascii_case(s)) {
                return Err(err("invalidSyntax", "Unknown name sub-attribute"));
            }
            if !v.is_null() {
                text(v, k, false)?;
            }
        }
    }
    let display = get(body, "displayName")
        .filter(|v| !v.is_null())
        .or_else(|| {
            name.and_then(|n| get(n, "formatted"))
                .filter(|v| !v.is_null())
        });
    let display = if let Some(v) = display {
        text(v, "displayName", false)?.to_string()
    } else {
        ["givenName", "familyName"]
            .iter()
            .filter_map(|k| name.and_then(|n| get(n, k)).and_then(Value::as_str))
            .filter(|s| !s.is_empty())
            .collect::<Vec<_>>()
            .join(" ")
    };
    result["displayName"] = json!(display);
    result["name"] = json!({"formatted": display});
    result["active"] = json!(
        get(body, "active")
            .filter(|v| !v.is_null())
            .map(boolean)
            .transpose()?
            .unwrap_or(true)
    );
    let mut aliases = std::collections::BTreeSet::new();
    if let Some(v) = get(body, "emails").filter(|v| !v.is_null()) {
        for item in v
            .as_array()
            .ok_or_else(|| invalid("emails must be an array"))?
        {
            validate_subkeys(item, &["value", "display", "type", "primary"], "emails")?;
            let address = email(get(item, "value").unwrap_or(&Value::Null))?;
            let flag = get(item, "primary").map(boolean).transpose()?;
            if let Some(v) = get(item, "type") {
                text(v, "emails.type", false)?;
            }
            if address == primary {
                if flag == Some(false)
                    || get(item, "type").is_some_and(|v| v.as_str() != Some("work"))
                {
                    return Err(err(
                        "mutability",
                        "Change the primary email through userName",
                    ));
                }
            } else {
                if flag == Some(true) {
                    return Err(err("mutability", "The primary email must match userName"));
                }
                aliases.insert(address);
            }
        }
    }
    let mut emails = vec![json!({"value": primary, "primary": true, "type": "work"})];
    emails.extend(
        aliases
            .into_iter()
            .map(|v| json!({"value": v, "primary": false, "type": "work"})),
    );
    result["emails"] = json!(emails);
    if let Some(v) = get(body, "locale")
        .filter(|v| !v.is_null())
        .or_else(|| get(body, "preferredLanguage").filter(|v| !v.is_null()))
    {
        let raw = text(v, "locale", true)?.replace('_', "-");
        if raw.len() > 128
            || !raw
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"-@".contains(&b))
        {
            return Err(invalid("Invalid locale syntax"));
        }
        let mut parts = raw.split('-');
        let mut locale = parts.next().unwrap_or_default().to_ascii_lowercase();
        for part in parts {
            locale.push('-');
            locale.push_str(&if part.len() == 2 {
                part.to_ascii_uppercase()
            } else {
                part.to_string()
            });
        }
        result["locale"] = json!(locale);
        result["preferredLanguage"] = json!(locale);
    }
    if let Some(v) = get(body, "timezone").filter(|v| !v.is_null()) {
        result["timezone"] = json!(text(v, "timezone", true)?);
    }
    Ok(result)
}
fn validate_subkeys(v: &Value, keys: &[&str], context: &str) -> Result<(), Error> {
    let m = v
        .as_object()
        .ok_or_else(|| invalid(format!("{context} entries must be objects")))?;
    if m.keys()
        .any(|k| !keys.iter().any(|s| k.eq_ignore_ascii_case(s)))
    {
        return Err(err(
            "invalidSyntax",
            format!("Unknown {context} sub-attribute"),
        ));
    }
    Ok(())
}
pub fn normalize_group(body: &Value) -> Result<Value, Error> {
    let mut result = start(body, true)?;
    result["displayName"] = json!(text(
        get(body, "displayName").unwrap_or(&Value::Null),
        "displayName",
        true
    )?);
    let mut members = std::collections::BTreeSet::new();
    if let Some(v) = get(body, "members").filter(|v| !v.is_null()) {
        for member in v
            .as_array()
            .ok_or_else(|| invalid("members must be an array"))?
        {
            validate_subkeys(member, &["value", "$ref", "type", "display"], "members")?;
            if get(member, "type").is_some_and(|v| v.as_str() != Some("User")) {
                return Err(invalid("Only User members are supported"));
            }
            members.insert(
                text(
                    get(member, "value").unwrap_or(&Value::Null),
                    "members.value",
                    true,
                )?
                .to_string(),
            );
        }
    }
    result["members"] = json!(
        members
            .into_iter()
            .map(|v| json!({"value":v,"type":"User"}))
            .collect::<Vec<_>>()
    );
    Ok(result)
}

#[derive(Debug, Clone)]
enum Token {
    Word(String),
    Literal(Value),
    Open,
    Close,
    Left,
    Right,
}
fn tokenize(input: &str) -> Result<Vec<Token>, Error> {
    if input.len() > MAX_TEXT {
        return Err(err("invalidFilter", "Expression exceeds length limit"));
    }
    let bytes = input.as_bytes();
    let mut i = 0;
    let mut tokens = Vec::new();
    while i < bytes.len() {
        if bytes[i].is_ascii_whitespace() {
            i += 1;
            continue;
        }
        let token = match bytes[i] {
            b'(' => {
                i += 1;
                Token::Open
            }
            b')' => {
                i += 1;
                Token::Close
            }
            b'[' => {
                i += 1;
                Token::Left
            }
            b']' => {
                i += 1;
                Token::Right
            }
            b'"' => {
                let start = i;
                i += 1;
                while i < bytes.len() {
                    if bytes[i] == b'\\' {
                        i += 2;
                    } else if bytes[i] == b'"' {
                        break;
                    } else {
                        i += 1;
                    }
                }
                if i >= bytes.len() {
                    return Err(err("invalidFilter", "Unterminated string"));
                }
                i += 1;
                Token::Literal(
                    serde_json::from_str(&input[start..i])
                        .map_err(|_| err("invalidFilter", "Invalid JSON string"))?,
                )
            }
            _ => {
                let start = i;
                while i < bytes.len()
                    && !bytes[i].is_ascii_whitespace()
                    && !b"()[]\"".contains(&bytes[i])
                {
                    i += 1;
                }
                let word = &input[start..i];
                if let Ok(v @ (Value::Bool(_) | Value::Null | Value::Number(_))) =
                    serde_json::from_str::<Value>(word)
                {
                    Token::Literal(v)
                } else {
                    Token::Word(word.into())
                }
            }
        };
        tokens.push(token);
        if tokens.len() > 512 {
            return Err(err("invalidFilter", "Too many expression tokens"));
        }
    }
    Ok(tokens)
}
#[derive(Debug, Clone)]
enum Expr {
    Compare(Vec<String>, Op, Value),
    Present(Vec<String>),
    And(Box<Expr>, Box<Expr>),
    Or(Box<Expr>, Box<Expr>),
    Not(Box<Expr>),
    Select(Vec<String>, Box<Expr>),
}
#[derive(Debug, Clone, Copy, PartialEq)]
enum Op {
    Eq,
    Ne,
    Co,
    Sw,
    Ew,
    Gt,
    Ge,
    Lt,
    Le,
}
#[derive(Debug, Clone)]
pub struct Filter(Expr);
struct Parser {
    tokens: Vec<Token>,
    pos: usize,
}
impl Parser {
    fn word(&mut self, expected: &str) -> bool {
        if matches!(self.tokens.get(self.pos), Some(Token::Word(w)) if w.eq_ignore_ascii_case(expected))
        {
            self.pos += 1;
            true
        } else {
            false
        }
    }
    fn expression(&mut self, depth: usize) -> Result<Expr, Error> {
        if depth > MAX_DEPTH {
            return Err(err("invalidFilter", "Expression nesting limit exceeded"));
        }
        let mut left = self.conjunction(depth + 1)?;
        while self.word("or") {
            left = Expr::Or(Box::new(left), Box::new(self.conjunction(depth + 1)?));
        }
        Ok(left)
    }
    fn conjunction(&mut self, depth: usize) -> Result<Expr, Error> {
        let mut left = self.atom(depth)?;
        while self.word("and") {
            left = Expr::And(Box::new(left), Box::new(self.atom(depth)?));
        }
        Ok(left)
    }
    fn atom(&mut self, depth: usize) -> Result<Expr, Error> {
        if depth > MAX_DEPTH {
            return Err(err("invalidFilter", "Expression nesting limit exceeded"));
        }
        if self.word("not") {
            if !matches!(self.tokens.get(self.pos), Some(Token::Open)) {
                return Err(err("invalidFilter", "not requires parentheses"));
            }
            return Ok(Expr::Not(Box::new(self.atom(depth + 1)?)));
        }
        if matches!(self.tokens.get(self.pos), Some(Token::Open)) {
            self.pos += 1;
            let expr = self.expression(depth + 1)?;
            if !matches!(self.tokens.get(self.pos), Some(Token::Close)) {
                return Err(err("invalidFilter", "Expected closing parenthesis"));
            }
            self.pos += 1;
            return Ok(expr);
        }
        let Some(Token::Word(path)) = self.tokens.get(self.pos) else {
            return Err(err("invalidFilter", "Expected attribute path"));
        };
        let path = attr_path(path).map_err(|_| err("invalidFilter", "Invalid attribute path"))?;
        self.pos += 1;
        if matches!(self.tokens.get(self.pos), Some(Token::Left)) {
            self.pos += 1;
            let expr = self.expression(depth + 1)?;
            if !matches!(self.tokens.get(self.pos), Some(Token::Right)) {
                return Err(err("invalidFilter", "Expected closing bracket"));
            }
            self.pos += 1;
            return Ok(Expr::Select(path, Box::new(expr)));
        }
        if self.word("pr") {
            return Ok(Expr::Present(path));
        }
        let op = [
            ("eq", Op::Eq),
            ("ne", Op::Ne),
            ("co", Op::Co),
            ("sw", Op::Sw),
            ("ew", Op::Ew),
            ("gt", Op::Gt),
            ("ge", Op::Ge),
            ("lt", Op::Lt),
            ("le", Op::Le),
        ]
        .into_iter()
        .find_map(|(name, op)| self.word(name).then_some(op))
        .ok_or_else(|| err("invalidFilter", "Unsupported comparison operator"))?;
        let Some(Token::Literal(value)) = self.tokens.get(self.pos) else {
            return Err(err("invalidFilter", "Expected JSON comparison value"));
        };
        if matches!(
            op,
            Op::Gt | Op::Ge | Op::Lt | Op::Le | Op::Co | Op::Sw | Op::Ew
        ) && (value.is_boolean() || value.is_null())
        {
            return Err(err(
                "invalidFilter",
                "Operator incompatible with comparison value",
            ));
        }
        let value = value.clone();
        self.pos += 1;
        Ok(Expr::Compare(path, op, value))
    }
}
fn attr_path(raw: &str) -> Result<Vec<String>, Error> {
    let raw = raw.trim();
    let raw = if raw.get(..4).is_some_and(|s| s.eq_ignore_ascii_case("urn:")) {
        let (schema, suffix) = raw
            .rsplit_once(':')
            .ok_or_else(|| err("invalidPath", "Invalid schema-qualified path"))?;
        if ![USER_SCHEMA, GROUP_SCHEMA]
            .iter()
            .any(|s| schema.eq_ignore_ascii_case(s))
        {
            return Err(err("invalidPath", "Unrecognized attribute schema"));
        }
        suffix
    } else {
        raw
    };
    let path: Vec<_> = raw.split('.').map(str::to_string).collect();
    if path.is_empty()
        || path.len() > 3
        || path.iter().any(|s| {
            s.is_empty()
                || !s.bytes().enumerate().all(|(i, b)| {
                    (b.is_ascii_alphabetic() || b == b'$' && i == 0)
                        || i > 0 && (b.is_ascii_digit() || b == b'-' || b == b'_')
                })
        })
    {
        return Err(err("invalidPath", "Invalid attribute path"));
    }
    Ok(path)
}
fn values<'a>(value: &'a Value, path: &[String], out: &mut Vec<&'a Value>) {
    if path.is_empty() {
        if let Value::Array(a) = value {
            out.extend(a.iter());
        } else {
            out.push(value);
        }
    } else if let Value::Array(a) = value {
        for v in a {
            values(v, path, out);
        }
    } else if let Some(v) = get(value, &path[0]) {
        values(v, &path[1..], out);
    }
}
fn present(v: &Value) -> bool {
    match v {
        Value::Null => false,
        Value::String(s) => !s.is_empty(),
        Value::Array(a) => a.iter().any(present),
        Value::Object(m) => m.values().any(present),
        _ => true,
    }
}
fn comparison(left: &Value, right: &Value, op: Op, exact: bool, datetime: bool) -> bool {
    let order = match (left, right) {
        (Value::String(a), Value::String(b)) => {
            if matches!(op, Op::Co | Op::Sw | Op::Ew) {
                let (a, b) = if exact {
                    (a.clone(), b.clone())
                } else {
                    (a.to_lowercase(), b.to_lowercase())
                };
                return match op {
                    Op::Co => a.contains(&b),
                    Op::Sw => a.starts_with(&b),
                    _ => a.ends_with(&b),
                };
            }
            // Date-time comparison uses instants, not the lexical timezone spelling.
            if datetime {
                match (
                    chrono::DateTime::parse_from_rfc3339(a),
                    chrono::DateTime::parse_from_rfc3339(b),
                ) {
                    (Ok(a), Ok(b)) => Some(a.cmp(&b)),
                    _ => None,
                }
            } else if exact {
                Some(a.cmp(b))
            } else {
                Some(a.to_lowercase().cmp(&b.to_lowercase()))
            }
        }
        (Value::Number(a), Value::Number(b)) => {
            if let (Some(a), Some(b)) = (a.as_i64(), b.as_i64()) {
                Some(a.cmp(&b))
            } else if let (Some(a), Some(b)) = (a.as_u64(), b.as_u64()) {
                Some(a.cmp(&b))
            } else {
                a.as_f64()
                    .zip(b.as_f64())
                    .and_then(|(a, b)| a.partial_cmp(&b))
            }
        }
        (Value::Bool(a), Value::Bool(b)) if matches!(op, Op::Eq | Op::Ne) => Some(a.cmp(b)),
        (Value::Null, Value::Null) => Some(Ordering::Equal),
        _ => None,
    };
    match op {
        Op::Eq => order == Some(Ordering::Equal),
        Op::Ne => order.is_some_and(|o| o != Ordering::Equal),
        Op::Gt => order == Some(Ordering::Greater),
        Op::Ge => order.is_some_and(|o| o != Ordering::Less),
        Op::Lt => order == Some(Ordering::Less),
        Op::Le => order.is_some_and(|o| o != Ordering::Greater),
        _ => false,
    }
}
impl Expr {
    fn matches(&self, resource: &Value) -> bool {
        self.matches_at(resource, None)
    }
    fn matches_at(&self, resource: &Value, context: Option<&str>) -> bool {
        match self {
            Self::And(a, b) => a.matches_at(resource, context) && b.matches_at(resource, context),
            Self::Or(a, b) => a.matches_at(resource, context) || b.matches_at(resource, context),
            Self::Not(a) => !a.matches_at(resource, context),
            Self::Present(path) => {
                let mut found = Vec::new();
                values(resource, path, &mut found);
                found.into_iter().any(present)
            }
            Self::Compare(path, op, rhs) => {
                let mut found = Vec::new();
                values(resource, path, &mut found);
                let membership = context
                    .or_else(|| path.first().map(String::as_str))
                    .is_some_and(|p| {
                        p.eq_ignore_ascii_case("members") || p.eq_ignore_ascii_case("groups")
                    });
                let exact = path.last().is_some_and(|p| {
                    ["id", "externalId", "$ref", "location", "version"]
                        .iter()
                        .any(|s| p.eq_ignore_ascii_case(s))
                }) || membership
                    && path.last().is_some_and(|p| p.eq_ignore_ascii_case("value"));
                if found.is_empty() {
                    return matches!(op, Op::Eq) && rhs.is_null();
                }
                let datetime = path.len() == 2
                    && path[0].eq_ignore_ascii_case("meta")
                    && ["created", "lastModified"]
                        .iter()
                        .any(|s| path[1].eq_ignore_ascii_case(s));
                found
                    .into_iter()
                    .any(|v| comparison(v, rhs, *op, exact, datetime))
            }
            Self::Select(path, expr) => {
                let mut found = Vec::new();
                values(resource, path, &mut found);
                found
                    .into_iter()
                    .any(|v| v.is_object() && expr.matches_at(v, path.first().map(String::as_str)))
            }
        }
    }
    fn public(&mut self) -> Result<(), Error> {
        match self {
            Self::Compare(path, Op::Eq, _) => {
                let name = path.join(".").to_ascii_lowercase();
                if ![
                    "id",
                    "externalid",
                    "username",
                    "emails",
                    "emails.value",
                    "active",
                    "displayname",
                    "name.formatted",
                    "groups",
                    "groups.value",
                    "members",
                    "members.value",
                ]
                .contains(&name.as_str())
                {
                    return Err(err(
                        "invalidFilter",
                        format!("Unsupported filter attribute: {name}"),
                    ));
                }
                if ["emails", "groups", "members"].contains(&name.as_str()) {
                    path.push("value".into());
                }
                Ok(())
            }
            Self::And(a, b) => {
                a.public()?;
                b.public()
            }
            _ => Err(err(
                "invalidFilter",
                "Only eq and and filters are supported; value selections are PATCH-only",
            )),
        }
    }
    fn terms(&self, output: &mut Vec<(String, Value)>) -> Option<()> {
        match self {
            Self::Compare(path, Op::Eq, value) => {
                output.push((path.join(".").to_ascii_lowercase(), value.clone()));
                Some(())
            }
            Self::And(a, b) => {
                a.terms(output)?;
                b.terms(output)
            }
            _ => None,
        }
    }
}
impl Filter {
    /// Full RFC operator parser for internal use; HTTP must use `parse_public`.
    pub fn parse(input: &str) -> Result<Self, Error> {
        let mut parser = Parser {
            tokens: tokenize(input)?,
            pos: 0,
        };
        let expr = parser.expression(0)?;
        if parser.pos != parser.tokens.len() {
            return Err(err("invalidFilter", "Unexpected trailing filter tokens"));
        }
        Ok(Self(expr))
    }
    /// Current documented Stalwart public profile: eq and conjunction only.
    pub fn parse_public(input: &str) -> Result<Self, Error> {
        let mut filter = Self::parse(input)?;
        filter.0.public()?;
        Ok(filter)
    }
    /// Lowercase equality paths and values for indexed candidate selection.
    /// Returns None for the broader internal grammar, never a partial query.
    pub fn equality_terms(&self) -> Option<Vec<(String, Value)>> {
        let mut output = Vec::new();
        self.0.terms(&mut output)?;
        Some(output)
    }
    /// Apply the resource-specific public filter whitelist after parse_public.
    /// Root searches may use parse_public without this per-type restriction.
    pub fn validate_resource_type(&self, resource_type: &str) -> Result<(), Error> {
        let group = match resource_type.to_ascii_lowercase().as_str() {
            "user" | "users" => false,
            "group" | "groups" => true,
            _ => return Err(err("invalidFilter", "Unknown filter resource type")),
        };
        let allowed: &[&str] = if group {
            &["id", "externalid", "displayname", "members.value"]
        } else {
            &[
                "id",
                "externalid",
                "username",
                "emails.value",
                "active",
                "displayname",
                "name.formatted",
                "groups.value",
            ]
        };
        let terms = self
            .equality_terms()
            .ok_or_else(|| err("invalidFilter", "Only eq and and filters are supported"))?;
        for (name, _) in terms {
            if !allowed.contains(&name.as_str()) {
                return Err(err(
                    "invalidFilter",
                    format!("Unsupported filter attribute for {resource_type}: {name}"),
                ));
            }
        }
        Ok(())
    }
    pub fn matches(&self, resource: &Value) -> bool {
        bounded(resource).is_ok() && self.0.matches(resource)
    }
}

#[derive(Debug)]
struct PatchPath {
    head: Vec<String>,
    selection: Option<Filter>,
    tail: Vec<String>,
}
fn patch_path(raw: &str) -> Result<PatchPath, Error> {
    if raw.len() > MAX_TEXT {
        return Err(err("invalidPath", "PATCH path exceeds limit"));
    }
    if let Some(open) = raw.find('[') {
        let mut quoted = false;
        let mut escaped = false;
        let mut nesting = 1;
        let mut end = None;
        for (offset, ch) in raw[open + 1..].char_indices() {
            if escaped {
                escaped = false;
                continue;
            }
            if quoted && ch == '\\' {
                escaped = true;
                continue;
            }
            if ch == '"' {
                quoted = !quoted;
                continue;
            }
            if !quoted {
                if ch == '[' {
                    nesting += 1;
                }
                if ch == ']' {
                    nesting -= 1;
                    if nesting == 0 {
                        end = Some(open + 1 + offset);
                        break;
                    }
                }
            }
        }
        let end = end.ok_or_else(|| err("invalidPath", "Unclosed value selection"))?;
        let suffix = raw[end + 1..].trim();
        let tail = if suffix.is_empty() {
            Vec::new()
        } else {
            attr_path(
                suffix
                    .strip_prefix('.')
                    .ok_or_else(|| err("invalidPath", "Expected sub-attribute after selection"))?,
            )?
        };
        let selection =
            Filter::parse(&raw[open + 1..end]).map_err(|e| err("invalidPath", e.detail))?;
        Ok(PatchPath {
            head: attr_path(&raw[..open])?,
            selection: Some(selection),
            tail,
        })
    } else {
        Ok(PatchPath {
            head: attr_path(raw)?,
            selection: None,
            tail: Vec::new(),
        })
    }
}
fn check_patch_path(path: &PatchPath, group: bool) -> Result<bool, Error> {
    let top = canonical(&path.head[0], group)
        .ok_or_else(|| err("invalidPath", "Unknown PATCH attribute"))?;
    if ["id", "meta", "groups", "schemas"].contains(&top) {
        return Err(err("mutability", "Read-only attribute"));
    }
    if IGNORED.contains(&top) || top == "description" {
        return Ok(false);
    }
    let sub = if path.selection.is_some() {
        if path.head.len() != 1 || !["members", "emails"].contains(&top) {
            return Err(err(
                "invalidPath",
                "Selection requires a multi-valued complex attribute",
            ));
        }
        &path.tail[..]
    } else {
        &path.head[1..]
    };
    if sub.len() > 1 {
        return Err(err("invalidPath", "Too many PATCH sub-attributes"));
    }
    if let Some(s) = sub.first() {
        let allowed: &[&str] = match top {
            "name" => &[
                "formatted",
                "givenName",
                "familyName",
                "middleName",
                "honorificPrefix",
                "honorificSuffix",
            ],
            "emails" => &["value", "display", "primary", "type"],
            "members" => &["value", "$ref", "display", "type"],
            _ => &[],
        };
        if !allowed.iter().any(|k| k.eq_ignore_ascii_case(s)) {
            return Err(err("invalidPath", "Unknown PATCH sub-attribute"));
        }
        if top == "members"
            && ["display", "$ref"]
                .iter()
                .any(|k| k.eq_ignore_ascii_case(s))
        {
            return Err(err("mutability", "Read-only member sub-attribute"));
        }
    }
    Ok(true)
}
fn merge(target: &mut Value, value: &Value, append: bool) {
    if let (Some(target), Some(source)) = (target.as_object_mut(), value.as_object()) {
        for (key, value) in source {
            let key = key_of(target, key).unwrap_or_else(|| key.clone());
            if let Some(old) = target.get_mut(&key) {
                merge(old, value, append);
            } else {
                target.insert(key, value.clone());
            }
        }
    } else if append && target.is_array() {
        let a = target.as_array_mut().unwrap();
        if let Some(source) = value.as_array() {
            for v in source {
                if !a.contains(v) {
                    a.push(v.clone());
                }
            }
        } else if !a.contains(value) {
            a.push(value.clone());
        }
    } else {
        *target = value.clone();
    }
}
fn modify(
    target: &mut Value,
    path: &[String],
    op: &str,
    value: Option<&Value>,
) -> Result<usize, Error> {
    if let Some(a) = target.as_array_mut() {
        let mut count = 0;
        for target in a {
            count += modify(target, path, op, value)?;
        }
        return Ok(count);
    }
    let m = target
        .as_object_mut()
        .ok_or_else(|| err("invalidPath", "PATCH traverses a non-complex attribute"))?;
    let key = key_of(m, &path[0]).unwrap_or_else(|| path[0].clone());
    if path.len() > 1 {
        if !m.contains_key(&key) {
            if op == "remove" {
                return Ok(0);
            }
            m.insert(key.clone(), json!({}));
        }
        return modify(m.get_mut(&key).unwrap(), &path[1..], op, value);
    }
    if op == "remove" {
        return Ok(usize::from(m.remove(&key).is_some()));
    }
    let value = value.ok_or_else(|| err("invalidSyntax", "PATCH operation requires value"))?;
    if let Some(old) = m.get_mut(&key) {
        // Complex replacement preserves unspecified sub-attributes (RFC 7644 3.5.2.3).
        merge(old, value, op == "add");
    } else {
        m.insert(key, value.clone());
    }
    Ok(1)
}
fn selected_modify(
    target: &mut Value,
    path: &[String],
    filter: &Filter,
    tail: &[String],
    op: &str,
    value: Option<&Value>,
) -> Result<usize, Error> {
    let Some(next) = target
        .as_object_mut()
        .and_then(|m| key_of(m, &path[0]).and_then(|k| m.get_mut(&k)))
    else {
        return Ok(0);
    };
    if path.len() > 1 {
        return selected_modify(next, &path[1..], filter, tail, op, value);
    }
    let items = next
        .as_array_mut()
        .ok_or_else(|| err("invalidPath", "Selection target is not multi-valued"))?;
    let mut count = 0;
    let mut i = 0;
    while i < items.len() {
        if !filter
            .0
            .matches_at(&items[i], path.first().map(String::as_str))
        {
            i += 1;
            continue;
        }
        count += 1;
        if tail.is_empty() && op == "remove" {
            items.remove(i);
            continue;
        }
        if tail.is_empty() {
            let v = value.ok_or_else(|| err("invalidSyntax", "PATCH operation requires value"))?;
            if !v.is_object() {
                return Err(invalid("Selected complex replacement requires an object"));
            }
            merge(&mut items[i], v, op == "add");
        } else {
            modify(&mut items[i], tail, op, value)?;
        }
        i += 1;
    }
    Ok(count)
}
fn primary_entry(resource: &Value) -> Option<&Value> {
    let username = get(resource, "userName")?.as_str()?;
    get(resource, "emails")?.as_array()?.iter().find(|v| {
        get(v, "value")
            .and_then(Value::as_str)
            .is_some_and(|s| s.eq_ignore_ascii_case(username))
    })
}
fn protect_primary(before: &Value, after: &Value) -> Result<(), Error> {
    if let Some(old) = primary_entry(before) {
        let Some(new) = primary_entry(after) else {
            return Err(err(
                "mutability",
                "Change the primary email through userName",
            ));
        };
        for key in ["value", "type", "primary"] {
            if get(old, key) != get(new, key) {
                return Err(err(
                    "mutability",
                    "Change the primary email through userName",
                ));
            }
        }
    }
    Ok(())
}
pub fn apply_patch(resource: &Value, request: &Value) -> Result<Value, Error> {
    bounded(resource)?;
    bounded(request)?;
    if !resource.is_object() {
        return Err(invalid("Expected a resource object"));
    }
    if !get(request, "schemas")
        .and_then(Value::as_array)
        .is_some_and(|a| a.iter().any(|v| v.as_str() == Some(PATCH_SCHEMA)))
    {
        return Err(err("invalidSyntax", "Missing PatchOp schema"));
    }
    let ops = get(request, "Operations")
        .and_then(Value::as_array)
        .ok_or_else(|| err("invalidSyntax", "Expected PATCH Operations"))?;
    if ops.is_empty() || ops.len() > 100 {
        return Err(err("invalidSyntax", "Expected 1–100 PATCH operations"));
    }
    let group = get(resource, "schemas")
        .and_then(Value::as_array)
        .is_some_and(|a| a.iter().any(|v| v.as_str() == Some(GROUP_SCHEMA)));
    let mut result = resource.clone();
    for operation in ops {
        let op = get(operation, "op")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_ascii_lowercase();
        if !["add", "replace", "remove"].contains(&op.as_str()) {
            return Err(err("invalidSyntax", "Unsupported PATCH operation"));
        }
        let value = get(operation, "value");
        if op != "remove" && value.is_none() {
            return Err(err("invalidSyntax", "PATCH operation requires value"));
        }
        let mut paths: Vec<(String, Option<&Value>)> = if let Some(path) = get(operation, "path") {
            vec![(text(path, "PATCH path", true)?.to_string(), value)]
        } else {
            if op == "remove" {
                return Err(err("noTarget", "remove requires a path"));
            }
            value
                .and_then(Value::as_object)
                .ok_or_else(|| err("invalidSyntax", "Pathless PATCH requires an object"))?
                .iter()
                .map(|(k, v)| (k.clone(), Some(v)))
                .collect()
        };
        // A pathless operation is one object, not JSON-map iteration order.
        // Apply a rename before validating its derived primary email; the public
        // displayName/locale aliases win when both spellings are supplied.
        paths.sort_by_key(|(p, _)| match p.to_ascii_lowercase().as_str() {
            "username" => 0,
            "name" => 1,
            "preferredlanguage" => 1,
            "displayname" => 3,
            "locale" => 3,
            _ => 2,
        });
        for (raw, value) in paths {
            // Known discarded schema extensions are accepted as whole objects.
            if !group && raw.eq_ignore_ascii_case(ENTERPRISE) {
                continue;
            }
            if !group
                && raw
                    .get(..ENTERPRISE.len())
                    .is_some_and(|p| p.eq_ignore_ascii_case(ENTERPRISE))
                && raw.as_bytes().get(ENTERPRISE.len()) == Some(&b':')
            {
                let path = attr_path(&raw[ENTERPRISE.len() + 1..])?;
                if ![
                    "employeeNumber",
                    "costCenter",
                    "organization",
                    "division",
                    "department",
                    "manager",
                ]
                .iter()
                .any(|s| path[0].eq_ignore_ascii_case(s))
                {
                    return Err(err("invalidPath", "Unknown enterprise extension attribute"));
                }
                continue;
            }
            let mut path = patch_path(&raw)?;
            if !check_patch_path(&path, group)? {
                continue;
            }
            path.head[0] = canonical(&path.head[0], group).unwrap().into();
            let before = if path.head[0] == "emails" {
                Some(result.clone())
            } else {
                None
            };
            let count = if let Some(filter) = &path.selection {
                selected_modify(&mut result, &path.head, filter, &path.tail, &op, value)?
            } else {
                modify(&mut result, &path.head, &op, value)?
            };
            if count == 0 && (op == "remove" || path.selection.is_some()) {
                return Err(err("noTarget", "PATCH path did not match a target"));
            }
            if let Some(before) = before {
                protect_primary(&before, &result)?;
            }
            // Both public display attributes refer to one stored field.
            if path.head[0] == "name" {
                if op == "remove"
                    && (path.head.len() == 1 || path.head[1].eq_ignore_ascii_case("formatted"))
                {
                    result.as_object_mut().unwrap().remove("displayName");
                } else if let Some(formatted) = get(&result, "name")
                    .and_then(|v| get(v, "formatted"))
                    .cloned()
                {
                    result["displayName"] = formatted;
                }
            } else if path.head[0] == "displayName" {
                let display = get(&result, "displayName").cloned().unwrap_or(Value::Null);
                result["name"] = json!({"formatted":display});
            } else if path.head[0] == "userName" {
                // Rename the derived primary entry; it is not retained as an alias.
                let new_primary = email(get(&result, "userName").unwrap_or(&Value::Null))?;
                if let Some(items) = result.get_mut("emails").and_then(Value::as_array_mut) {
                    for item in items {
                        if get(item, "primary").and_then(Value::as_bool) == Some(true) {
                            item["value"] = json!(new_primary);
                        }
                    }
                }
            } else if path.head[0] == "preferredLanguage" {
                if let Some(v) = get(&result, "preferredLanguage").cloned() {
                    result["locale"] = v;
                } else {
                    result.as_object_mut().unwrap().remove("locale");
                }
            } else if path.head[0] == "locale" {
                if let Some(v) = get(&result, "locale").cloned() {
                    result["preferredLanguage"] = v;
                } else {
                    result.as_object_mut().unwrap().remove("preferredLanguage");
                }
            }
            bounded(&result)?;
        }
    }
    Ok(result)
}

fn schema_attributes(group: bool) -> Vec<Value> {
    fn attr(
        name: &str,
        kind: &str,
        multi: bool,
        required: bool,
        mutability: &str,
        returned: &str,
        exact: bool,
        unique: &str,
    ) -> Value {
        json!({"name":name,"type":kind,"multiValued":multi,"description":format!("SCIM {name} attribute"),"required":required,"caseExact":exact,"mutability":mutability,"returned":returned,"uniqueness":unique})
    }
    let mut fields = vec![
        attr(
            "id", "string", false, true, "readOnly", "always", true, "server",
        ),
        attr(
            "externalId",
            "string",
            false,
            false,
            "readWrite",
            "default",
            true,
            "none",
        ),
        attr(
            "displayName",
            "string",
            false,
            group,
            "readWrite",
            "default",
            false,
            if group { "server" } else { "none" },
        ),
    ];
    let mut meta = attr(
        "meta", "complex", false, false, "readOnly", "default", false, "none",
    );
    meta["subAttributes"] = json!([
        attr(
            "resourceType",
            "string",
            false,
            false,
            "readOnly",
            "default",
            true,
            "none"
        ),
        attr(
            "created", "dateTime", false, false, "readOnly", "default", false, "none"
        ),
        attr(
            "lastModified",
            "dateTime",
            false,
            false,
            "readOnly",
            "default",
            false,
            "none"
        ),
        attr(
            "location",
            "reference",
            false,
            false,
            "readOnly",
            "default",
            true,
            "none"
        ),
        attr(
            "version", "string", false, false, "readOnly", "default", true, "none"
        )
    ]);
    fields.push(meta);
    let mut membership = attr(
        if group { "members" } else { "groups" },
        "complex",
        true,
        false,
        if group { "readWrite" } else { "readOnly" },
        "default",
        false,
        "none",
    );
    let mut member_type = attr(
        "type",
        "string",
        false,
        false,
        if group { "readWrite" } else { "readOnly" },
        "default",
        false,
        "none",
    );
    member_type["canonicalValues"] = if group {
        json!(["User"])
    } else {
        json!(["direct", "indirect"])
    };
    let mut reference = attr(
        "$ref",
        "reference",
        false,
        false,
        "readOnly",
        "default",
        true,
        "none",
    );
    reference["referenceTypes"] = if group {
        json!(["User"])
    } else {
        json!(["Group"])
    };
    membership["subAttributes"] = json!([
        attr(
            "value",
            "string",
            false,
            group,
            if group { "readWrite" } else { "readOnly" },
            "default",
            true,
            "none"
        ),
        reference,
        attr(
            "display", "string", false, false, "readOnly", "default", false, "none"
        ),
        member_type
    ]);
    fields.push(membership);
    if !group {
        fields.push(attr(
            "userName",
            "string",
            false,
            true,
            "readWrite",
            "default",
            false,
            "server",
        ));
        fields.push(attr(
            "active",
            "boolean",
            false,
            false,
            "readWrite",
            "default",
            false,
            "none",
        ));
        let mut name = attr(
            "name",
            "complex",
            false,
            false,
            "readWrite",
            "default",
            false,
            "none",
        );
        name["subAttributes"] = json!([attr(
            "formatted",
            "string",
            false,
            false,
            "readWrite",
            "default",
            false,
            "none"
        )]);
        fields.push(name);
        let mut emails = attr(
            "emails",
            "complex",
            true,
            false,
            "readWrite",
            "default",
            false,
            "none",
        );
        let mut email_type = attr(
            "type",
            "string",
            false,
            false,
            "readWrite",
            "default",
            false,
            "none",
        );
        email_type["canonicalValues"] = json!(["work"]);
        emails["subAttributes"] = json!([
            attr(
                "value",
                "string",
                false,
                true,
                "readWrite",
                "default",
                false,
                "none"
            ),
            email_type,
            attr(
                "primary",
                "boolean",
                false,
                false,
                "readWrite",
                "default",
                false,
                "none"
            )
        ]);
        emails["description"] = json!(
            "Primary email is derived from userName; its value, type and primary are read-only. Other entries are aliases."
        );
        fields.push(emails);
        for key in ["locale", "preferredLanguage", "timezone"] {
            fields.push(attr(
                key,
                "string",
                false,
                false,
                "readWrite",
                "default",
                false,
                "none",
            ));
        }
    }
    fields
}
fn known_projection(path: &[String], group: bool) -> bool {
    if path.len() == 1 && path[0].eq_ignore_ascii_case("schemas") {
        return true;
    }
    let attrs = schema_attributes(group);
    let Some(attr) = attrs.iter().find(|a| {
        a["name"]
            .as_str()
            .is_some_and(|s| s.eq_ignore_ascii_case(&path[0]))
    }) else {
        return false;
    };
    path.len() == 1
        || path.len() == 2
            && attr["subAttributes"].as_array().is_some_and(|a| {
                a.iter().any(|a| {
                    a["name"]
                        .as_str()
                        .is_some_and(|s| s.eq_ignore_ascii_case(&path[1]))
                })
            })
}
fn project_tree(value: &Value, paths: &[Vec<String>], include: bool) -> Value {
    if let Some(a) = value.as_array() {
        return Value::Array(a.iter().map(|v| project_tree(v, paths, include)).collect());
    }
    let Some(m) = value.as_object() else {
        return value.clone();
    };
    let mut result = Map::new();
    for (key, value) in m {
        let matched: Vec<_> = paths
            .iter()
            .filter(|p| p[0].eq_ignore_ascii_case(key))
            .collect();
        let whole = matched.iter().any(|p| p.len() == 1);
        if (include && whole) || (!include && matched.is_empty()) {
            result.insert(key.clone(), value.clone());
        } else if !whole && !matched.is_empty() {
            let sub = matched.iter().map(|p| p[1..].to_vec()).collect::<Vec<_>>();
            result.insert(key.clone(), project_tree(value, &sub, include));
        }
    }
    Value::Object(result)
}
pub fn project(
    resource: &Value,
    attributes: Option<&str>,
    excluded_attributes: Option<&str>,
) -> Result<Value, Error> {
    bounded(resource)?;
    if attributes.is_some() && excluded_attributes.is_some() {
        return Err(err(
            "invalidSyntax",
            "attributes and excludedAttributes are mutually exclusive",
        ));
    }
    let group = get(resource, "schemas")
        .and_then(Value::as_array)
        .is_some_and(|a| a.iter().any(|v| v.as_str() == Some(GROUP_SCHEMA)));
    let parse = |raw: &str| -> Result<Vec<Vec<String>>, Error> {
        if raw.len() > MAX_TEXT {
            return Err(err("invalidSyntax", "Projection exceeds limit"));
        }
        let mut paths = Vec::new();
        for raw in raw.split(',') {
            let path = attr_path(raw)?;
            if !known_projection(&path, group) {
                return Err(err("invalidPath", "Unknown projection attribute"));
            }
            paths.push(path);
            if paths.len() > 100 {
                return Err(err("invalidSyntax", "Too many projection attributes"));
            }
        }
        Ok(paths)
    };
    // Only schema-defined attributes can leave the protocol layer, even without
    // a projection. This also removes discarded credentials in defensive callers.
    let mut defined: Vec<Vec<String>> = schema_attributes(group)
        .iter()
        .flat_map(|a| {
            let name = a["name"].as_str().unwrap().to_string();
            if let Some(sub) = a["subAttributes"].as_array() {
                sub.iter()
                    .map(|s| vec![name.clone(), s["name"].as_str().unwrap().into()])
                    .collect::<Vec<_>>()
            } else {
                vec![vec![name]]
            }
        })
        .collect();
    defined.push(vec!["schemas".into()]);
    let clean = project_tree(resource, &defined, true);
    let mut result = if let Some(raw) = attributes {
        project_tree(&clean, &parse(raw)?, true)
    } else if let Some(raw) = excluded_attributes {
        project_tree(&clean, &parse(raw)?, false)
    } else {
        clean
    };
    for key in ["schemas", "id"] {
        if let Some(v) = get(resource, key) {
            result[key] = v.clone();
        }
    }
    Ok(result)
}

/// Relative endpoint, e.g. `Schemas`, `Schemas/<URN>`, `ResourceTypes/User`.
/// Unsupported capabilities stay disabled until the HTTP/storage layer supports them.
pub fn discovery(resource: &str, base_url: &str) -> Option<Value> {
    let base = base_url.trim_end_matches('/');
    let resource = resource.trim_matches('/');
    let with_meta = |mut value: Value, kind: &str, path: &str| {
        value["meta"] = json!({"resourceType":kind,"location":format!("{base}/{path}")});
        value
    };
    if resource == "ServiceProviderConfig" {
        return Some(with_meta(
            json!({
                "schemas":["urn:ietf:params:scim:schemas:core:2.0:ServiceProviderConfig"],
                "documentationUri":"https://stalw.art/docs/auth/scim/",
                "patch":{"supported":true},"bulk":{"supported":false,"maxOperations":0,"maxPayloadSize":0},
                "filter":{"supported":true,"maxResults":200},"changePassword":{"supported":false},
                "sort":{"supported":false},"etag":{"supported":false},"interopProfileConformant":false,
                "authenticationSchemes":[{"type":"oauthbearertoken","name":"Bearer token","description":"Bearer authentication only","specUri":"https://www.rfc-editor.org/rfc/rfc6750","primary":true}]
            }),
            "ServiceProviderConfig",
            resource,
        ));
    }
    let types = [false,true].into_iter().map(|group| {
        let name = if group {"Group"} else {"User"};
        with_meta(json!({"schemas":["urn:ietf:params:scim:schemas:core:2.0:ResourceType"],"id":name,"name":name,"description":format!("Stalwart {name} resource"),"endpoint":format!("/{name}s"),"schema":if group {GROUP_SCHEMA} else {USER_SCHEMA},"schemaExtensions":[]}),"ResourceType",&format!("ResourceTypes/{name}"))
    }).collect::<Vec<_>>();
    let schemas = [false,true].into_iter().map(|group| {
        let id = if group {GROUP_SCHEMA} else {USER_SCHEMA};
        with_meta(json!({"schemas":["urn:ietf:params:scim:schemas:core:2.0:Schema"],"id":id,"name":if group {"Group"} else {"User"},"description":"Supported Stalwart SCIM attributes","attributes":schema_attributes(group)}),"Schema",&format!("Schemas/{id}"))
    }).collect::<Vec<_>>();
    let list = |resources: Vec<Value>| json!({"schemas":["urn:ietf:params:scim:api:messages:2.0:ListResponse"],"totalResults":resources.len(),"startIndex":1,"itemsPerPage":resources.len(),"Resources":resources});
    match resource {
        "ResourceTypes" => Some(list(types)),
        "Schemas" => Some(list(schemas)),
        _ if resource.starts_with("ResourceTypes/") => types
            .into_iter()
            .find(|v| v["id"].as_str() == resource.strip_prefix("ResourceTypes/")),
        _ if resource.starts_with("Schemas/") => schemas
            .into_iter()
            .find(|v| v["id"].as_str() == resource.strip_prefix("Schemas/")),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn user() -> Value {
        normalize_user(&json!({"schemas":[USER_SCHEMA],"userName":"Alice@Example.org","name":{"givenName":"Alice","familyName":"Smith"},"emails":[{"value":"alias@example.org"}]})).unwrap()
    }
    fn patch(ops: Value) -> Value {
        json!({"schemas":[PATCH_SCHEMA],"Operations":ops})
    }
    #[test]
    fn normalization_mapping_and_discarded_credentials() {
        let mut input = user();
        input["password"] = json!("never persist");
        input["roles"] = json!(["admin"]);
        input["id"] = json!("server");
        let result = normalize_user(&input).unwrap();
        assert_eq!(result["userName"], "alice@example.org");
        assert_eq!(result["name"]["formatted"], "Alice Smith");
        assert!(result.get("password").is_none());
        assert!(result.get("roles").is_none());
        assert!(result.get("id").is_none());
        assert_eq!(result["emails"].as_array().unwrap().len(), 2);
    }
    #[test]
    fn normalization_validation_and_case() {
        assert!(
            normalize_user(
                &json!({"SCHEMAS":[USER_SCHEMA],"USERNAME":"a@example.org","ACTIVE":"false"})
            )
            .is_ok()
        );
        let pocket = normalize_user(&json!({
            "schemas": [USER_SCHEMA],
            "userName": "alice",
            "emails": [{"value": "Alice@example.org", "primary": true}],
        }))
        .unwrap();
        assert_eq!(pocket["userName"], "alice@example.org");
        for body in [
            json!({"schemas":[USER_SCHEMA],"userName":"bare"}),
            json!({"schemas":[USER_SCHEMA],"userName":"alice","emails":[{"value":"other@example.org","primary":true}]}),
            json!({"schemas":[USER_SCHEMA],"userName":"alice","emails":[{"value":"alice@example.org","primary":true},{"value":"alice@other.org","primary":true}]}),
        ] {
            assert!(normalize_user(&body).is_err());
        }
        for username in [
            "a@@example.org",
            ".a@example.org",
            "a@-example.org",
            "a b@example.org",
        ] {
            assert!(normalize_user(&json!({"schemas":[USER_SCHEMA],"userName":username})).is_err());
        }
        assert!(normalize_user(&json!({"schemas":[USER_SCHEMA],"userName":"a@example.org","UserName":"b@example.org"})).is_err());
        let mut input = user();
        input["dispalyName"] = json!("typo");
        assert_eq!(
            normalize_user(&input).unwrap_err().scim_type,
            Some("invalidSyntax")
        );
    }
    #[test]
    fn primary_consistency_and_group_constraints() {
        let mut input = user();
        input["emails"][0]["primary"] = json!(false);
        assert_eq!(
            normalize_user(&input).unwrap_err().scim_type,
            Some("mutability")
        );
        assert!(normalize_group(&json!({"schemas":[GROUP_SCHEMA],"displayName":"Team","members":[{"value":"1","type":"Group"}]})).is_err());
        let g = normalize_group(&json!({"schemas":[GROUP_SCHEMA],"displayName":"Team","description":"discard","members":[{"value":"1"},{"value":"1"}]})).unwrap();
        assert_eq!(g["members"].as_array().unwrap().len(), 1);
        assert!(g.get("description").is_none());
    }
    #[test]
    fn all_filter_operators_and_precedence() {
        let resource = json!({"userName":"Alice@example.org","n":10,"active":false,"empty":"","id":"Case","meta":{"created":"2024-01-01T01:00:00+01:00"}});
        for filter in [
            r#"USERNAME eq "alice@example.org""#,
            r#"userName ne "Bob""#,
            r#"userName co "EXAMPLE""#,
            r#"userName sw "ali""#,
            r#"userName ew ".ORG""#,
            "n gt 9",
            "n ge 10",
            "n lt 11",
            "n le 10",
            "active pr",
            "not (empty pr)",
            "active eq true or n eq 10 and active eq false",
            r#"meta.created eq "2024-01-01T00:00:00Z""#,
        ] {
            assert!(
                Filter::parse(filter).unwrap().matches(&resource),
                "{filter}"
            );
        }
        assert!(!Filter::parse(r#"id eq "case""#).unwrap().matches(&resource));
        assert!(Filter::parse_public(r#"userName eq "a" and active eq true"#).is_ok());
        for filter in [
            "n gt 1",
            "n eq 1 or n eq 2",
            "not (n eq 1)",
            "emails[value eq 1]",
        ] {
            assert!(Filter::parse_public(filter).is_err());
        }
    }
    #[test]
    fn value_paths_keep_predicates_on_same_element() {
        let resource = json!({"emails":[{"value":"a@example.org","type":"work"},{"value":"b@example.org","type":"home"}]});
        assert!(
            Filter::parse(r#"emails[type eq "work" and value sw "a"]"#)
                .unwrap()
                .matches(&resource)
        );
        assert!(
            !Filter::parse(r#"emails[type eq "work" and value sw "b"]"#)
                .unwrap()
                .matches(&resource)
        );
        assert!(
            Filter::parse(&format!("{USER_SCHEMA}:emails.value co \"example\""))
                .unwrap()
                .matches(&resource)
        );
    }
    #[test]
    fn malformed_and_bounded_filters() {
        for input in [
            "",
            "a eq",
            "a eq 'x'",
            "a eq true junk",
            "a gt false",
            "not a eq 1",
            "a[x eq 1",
            "(a eq 1",
            "a eq \"\\q\"",
        ] {
            assert!(Filter::parse(input).is_err(), "{input}");
        }
        assert!(Filter::parse(&format!("{}a eq 1{}", "(".repeat(1000), ")".repeat(1000))).is_err());
        assert!(Filter::parse(&"a".repeat(MAX_TEXT + 1)).is_err());
    }
    #[test]
    fn patch_filtered_complex_and_atomic_failure() {
        let original = user();
        let result = apply_patch(&original,&patch(json!([
            {"op":"Add","path":"emails","value":[{"value":"other@example.org"}]},
            {"op":"replace","path":"EMAILS[value eq \"alias@example.org\"].value","value":"renamed@example.org"},
            {"op":"remove","path":"emails[value eq \"other@example.org\"]"}
        ]))).unwrap();
        assert_eq!(
            normalize_user(&result).unwrap()["emails"][1]["value"],
            "renamed@example.org"
        );
        assert_eq!(original["emails"][1]["value"], "alias@example.org");
        assert!(apply_patch(&original,&patch(json!([{"op":"replace","path":"displayName","value":"new"},{"op":"replace","path":"id","value":"bad"}]))).is_err());
        assert_eq!(original["displayName"], "Alice Smith");
    }
    #[test]
    fn patch_primary_readonly_and_missing_targets() {
        for path in [
            "id",
            "meta.version",
            "groups",
            "emails[primary eq true]",
            "emails[primary eq true].type",
        ] {
            let error =
                apply_patch(&user(), &patch(json!([{"op":"remove","path":path}]))).unwrap_err();
            assert_eq!(error.scim_type, Some("mutability"), "{path}");
        }
        assert_eq!(
            apply_patch(
                &user(),
                &patch(json!([{"op":"remove","path":"emails[value eq \"missing@example.org\"]"}]))
            )
            .unwrap_err()
            .scim_type,
            Some("noTarget")
        );
    }
    #[test]
    fn patch_shared_fields_and_rename() {
        let result = apply_patch(&user(),&patch(json!([{"op":"replace","path":"name.formatted","value":"New"},{"op":"replace","path":"userName","value":"new@example.org"},{"op":"add","path":"preferredLanguage","value":"EN-us"}]))).unwrap();
        let result = normalize_user(&result).unwrap();
        assert_eq!(result["displayName"], "New");
        assert_eq!(result["emails"][0]["value"], "new@example.org");
        assert_eq!(result["locale"], "en-US");
    }
    #[test]
    fn projection_complex_and_always_returned() {
        let mut resource = user();
        resource["id"] = json!("1");
        resource["password"] = json!("hidden");
        resource["name"]["givenName"] = json!("discard");
        let result = project(&resource, Some("EMAILS.value,name.formatted"), None).unwrap();
        assert_eq!(result["id"], "1");
        assert!(result.get("schemas").is_some());
        assert!(result.get("userName").is_none());
        assert!(result["emails"][0].get("primary").is_none());
        let result = project(&resource, None, Some("id,schemas,emails.value")).unwrap();
        assert_eq!(result["id"], "1");
        assert!(result["emails"][0].get("value").is_none());
        assert!(result.get("password").is_none());
        assert!(result["name"].get("givenName").is_none());
        assert!(project(&resource, Some("password"), None).is_err());
        assert!(project(&resource, Some("id"), Some("name")).is_err());
    }
    #[test]
    fn discovery_real_schemas_and_conservative_capabilities() {
        let config = discovery("ServiceProviderConfig", "https://host/scim/").unwrap();
        assert_eq!(config["bulk"]["supported"], false);
        assert_eq!(config["sort"]["supported"], false);
        assert_eq!(config["etag"]["supported"], false);
        let schema = discovery(&format!("Schemas/{USER_SCHEMA}"), "https://host/scim").unwrap();
        let attrs = schema["attributes"].as_array().unwrap();
        assert!(
            attrs
                .iter()
                .any(|v| v["name"] == "emails" && v["subAttributes"].is_array())
        );
        assert!(!attrs.iter().any(|v| v["name"] == "password"));
        assert_eq!(
            discovery("ResourceTypes", "https://host/scim").unwrap()["totalResults"],
            2
        );
        assert!(discovery("Schemas/missing", "https://host/scim").is_none());
    }
    #[test]
    fn pathless_alias_precedence_and_primary_rename() {
        let result = apply_patch(&user(), &patch(json!([{"op":"replace","value":{
            "userName":"renamed@example.org", "emails":[{"value":"renamed@example.org","primary":true,"type":"work"}],
            "name":{"formatted":"less important"}, "displayName":"winner",
            "locale":"en-US", "preferredLanguage":"fr-FR"
        }}]))).unwrap();
        let result = normalize_user(&result).unwrap();
        assert_eq!(result["displayName"], "winner");
        assert_eq!(result["locale"], "en-US");
        assert_eq!(result["emails"][0]["value"], "renamed@example.org");
        let cleared = apply_patch(
            &user(),
            &patch(json!([{"op":"remove","path":"name.formatted"}])),
        )
        .unwrap();
        assert_eq!(normalize_user(&cleared).unwrap()["displayName"], "");
    }
    #[test]
    fn member_ids_are_case_exact_inside_selections() {
        let resource = json!({"schemas":[GROUP_SCHEMA],"displayName":"Group","members":[{"value":"Case","type":"User"}]});
        assert!(
            !Filter::parse(r#"members[value eq "case"]"#)
                .unwrap()
                .matches(&resource)
        );
        assert!(
            Filter::parse(r#"members[value eq "Case"]"#)
                .unwrap()
                .matches(&resource)
        );
        assert!(
            apply_patch(
                &resource,
                &patch(json!([{"op":"remove","path":"members[value eq \"case\"]"}]))
            )
            .is_err()
        );
    }
    #[test]
    fn public_filter_whitelist_and_shorthand() {
        let filter =
            Filter::parse_public(r#"emails eq "alice@example.org" and active eq true"#).unwrap();
        assert!(filter.matches(&user()));
        assert!(filter.validate_resource_type("Users").is_ok());
        assert!(filter.validate_resource_type("Groups").is_err());
        assert_eq!(filter.equality_terms().unwrap()[0].0, "emails.value");
        assert!(Filter::parse_public(r#"timezone eq "UTC""#).is_err());
        assert!(Filter::parse_public(r#"name.givenName eq "Alice""#).is_err());
        let filter = Filter::parse_public(r#"members eq "123""#).unwrap();
        assert!(filter.validate_resource_type("Groups").is_ok());
        assert!(filter.validate_resource_type("Users").is_err());
        assert!(filter.matches(&json!({"members":[{"value":"123"}]})));
    }
    #[test]
    fn enterprise_patch_attributes_are_discarded() {
        let original = user();
        let result = apply_patch(&original, &patch(json!([{"op":"replace","path":format!("{ENTERPRISE}:department"),"value":"Engineering"}]))).unwrap();
        assert_eq!(result, original);
    }
    #[test]
    fn structure_budget() {
        let mut value = json!({});
        for _ in 0..30 {
            value = json!({"nested":value});
        }
        assert!(normalize_user(&value).is_err());
        assert!(!Filter::parse("id pr").unwrap().matches(&value));
    }
}
