locals {
  channels = {
    assistant = {
      display_name = "Assistant"
      description  = "General conversations and requests for Hermes."
    }
    meals = {
      display_name = "Meals"
      description  = "Meal planning, recipes, and Mealie activity."
    }
    shopping = {
      display_name = "Shopping"
      description  = "Shopping lists, purchases, and errands."
    }
    finance = {
      display_name = "Finance"
      description  = "Personal finance planning and tracking."
    }
    homelab = {
      display_name = "Homelab"
      description  = "Infrastructure operations and cluster discussions."
    }
    alerts = {
      display_name = "Alerts"
      description  = "Monitoring alerts and Hermes investigations."
    }
  }
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

  team_id      = mattermost_team.hermes.id
  name         = each.key
  display_name = each.value.display_name
  description  = each.value.description
  type         = "O"

  lifecycle {
    prevent_destroy = true
  }
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

resource "mattermost_incoming_webhook" "alertmanager" {
  channel_id  = mattermost_channel.channels["alerts"].id
  name        = "Alertmanager"
  description = "Warning and critical alerts from the espresso cluster."
  username    = "Alertmanager"

  lifecycle {
    prevent_destroy = true
  }
}
