locals {
  # capsctrl (Mathias). Rulesets take the numeric user ID as bypass actor.
  mathias_user_id = 104485760

  # Existing main rulesets, keyed by repository. self_merge lets Mathias
  # merge his own PRs without approval; direct pushes still need a PR.
  manafishrov_rulesets = {
    infra        = { ruleset_id = 20110863, self_merge = false }
    ui           = { ruleset_id = 20110857, self_merge = false }
    workspace    = { ruleset_id = 20110845, self_merge = false }
    app          = { ruleset_id = 20110855, self_merge = true }
    firmware     = { ruleset_id = 10309196, self_merge = true }
    esc-firmware = { ruleset_id = 20110862, self_merge = true }
    mcu-firmware = { ruleset_id = 10597861, self_merge = true }
  }

  # Mathias's explicit role per repository. The org base permission is
  # read, so repositories missing here are read-only for him. infra-secrets
  # is deliberately absent: it is private, the Free plan cannot enforce a
  # ruleset on it, and Flux applies whatever lands on its main.
  mathias_permissions = {
    infra        = "push"
    ui           = "push"
    workspace    = "push"
    app          = "maintain"
    firmware     = "maintain"
    esc-firmware = "maintain"
    mcu-firmware = "maintain"
    "3dmodels"   = "maintain"
    landing-page = "maintain"
  }
}

# Read-only deploy key for the manafishrov Flux secrets GitRepository
# source. The private half is sops-managed in infra-secrets and applied to
# the cluster as the manafishrov-secrets-auth secret.
resource "github_repository_deploy_key" "flux_espresso_manafishrov_secrets" {
  provider   = github.manafishrov
  repository = "infra-secrets"
  title      = "flux-espresso"
  key        = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHP2Q6sV7UUjH9DjY0UOaQ9iZh+gAtdIZ/1kHhGrkfWp flux-manafishrov-secrets"
  read_only  = true
}

import {
  for_each = local.mathias_permissions
  to       = github_repository_collaborators.manafishrov[each.key]
  id       = each.key
}

# Authoritative: any other direct collaborator or team on these
# repositories is removed on apply.
resource "github_repository_collaborators" "manafishrov" {
  for_each   = local.mathias_permissions
  provider   = github.manafishrov
  repository = each.key

  user {
    username   = "capsctrl"
    permission = each.value
  }
}

import {
  for_each = local.manafishrov_rulesets
  to       = github_repository_ruleset.manafishrov_main[each.key]
  id       = "${each.key}:${each.value.ruleset_id}"
}

resource "github_repository_ruleset" "manafishrov_main" {
  for_each    = local.manafishrov_rulesets
  provider    = github.manafishrov
  repository  = each.key
  name        = "main"
  target      = "branch"
  enforcement = "active"

  bypass_actors {
    actor_type  = "OrganizationAdmin"
    bypass_mode = "always"
  }

  dynamic "bypass_actors" {
    for_each = each.value.self_merge ? [local.mathias_user_id] : []
    content {
      actor_id    = bypass_actors.value
      actor_type  = "User"
      bypass_mode = "pull_request"
    }
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
      allowed_merge_methods             = ["merge", "rebase"]
      dismiss_stale_reviews_on_push     = false
      require_code_owner_review         = false
      require_last_push_approval        = false
      required_approving_review_count   = 1
      required_review_thread_resolution = true
    }

    required_status_checks {
      do_not_enforce_on_create             = false
      strict_required_status_checks_policy = true

      required_check {
        context        = "ci"
        integration_id = 15368 # GitHub Actions
      }
    }
  }
}

# landing-page deploys to GitHub Pages on every push to main and has no CI
# to gate on, so direct pushes stay allowed; this only stops main from
# being force-pushed over or deleted.
resource "github_repository_ruleset" "manafishrov_landing_page_main" {
  provider    = github.manafishrov
  repository  = "landing-page"
  name        = "main"
  target      = "branch"
  enforcement = "active"

  bypass_actors {
    actor_type  = "OrganizationAdmin"
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
  }
}
