output "alertmanager_webhook_url" {
  description = "Internal Mattermost incoming webhook URL for Alertmanager"
  value       = "http://mattermost.mattermost.svc.cluster.local:8065/hooks/${mattermost_incoming_webhook.alertmanager.id}"
  sensitive   = true
}

output "hermes_home_channel_id" {
  description = "Mattermost channel ID used as the Hermes home channel"
  value       = mattermost_channel.channels["assistant"].id
}

output "hermes_alerts_channel_id" {
  description = "Mattermost channel ID used for alert notifications and investigations"
  value       = mattermost_channel.channels["alerts"].id
}

output "hermes_code_channel_id" {
  description = "Mattermost channel ID used for coding and software development"
  value       = mattermost_channel.channels["code"].id
}

output "hermes_stateless_channel_ids" {
  description = "Mattermost channel IDs where every post starts a memory-free session"
  value       = mattermost_channel.channels["scratchpad"].id
}

output "hermes_allowed_channel_ids" {
  description = "Mattermost channel IDs in which Hermes may respond"
  value       = join(",", [for name in sort(keys(local.channels)) : mattermost_channel.channels[name].id])
}

output "hermes_free_response_channel_ids" {
  description = "Mattermost channel IDs where Hermes responds without a mention"
  value = join(",", [for name in [
    "assistant",
    "code",
    "scratchpad",
    "finance",
    "homelab",
  ] : mattermost_channel.channels[name].id])
}
