variable "stalwart_endpoint" {
  type    = string
  default = "https://edge.asgard.michaelbrusegard.com"
  validation {
    condition     = startswith(var.stalwart_endpoint, "https://")
    error_message = "Management requires certificate-verified HTTPS."
  }
}

variable "bootstrap_internal_domain_id" {
  type        = string
  description = "ID of bootstrap's system.edge.asgard.michaelbrusegard.com internal machine domain."
}

variable "bootstrap_https_listener_id" {
  type        = string
  description = "ID of bootstrap's https listener (HTTP with implicit TLS on 443)."
}

variable "bootstrap_certificate_id" {
  type        = string
  description = "ID of bootstrap's file-backed wildcard certificate used to reach management."
}

variable "bootstrap_webui_id" {
  type        = string
  default     = null
  description = "Import an existing disabled Application, if bootstrap created one; otherwise create it."
}

variable "webui_resource_url" {
  type        = string
  default     = "file:///usr/local/share/stalwart/webui.zip"
  description = "file:/// path to bundled WebUI assets in the pinned image; no remote/latest download."
  validation {
    condition     = startswith(var.webui_resource_url, "file:///")
    error_message = "Use bundled file:/// assets only."
  }
}
