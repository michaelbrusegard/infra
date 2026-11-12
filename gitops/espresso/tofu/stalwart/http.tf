# Bulwark connects directly to JMAP from the browser after Pocket ID login.
# Restrict cross-origin access to the webmail origin, not wildcard CORS.
resource "stalwart_http" "server" {
  use_permissive_cors = false
  enable_hsts         = false
  # Envoy appends the real client on the right. Trust exactly that hop;
  # earlier client-supplied XFF entries cannot choose the address. Missing
  # headers fall back to the TCP peer. HTTP ingress is Gateway-restricted.
  client_ip_source = "xForwardedFor"
  forwarded_hops   = 1
  redirect_root    = "/account"
  # SCIM is only for Pocket ID, which reaches the private https listener via
  # mail-backend. The Gateway routes to the http listener, so a leaked
  # provisioning token is useless from the Internet.
  allowed_endpoints = {
    else = "200"
    match = [{
      if   = "listener != 'https' && starts_with(path, '/scim')"
      then = "403"
    }]
  }
  rate_limit_authenticated = {
    count  = 1000
    period = 60000
  }
  # Known OIDC tokens use admission-only hints, not cached authorization.
  # Every request still revalidates claims/account state and uses the account
  # budget (including privileged OIDC sessions). Unknown tokens remain subject
  # to this IP budget, using the Gateway-appended client address.
  rate_limit_anonymous = {
    count  = 100
    period = 60000
  }
  response_headers = {
    "Access-Control-Allow-Origin"  = "https://webmail.asgard.michaelbrusegard.com"
    "Access-Control-Allow-Methods" = "GET, HEAD, POST, OPTIONS"
    "Access-Control-Allow-Headers" = "Authorization, Content-Type, Accept, Last-Event-ID"
  }
}
