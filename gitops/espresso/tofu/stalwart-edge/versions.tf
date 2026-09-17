terraform {
  required_version = "~> 1.11.5"

  required_providers {
    stalwart = {
      source  = "tahacodes/stalwart"
      version = "0.2.3"
    }
  }

  # tofu-controller supplies the Kubernetes backend configuration.
  backend "kubernetes" {}
}

provider "stalwart" {
  endpoint    = var.stalwart_endpoint
  insecure    = false
  auto_reload = true
  # STALWART_TOKEN is injected into the runner, never stored in configuration.
}
