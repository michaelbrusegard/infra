# Private verification and queued delivery need prompt recipient responses.
# Keep penalties unchanged on unrelated authenticated listeners.
resource "stalwart_mta_stage_rcpt" "server" {
  # None of the three private listeners offers SASL. Local domains still accept
  # recipients, but an edge connection must never relay to an external domain.
  allow_relaying = {
    else  = "!is_empty(authenticated_as)"
    match = null
  }
  wait_on_fail = {
    match = [{
      if = "listener == 'edge-lmtp' || listener == 'smtp-edge' || listener == 'smtp-edge-local'"
      # Native Duration conversion requires a strictly positive integer.
      then = "1ms"
    }]
    else = "5s"
  }
}
