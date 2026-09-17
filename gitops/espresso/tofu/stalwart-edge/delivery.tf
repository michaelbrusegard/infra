resource "stalwart_mta_route_relay" "manafishrov" {
  name                = "to-manafishrov"
  description         = "Private final delivery; retain queued mail while the backend is unavailable"
  address             = "backend.manafishrov.com"
  port                = 24
  protocol            = "lmtp"
  implicit_tls        = true
  allow_invalid_certs = false
  auth_secret         = { type = "None" }
}

resource "stalwart_mta_route_relay" "resend" {
  name                = "edge-dsn-resend"
  description         = "Resend for edge-generated DSNs; never direct Internet MX delivery"
  address             = "smtp.resend.com"
  port                = 465
  protocol            = "smtp"
  implicit_tls        = true
  allow_invalid_certs = false
  auth_username       = "resend"
  auth_secret = {
    type          = "EnvironmentVariable"
    variable_name = "STALWART_RESEND_API_KEY"
  }
}

resource "stalwart_mta_outbound_strategy" "edge" {
  route = {
    match = [{
      if   = "rcpt_domain == 'manafishrov.com'"
      then = "'${stalwart_mta_route_relay.manafishrov.name}'"
    }]
    else = "'${stalwart_mta_route_relay.resend.name}'"
  }
}

resource "stalwart_dsn_report_settings" "edge" {
  # Native DsnReportSettings.fromAddress controls the RFC 5322 From header;
  # DSN envelope MAIL FROM remains empty. Resend must accept that contract.
  from_address     = { else = "'postmaster@manafishrov.com'", match = [] }
  from_name        = { else = "'Mail Delivery Subsystem'", match = [] }
  dkim_sign_domain = { else = "false", match = [] }
}
