locals {
  channels = {
    assistant = {
      name         = "town-square"
      display_name = "Assistant"
      header       = "General conversations and requests for Hermes."
    }
    scratchpad = {
      name         = "scratchpad"
      display_name = "Scratchpad"
      header       = "One-shot Hermes requests with no prior session or persistent memory context."
    }
    code = {
      name         = "code"
      display_name = "Code"
      header       = "Coding and software development with Hermes."
    }
    groceries = {
      name         = "groceries"
      display_name = "Groceries"
      header       = "Grocery planning, shopping lists, and store research with Hermes."
    }
    homelab = {
      name         = "homelab"
      display_name = "Homelab"
      header       = "Infrastructure operations and cluster discussions."
    }
    alerts = {
      name         = "alerts"
      display_name = "Alerts"
      header       = "Monitoring alerts and Hermes investigations."
    }
  }
}

import {
  to = mattermost_team.hermes
  id = var.mattermost_team_id
}

resource "mattermost_team" "hermes" {
  name         = "hermes"
  display_name = "Hermes"
  description  = "Private home operations and assistant workspace."
  type         = "I"

  lifecycle {
    prevent_destroy = true
  }
}

resource "mattermost_channel" "channels" {
  for_each = local.channels

  team_id = mattermost_team.hermes.id
  # Mattermost does not allow changing the canonical names of its two
  # protected default channels. Their UI display names are still managed as
  # Assistant and Scratchpad.
  name         = each.value.name
  display_name = each.value.display_name
  header       = each.value.header
  type         = "O"

  lifecycle {
    prevent_destroy = true
  }
}

moved {
  from = mattermost_channel.channels["finance"]
  to   = mattermost_channel.channels["groceries"]
}

import {
  to = mattermost_channel.channels["assistant"]
  id = var.mattermost_town_square_channel_id
}

import {
  to = mattermost_channel.channels["scratchpad"]
  id = var.mattermost_off_topic_channel_id
}

data "mattermost_user" "hermes_bot" {
  username = "hermes"
}

data "mattermost_user" "admin" {
  username = var.mattermost_admin_username
}

resource "mattermost_team_member" "admin" {
  team_id = mattermost_team.hermes.id
  user_id = data.mattermost_user.admin.id
}

import {
  to = mattermost_team_member.admin
  id = "${var.mattermost_team_id}/${data.mattermost_user.admin.id}"
}

resource "mattermost_team_member" "hermes_bot" {
  team_id = mattermost_team.hermes.id
  user_id = data.mattermost_user.hermes_bot.id
}

resource "mattermost_channel_member" "hermes_bot" {
  for_each = mattermost_channel.channels

  channel_id = each.value.id
  user_id    = data.mattermost_user.hermes_bot.id
}

resource "mattermost_channel_member" "admin" {
  for_each = mattermost_channel.channels

  channel_id = each.value.id
  user_id    = data.mattermost_user.admin.id
}

moved {
  from = mattermost_channel_member.hermes_bot["finance"]
  to   = mattermost_channel_member.hermes_bot["groceries"]
}

moved {
  from = mattermost_channel_member.admin["finance"]
  to   = mattermost_channel_member.admin["groceries"]
}

import {
  to = mattermost_channel_member.admin["assistant"]
  id = "${var.mattermost_town_square_channel_id}/${data.mattermost_user.admin.id}"
}

import {
  to = mattermost_channel_member.admin["scratchpad"]
  id = "${var.mattermost_off_topic_channel_id}/${data.mattermost_user.admin.id}"
}

resource "mattermost_incoming_webhook" "alertmanager" {
  channel_id  = mattermost_channel.channels["alerts"].id
  name        = "Alertmanager"
  description = "Warning and critical alerts from the espresso cluster."

  lifecycle {
    prevent_destroy = true
  }
}
