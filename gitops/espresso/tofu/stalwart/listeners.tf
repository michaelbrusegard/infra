# Listeners with unique names adopt the server's seeded objects (http,
# https, submissions, imaps, sieve) and update them in place.

resource "stalwart_network_listener" "http" {
  bind                            = ["[::]:8080"]
  max_connections                 = 8192
  name                            = "http"
  override_proxy_trusted_networks = null
  protocol                        = "http"
  socket_backlog                  = 1024
  socket_no_delay                 = true
  socket_receive_buffer_size      = null
  socket_reuse_address            = true
  socket_reuse_port               = true
  socket_send_buffer_size         = null
  socket_tos_v4                   = null
  socket_ttl                      = null
  tls_disable_cipher_suites       = null
  tls_disable_protocols           = null
  tls_ignore_client_order         = true
  implicit_tls                    = false
  tls_timeout                     = 60000
  use_tls                         = false
}

resource "stalwart_network_listener" "https" {
  bind                            = ["[::]:443"]
  max_connections                 = 8192
  name                            = "https"
  override_proxy_trusted_networks = null
  protocol                        = "http"
  socket_backlog                  = 1024
  socket_no_delay                 = true
  socket_receive_buffer_size      = null
  socket_reuse_address            = true
  socket_reuse_port               = true
  socket_send_buffer_size         = null
  socket_tos_v4                   = null
  socket_ttl                      = null
  tls_disable_cipher_suites       = null
  tls_disable_protocols           = null
  tls_ignore_client_order         = true
  implicit_tls                    = true
  tls_timeout                     = 60000
  use_tls                         = true
}

resource "stalwart_network_listener" "submission" {
  bind                            = ["[::]:587"]
  max_connections                 = 8192
  name                            = "submission"
  override_proxy_trusted_networks = null
  protocol                        = "smtp"
  socket_backlog                  = 1024
  socket_no_delay                 = true
  socket_receive_buffer_size      = null
  socket_reuse_address            = true
  socket_reuse_port               = true
  socket_send_buffer_size         = null
  socket_tos_v4                   = null
  socket_ttl                      = null
  tls_disable_cipher_suites       = null
  tls_disable_protocols           = null
  tls_ignore_client_order         = true
  implicit_tls                    = false
  tls_timeout                     = 60000
  use_tls                         = true
}

resource "stalwart_network_listener" "submissions" {
  bind                            = ["[::]:465"]
  max_connections                 = 8192
  name                            = "submissions"
  override_proxy_trusted_networks = null
  protocol                        = "smtp"
  socket_backlog                  = 1024
  socket_no_delay                 = true
  socket_receive_buffer_size      = null
  socket_reuse_address            = true
  socket_reuse_port               = true
  socket_send_buffer_size         = null
  socket_tos_v4                   = null
  socket_ttl                      = null
  tls_disable_cipher_suites       = null
  tls_disable_protocols           = null
  tls_ignore_client_order         = true
  implicit_tls                    = true
  tls_timeout                     = 60000
  use_tls                         = true
}

resource "stalwart_network_listener" "imaps" {
  bind                            = ["[::]:993"]
  max_connections                 = 8192
  name                            = "imaps"
  override_proxy_trusted_networks = null
  protocol                        = "imap"
  socket_backlog                  = 1024
  socket_no_delay                 = true
  socket_receive_buffer_size      = null
  socket_reuse_address            = true
  socket_reuse_port               = true
  socket_send_buffer_size         = null
  socket_tos_v4                   = null
  socket_ttl                      = null
  tls_disable_cipher_suites       = null
  tls_disable_protocols           = null
  tls_ignore_client_order         = true
  implicit_tls                    = true
  tls_timeout                     = 60000
  use_tls                         = true
}

resource "stalwart_network_listener" "sieve" {
  bind                            = ["[::]:4190"]
  max_connections                 = 8192
  name                            = "sieve"
  override_proxy_trusted_networks = null
  protocol                        = "manageSieve"
  socket_backlog                  = 1024
  socket_no_delay                 = true
  socket_receive_buffer_size      = null
  socket_reuse_address            = true
  socket_reuse_port               = true
  socket_send_buffer_size         = null
  socket_tos_v4                   = null
  socket_ttl                      = null
  tls_disable_cipher_suites       = null
  tls_disable_protocols           = null
  tls_ignore_client_order         = true
  implicit_tls                    = false
  tls_timeout                     = 60000
  use_tls                         = true
}

resource "stalwart_network_listener" "edge_lmtp" {
  bind                            = ["[::]:24"]
  max_connections                 = 8192
  name                            = "edge-lmtp"
  override_proxy_trusted_networks = null
  protocol                        = "lmtp"
  socket_backlog                  = 1024
  socket_no_delay                 = true
  socket_receive_buffer_size      = null
  socket_reuse_address            = true
  socket_reuse_port               = true
  socket_send_buffer_size         = null
  socket_tos_v4                   = null
  socket_ttl                      = null
  tls_disable_cipher_suites       = null
  tls_disable_protocols           = null
  tls_ignore_client_order         = true
  implicit_tls                    = true
  tls_timeout                     = 60000
  use_tls                         = true
}
