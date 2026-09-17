locals {
  # One authoritative query shared with the policy service/readiness checks.
  recipient_query = trimspace(file("${path.module}/../../apps/stalwart-edge/policy.sql"))
}

resource "stalwart_store_lookup" "recipients" {
  namespace = "edge-recipients"
  store = {
    type                 = "Sqlite"
    path                 = "/var/lib/stalwart/routing/recipients.sqlite3"
    pool_max_connections = 4
  }
}

resource "stalwart_sieve_system_script" "rcpt_domain_guard" {
  name        = "edge-rcpt-domain-guard"
  description = "Reject internal machine identities and all unapproved recipient domains, without I/O"
  is_active   = true
  # Native Get trims the script; normalize here to avoid perpetual drift.
  contents = trimspace(<<-SIEVE
    require ["envelope", "reject"];
    if not envelope :domain :is "to" "manafishrov.com" {
      reject "550 5.7.1 Recipient domain is not served by this edge";
    }
  SIEVE
  )
}

resource "stalwart_mta_hook" "rcpt_policy" {
  url                 = "http://127.0.0.1:8090/rcpt"
  stages              = ["rcpt"]
  enable              = { else = "true", match = [] }
  temp_fail_on_error  = true
  timeout             = 5000
  allow_invalid_certs = false
  max_response_size   = 16384
  http_auth           = { type = "Unauthenticated" }
  http_headers        = {}
}

resource "stalwart_mta_stage_rcpt" "edge" {
  # Never create a Domain or SQL Directory for manafishrov.com: UnknownDomain
  # must reach this address-specific relay predicate, not local provisioning.
  allow_relaying = {
    match = [{
      if = "rcpt_domain == 'manafishrov.com'"
      # Native expression strings are NOT JSON strings (no Unicode escapes).
      # Preserve literal newlines; the query uses SQL single-quoted strings.
      then = "sql_query('${stalwart_store_lookup.recipients.namespace}', \"${local.recipient_query}\", [rcpt]) == 1"
    }]
    else = "false"
  }
  script     = { else = "'${stalwart_sieve_system_script.rcpt_domain_guard.name}'", match = [] }
  rewrite    = { else = "false", match = [] }
  depends_on = [stalwart_mta_hook.rcpt_policy]
  lifecycle {
    precondition {
      condition     = !strcontains(local.recipient_query, "\"") && !strcontains(local.recipient_query, "\\")
      error_message = "The shared SQL must not contain double quotes or backslashes: native expression quoting is not JSON escaping."
    }
  }
}

resource "stalwart_mta_stage_auth" "edge" {
  require         = { else = "false", match = [] }
  sasl_mechanisms = { else = "false", match = [] }
}

resource "stalwart_mta_stage_data" "edge" {
  enable_spam_filter = { else = "local_port == 25", match = [] }
}

resource "stalwart_sender_auth" "edge" {
  spf_ehlo_verify   = { else = "relaxed", match = [] }
  spf_from_verify   = { else = "relaxed", match = [] }
  dkim_verify       = { else = "relaxed", match = [] }
  dmarc_verify      = { else = "relaxed", match = [] }
  reverse_ip_verify = { else = "relaxed", match = [] }
  dkim_sign_domain  = { else = "false", match = [] }
}

# Created only after the acceptance and delivery policy has been configured.
# Binding new sockets still requires the parent's controlled restart.
resource "stalwart_network_listener" "smtp" {
  name                            = "smtp"
  protocol                        = "smtp"
  bind                            = ["[::]:25"]
  use_tls                         = true
  tls_implicit                    = false
  override_proxy_trusted_networks = []
  depends_on = [
    stalwart_mta_stage_rcpt.edge, stalwart_mta_stage_auth.edge,
    stalwart_mta_stage_data.edge, stalwart_sender_auth.edge,
    stalwart_mta_outbound_strategy.edge, stalwart_system_settings.edge,
  ]
}
