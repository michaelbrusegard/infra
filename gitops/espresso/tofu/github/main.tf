# Read-only deploy keys for the Flux secrets GitRepository sources. The
# private halves are sops-managed in infra-secrets (k3s/flux and the
# manafishrov equivalent) and applied to the cluster as the secrets-auth
# and manafishrov-secrets-auth secrets.
resource "github_repository_deploy_key" "flux_espresso_secrets" {
  repository = "infra-secrets"
  title      = "flux-espresso"
  key        = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGxmJXxX1UP9NOjJYd9PM2TkW7aULyBfYJSLDCkeTJRi michaelbrusegard@lungo"
  read_only  = true
}

resource "github_repository_deploy_key" "flux_espresso_manafishrov_secrets" {
  provider   = github.manafishrov
  repository = "infra-secrets"
  title      = "flux-espresso"
  key        = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHP2Q6sV7UUjH9DjY0UOaQ9iZh+gAtdIZ/1kHhGrkfWp flux-manafishrov-secrets"
  read_only  = true
}
