variable "mattermost_admin_token" {
  description = "Access token for the local Mattermost system administrator"
  type        = string
  sensitive   = true
}

variable "mattermost_admin_username" {
  description = "Username of the local Mattermost system administrator"
  type        = string
}

variable "mattermost_team_id" {
  description = "ID of the pre-created Hermes team adopted by OpenTofu"
  type        = string
}

variable "mattermost_town_square_channel_id" {
  description = "ID of the mandatory Town Square channel adopted as assistant"
  type        = string
}

variable "mattermost_off_topic_channel_id" {
  description = "ID of the default Off-Topic channel adopted as scratchpad"
  type        = string
}
