# Membership is administered in Pocket ID; only members get a mailbox.
resource "pocketid_group" "mail" {
  name          = "mail"
  friendly_name = "Mail"
}

resource "pocketid_client" "stalwart" {
  # Public identifier, shared with Stalwart and Bulwark without a secret.
  client_id = "stalwart"
  name      = "Stalwart"
  callback_urls = concat([
    "https://mail.${local.domain}/account/oauth/callback",
    "https://mail.${local.domain}/admin/oauth/callback",
    ], [
    # Bulwark includes the selected locale in its PKCE callback.
    for locale in ["ar", "ca", "cs", "da", "de", "en", "es", "fa", "fr", "he", "hu", "it", "ja", "ko", "lv", "mn", "nl", "pl", "pt", "ro", "ru", "sk", "tr", "uk", "zh"] :
    "https://webmail.${local.domain}/${locale}/auth/callback"
  ])
  launch_url   = "https://webmail.${local.domain}"
  is_public    = true
  pkce_enabled = true
  # Login needs a SCIM-provisioned mailbox. Mail members who are also Pocket
  # ID admins get session-only Stalwart administration.
  allowed_user_groups = [pocketid_group.mail.id]
}

# Pocket ID uses a client's allowlist as the SCIM synchronization boundary,
# so only mail members are provisioned, never every admin.
resource "pocketid_client" "stalwart_scim" {
  client_id           = "stalwart-scim"
  name                = "Stalwart SCIM scope"
  callback_urls       = ["https://mail-backend.${local.domain}/scim-unused"]
  is_public           = true
  pkce_enabled        = true
  allowed_user_groups = [pocketid_group.mail.id]
}

resource "pocketid_scim_service_provider" "stalwart" {
  client_id = pocketid_client.stalwart_scim.id
  endpoint  = "https://mail-backend.${local.domain}/scim/v2"
  token     = var.stalwart_scim_token
}
