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
  description = "IP of Blocky on macchiato reachable from NetBird peers"
  type        = string
  default     = "100.105.105.87"
}
