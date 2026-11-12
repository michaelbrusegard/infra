# A fresh server seeds a web UI application, two inbound throttles and a
# plain "smtp" listener on port 25. None can be adopted by a unique key that
# this stack uses, so look up their IDs and import them instead of creating
# duplicates. The lookups also re-adopt the objects if state is rebuilt.
data "stalwart_applications" "all" {}

data "stalwart_application" "all" {
  for_each = data.stalwart_applications.all.ids
  id       = each.value
}

data "stalwart_mta_inbound_throttles" "all" {}

data "stalwart_mta_inbound_throttle" "all" {
  for_each = data.stalwart_mta_inbound_throttles.all.ids
  id       = each.value
}

data "stalwart_network_listeners" "all" {}

data "stalwart_network_listener" "all" {
  for_each = data.stalwart_network_listeners.all.ids
  id       = each.value
}

import {
  to = stalwart_application.webui
  id = one([for id, app in data.stalwart_application.all : id if app.description == "Stalwart Web Interface"])
}

import {
  to = stalwart_mta_inbound_throttle.sender_ip
  id = one([for id, throttle in data.stalwart_mta_inbound_throttle.all : id if throttle.description == "Sender IP throttle"])
}

import {
  to = stalwart_mta_inbound_throttle.sender_recipient
  id = one([for id, throttle in data.stalwart_mta_inbound_throttle.all : id if throttle.description == "Sender address to recipient throttle"])
}

# Listener names are immutable, so importing the seeded "smtp" listener plans
# its replacement by smtp-edge. Otherwise both would bind port 25 with
# SO_REUSEPORT and split Internet mail between PROXY and non-PROXY listeners.
import {
  for_each = toset([for id, listener in data.stalwart_network_listener.all : id if listener.name == "smtp"])
  to       = stalwart_network_listener.smtp_edge
  id       = each.value
}
