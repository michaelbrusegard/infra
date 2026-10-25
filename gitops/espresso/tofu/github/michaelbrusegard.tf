# Read-only deploy key for the Flux secrets GitRepository source. The
# private half is sops-managed in infra-secrets (k3s/flux) and applied to
# the cluster as the secrets-auth secret.
resource "github_repository_deploy_key" "flux_espresso_secrets" {
  repository = "infra-secrets"
  title      = "flux-espresso"
  key        = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGxmJXxX1UP9NOjJYd9PM2TkW7aULyBfYJSLDCkeTJRi michaelbrusegard@lungo"
  read_only  = true
}

# Write key the image workflows use to commit digest bumps to main past
# the ruleset (DeployKey bypass). The private half is the IMAGE_BUMP_DEPLOY_KEY
# secret of the image-bump environment, set with `gh secret set --env` so
# it never lands in tofu state.
resource "github_repository_deploy_key" "image_bump" {
  repository = "infra"
  title      = "image-bump"
  key        = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIzrJ/6vvuImL47mKGymHhsGIsa1c7j6gUkNPZENA5ZO image-bump@github-actions"
  read_only  = false
}

# Only jobs running on main can enter the environment, so PR runs never
# see the image-bump key.
resource "github_repository_environment" "image_bump" {
  repository        = "infra"
  environment       = "image-bump"
  can_admins_bypass = false

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "image_bump_main" {
  repository     = "infra"
  environment    = github_repository_environment.image_bump.environment
  branch_pattern = "main"
}

resource "github_repository_ruleset" "infra_main" {
  repository  = "infra"
  name        = "main"
  target      = "branch"
  enforcement = "active"

  bypass_actors {
    actor_type  = "DeployKey"
    bypass_mode = "always"
  }

  bypass_actors {
    actor_id    = 5 # admin
    actor_type  = "RepositoryRole"
    bypass_mode = "always"
  }

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true

    pull_request {
      allowed_merge_methods             = ["merge", "squash", "rebase"]
      dismiss_stale_reviews_on_push     = false
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_approving_review_count   = 0
      required_review_thread_resolution = false
    }

    required_status_checks {
      do_not_enforce_on_create             = false
      strict_required_status_checks_policy = false

      required_check {
        context = "filter"
      }
      required_check {
        context = "code-quality"
      }
      required_check {
        context = "validate-nix"
      }
      required_check {
        context = "validate-kubernetes"
      }
      required_check {
        context = "validate-tofu"
      }
    }
  }
}

resource "github_repository_ruleset" "infra_secrets_main" {
  repository  = "infra-secrets"
  name        = "main"
  target      = "branch"
  enforcement = "active"

  bypass_actors {
    actor_id    = 5 # admin
    actor_type  = "RepositoryRole"
    bypass_mode = "always"
  }

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true

    pull_request {
      allowed_merge_methods             = ["merge", "squash", "rebase"]
      dismiss_stale_reviews_on_push     = false
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_approving_review_count   = 0
      required_review_thread_resolution = false
    }

    required_status_checks {
      do_not_enforce_on_create             = false
      strict_required_status_checks_policy = false

      required_check {
        context = "check"
      }
    }
  }
}
