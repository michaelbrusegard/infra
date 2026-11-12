# Adopt the objects the first apply created that have no unique key. Import
# blocks are intentionally retained so rebuilding state cannot create
# duplicates with new server-assigned identifiers.
import {
  to = stalwart_directory_oidc.pocket_id
  id = "joepbf2ywiaa"
}

import {
  to = stalwart_certificate.wildcard
  id = "joepbgauwoqa"
}

import {
  to = stalwart_tracer_stdout.stdout
  id = "joepbf02wjqa"
}

import {
  to = stalwart_mta_route_relay.smtp2go
  id = "joepbgg1wwqa"
}

import {
  to = stalwart_dkim_signature_dkim1_rsa_sha256.this["michaelbrusegard.com"]
  id = "joepbgk1w2qa"
}

import {
  to = stalwart_dkim_signature_dkim1_rsa_sha256.this["michbrus.com"]
  id = "joepbgjuwzqa"
}

import {
  to = stalwart_dkim_signature_dkim1_ed25519_sha256.this["michaelbrusegard.com"]
  id = "joepbglkw0qa"
}

import {
  to = stalwart_dkim_signature_dkim1_ed25519_sha256.this["michbrus.com"]
  id = "joepbgkqw9qa"
}
