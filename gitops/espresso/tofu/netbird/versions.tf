terraform {
  # renovate: datasource=github-releases depName=opentofu/opentofu
  required_version = "= 1.11.6"

  required_providers {
    netbird = {
      source  = "netbirdio/netbird"
      version = "= 0.0.9"
    }
  }
}
