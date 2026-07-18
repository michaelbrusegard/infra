variable "netbird_token" {
  description = "NetBird management PAT used by tofu-controller"
  type        = string
  sensitive   = true
}

variable "netbird_management_url" {
  description = "NetBird management API base URL"
  type        = string
}

variable "macchiato_blocky_dns_ip" {
  description = "Stable LAN address of Blocky on macchiato, reached through the routing peer. Deliberately not the NetBird peer IP — that one is reassigned whenever the macchiato peer re-registers."
  type        = string
  default     = "10.0.186.1"
}
