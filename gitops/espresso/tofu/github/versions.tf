terraform {
  required_version = "~> 1.11.5"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "6.13.0"
    }
  }
}
