variable "mattermost_admin_token" {
  description = "Access token for the local Mattermost system administrator"
  type        = string
  sensitive   = true
}

variable "mattermost_admin_username" {
  description = "Username of the local Mattermost system administrator"
  type        = string
}
