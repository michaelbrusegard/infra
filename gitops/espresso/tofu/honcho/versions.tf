terraform {
  # renovate: datasource=github-releases depName=opentofu/opentofu
  required_version = "= 1.11.5"

  required_providers {
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "= 1.26.0"
    }
  }
}
