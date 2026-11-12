# Objects without a unique key would duplicate if state were rebuilt: the
# OIDC directory, certificate, tracer and DKIM signatures. After the first
# apply, add import blocks with their server-assigned IDs. Seeded defaults
# are adopted in seeded.tf.

resource "stalwart_mta_sts" "this" {
  max_age  = 604800000
  mode     = "testing"
  mx_hosts = ["mx.asgard.michaelbrusegard.com"]
}

# Default role IDs stay as the server seeded them on first start.
resource "stalwart_authentication" "this" {
  directory_id            = stalwart_directory_oidc.pocket_id.id
  max_api_keys            = 5
  max_app_passwords       = 5
  password_default_expiry = null
  password_hash_algorithm = "argon2id"
  max_password_length     = 128
  min_password_length     = 8
  min_password_strength   = "three"
}

resource "stalwart_directory_oidc" "pocket_id" {
  claim_groups             = "groups"
  claim_name               = "name"
  claim_username           = "email"
  description              = "Pocket ID for michaelbrusegard.com"
  issuer_url               = "https://id.asgard.michaelbrusegard.com"
  member_tenant_id         = null
  accepted_audiences       = ["stalwart"]
  skip_audience_validation = false
  opaque_token_validation  = "userInfo"
  # Preserve Pocket ID administration as well as webmail. These tokens have
  # openid/email scopes, not Stalwart scopes; account roles still bound access.
  unscoped_tokens       = "full"
  allow_id_token_claims = false
  lenient_issuer_match  = false
  allow_invalid_certs   = false
  username_domain       = "michaelbrusegard.com"
}

resource "stalwart_tracer_stdout" "stdout" {
  ansi          = false
  buffered      = false
  enable        = true
  events        = null
  events_policy = "exclude"
  level         = "info"
  lossy         = false
  multiline     = false
}

resource "stalwart_certificate" "wildcard" {
  certificate = {
    file_path     = "/var/lib/stalwart/private/tls/tls.crt"
    type          = "File"
    value         = null
    variable_name = null
  }
  private_key = {
    file_path     = "/var/lib/stalwart/private/tls/tls.key"
    secret        = null
    type          = "File"
    variable_name = null
  }
}

resource "stalwart_imap" "this" {
  allow_plain_text_auth      = false
  max_auth_failures          = 30
  max_concurrent_connections = 16
  max_messages_per_command   = 1000000
  max_messages_per_save      = 1000000
  rate_limit = {
    count  = 2000
    period = 60000
  }
  max_request_size      = 52428800
  max_uid_batches       = 10000
  min_uid_batch_size    = 500
  anonymous_timeout     = 60000
  authenticated_timeout = 1800000
  idle_timeout          = 1800000
}

resource "stalwart_sender_auth" "this" {
  arc_verify = {
    else  = "disable"
    match = null
  }
  dkim_strict = true
  dkim_verify = {
    else = "relaxed"
    match = [
      {
        if   = "listener == 'edge-lmtp' || listener == 'smtp-edge-local'"
        then = "disable"
      },
    ]
  }
  dmarc_verify = {
    else = "disable"
    match = [
      {
        if   = "listener == 'smtp-edge'"
        then = "relaxed"
      },
    ]
  }
  reverse_ip_verify = {
    else = "disable"
    match = [
      {
        if   = "listener == 'smtp-edge'"
        then = "relaxed"
      },
    ]
  }
  spf_ehlo_verify = {
    else = "disable"
    match = [
      {
        if   = "listener == 'smtp-edge'"
        then = "relaxed"
      },
    ]
  }
  spf_from_verify = {
    else = "disable"
    match = [
      {
        if   = "listener == 'smtp-edge'"
        then = "relaxed"
      },
    ]
  }
}

resource "stalwart_application" "webui" {
  auto_update_interval = 2592000000
  description          = "Stalwart Web Interface"
  enable               = true
  # Pocket ID releases the groups claim only for this scope; OIDC admin
  # rights depend on it.
  oauth_scopes     = ["groups"]
  resource_url     = "file:///nix/store/1fvy05k3j1spzk13ahp0rabmwfn2yphs-stalwart-webui-no-upsell-2.0.5"
  unpack_directory = null
  url_prefix       = ["/account", "/admin"]
}

resource "stalwart_system_settings" "this" {
  default_certificate_id = stalwart_certificate.wildcard.id
  default_domain_id      = stalwart_domain.michaelbrusegard.id
  default_hostname       = "mail.asgard.michaelbrusegard.com"
  mail_exchangers = [
    {
      hostname = null
      priority = 10
    },
  ]
  max_connections        = 8192
  provider_info          = {}
  proxy_trusted_networks = null
  lifecycle {
    postcondition {
      condition     = self.proxy_trusted_networks == null ? true : length(self.proxy_trusted_networks) == 0
      error_message = "Global PROXY trust is forbidden; scope it to the private smtp-edge listener."
    }
  }
}

resource "stalwart_mta_stage_data" "this" {
  dkim_sign_domain = {
    else = "false"
    match = [
      {
        if   = "is_local_domain(sender_domain) && !is_empty(authenticated_as)"
        then = "sender_domain"
      },
    ]
  }

  depends_on = [
    stalwart_spam_settings.this,
    stalwart_spam_tag_score.blocked_domain,
    stalwart_spam_pyzor.this,
  ]
  add_auth_results_header = {
    else = "false"
    match = [
      {
        if   = "listener == 'smtp-edge'"
        then = "true"
      },
    ]
  }
  add_date_header = {
    else = "false"
    match = [
      {
        if   = "listener == 'smtp-edge'"
        then = "true"
      },
    ]
  }
  add_delivered_to_header = true
  add_message_id_header = {
    else = "false"
    match = [
      {
        if   = "listener == 'smtp-edge'"
        then = "true"
      },
    ]
  }
  add_received_header = {
    else = "false"
    match = [
      {
        if   = "listener == 'smtp-edge'"
        then = "true"
      },
    ]
  }
  add_received_spf_header = {
    else = "false"
    match = [
      {
        if   = "listener == 'smtp-edge'"
        then = "true"
      },
    ]
  }
  add_return_path_header = {
    else = "false"
    match = [
      {
        if   = "listener == 'smtp-edge'"
        then = "true"
      },
    ]
  }
  enable_spam_filter = {
    else = "false"
    match = [
      {
        if   = "listener == 'smtp-edge'"
        then = "true"
      },
    ]
  }
  max_message_size = {
    else  = "104857600"
    match = null
  }
  max_messages = {
    else  = "10"
    match = null
  }
  max_received_headers = {
    else  = "50"
    match = null
  }
  script = {
    else  = "false"
    match = null
  }
}
