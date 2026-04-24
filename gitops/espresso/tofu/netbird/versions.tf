terraform {
  required_version = ">= 1.9.0"

  required_providers {
    netbird = {
      source = "netbirdio/netbird"
      version = "= 0.0.9"
    }
  }
}
