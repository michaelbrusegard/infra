provider "mattermost" {
  url   = "http://mattermost.mattermost.svc.cluster.local:8065"
  token = var.mattermost_admin_token
}
