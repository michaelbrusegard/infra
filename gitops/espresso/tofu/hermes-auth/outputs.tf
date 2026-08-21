output "oauth2_client_id" {
  value = pocketid_client.android_viewer.id
}

output "oauth2_client_secret" {
  value     = pocketid_client.android_viewer.client_secret
  sensitive = true
}

output "oauth2_cookie_secret" {
  value     = random_password.oauth2_cookie_secret.result
  sensitive = true
}
