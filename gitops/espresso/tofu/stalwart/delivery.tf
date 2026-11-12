# Private relay listeners accept only identity-restricted edge traffic.
# LMTP serves the edge's recipient verification. Submission listeners retain
# their authentication requirements.
resource "stalwart_mta_stage_auth" "server" {
  require = {
    match = [{
      if   = "listener == 'edge-lmtp' || listener == 'smtp-edge' || listener == 'smtp-edge-local'"
      then = "false"
    }]
    else = "true"
  }
  sasl_mechanisms = {
    match = [
      {
        if   = "listener == 'edge-lmtp' || listener == 'smtp-edge' || listener == 'smtp-edge-local'"
        then = "false"
      },
      {
        if   = "local_port != 25 && is_tls"
        then = "[plain, login, oauthbearer, xoauth2]"
      },
      {
        if   = "local_port != 25"
        then = "[oauthbearer, xoauth2]"
      },
    ]
    else = "false"
  }
  # The single user sends as any address in a local domain (mb@, service@
  # michbrus.com, ...) over SMTP submission. Any other sender domain must
  # still be one of the account's own addresses, which are all local, so a
  # foreign domain is always refused. JMAP submission runs through this rule
  # too; the catch-all send-as patch only governs which identities exist.
  must_match_sender = {
    match = [{
      if   = "!is_empty(authenticated_as) && is_local_domain(sender_domain)"
      then = "false"
    }]
    else = "true"
  }
}

# All remote mail leaves through SMTP2GO; the backend reads the password
# from its own environment, not the OpenTofu runner.
resource "stalwart_mta_route_relay" "smtp2go" {
  name                = "smtp2go"
  description         = "SMTP2GO smarthost for external mail"
  host                = "mail.smtp2go.com"
  port                = 587
  protocol            = "smtp"
  implicit_tls        = false
  allow_invalid_certs = false
  auth_username       = "stalwart-personal"
  auth_secret = {
    type          = "EnvironmentVariable"
    variable_name = "STALWART_SMTP2GO_PASSWORD"
  }
}

# The seeded "default" strategy only offers STARTTLS opportunistically, and
# "invalid-tls" accepts any certificate on retry. Neither may carry relay
# credentials, so remote delivery requires a verified STARTTLS session.
resource "stalwart_mta_tls_strategy" "smtp2go" {
  name                = "smtp2go"
  description         = "Required, verified STARTTLS to the SMTP2GO relay"
  start_tls           = "require"
  allow_invalid_certs = false
}

resource "stalwart_mta_outbound_strategy" "this" {
  route = {
    match = [{
      if   = "is_local_domain(rcpt_domain)"
      then = "'local'"
    }]
    else = "'${stalwart_mta_route_relay.smtp2go.name}'"
  }
  tls = {
    match = []
    else  = "'${stalwart_mta_tls_strategy.smtp2go.name}'"
  }
}
