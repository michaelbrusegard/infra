# Verification and locally generated edge mail share a source address. Exclude
# those trusted paths. PROXY-delivered Internet mail retains its real source IP
# and remains subject to the public-client limits. Both throttles are the
# server's seeded objects, adopted in seeded.tf.
resource "stalwart_mta_inbound_throttle" "sender_recipient" {
  description = "Sender address to recipient throttle"
  enable      = true
  key         = ["senderDomain", "rcpt"]
  match       = { else = "listener != 'edge-lmtp' && listener != 'smtp-edge-local'", match = null }
  rate        = { count = 25, period = 3600000 }
}

resource "stalwart_mta_inbound_throttle" "sender_ip" {
  description = "Sender IP throttle"
  enable      = true
  key         = ["remoteIp"]
  match       = { else = "listener != 'edge-lmtp' && listener != 'smtp-edge-local'", match = null }
  rate        = { count = 5, period = 1000 }
}
