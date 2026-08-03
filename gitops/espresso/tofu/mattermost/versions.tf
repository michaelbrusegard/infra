terraform {
  required_version = "~> 1.11.5"

  required_providers {
    mattermost = {
      source  = "ndrpnt/mattermost"
      version = "0.4.0"
    }
  }
}
