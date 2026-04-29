terraform {
  required_version = "= 1.11.6"

  required_providers {
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "= 1.26.0"
    }
  }
}
