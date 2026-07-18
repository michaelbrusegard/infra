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
  description = "IP of Blocky on macchiato reachable from NetBird peers. NetBird reassigns this IP whenever the macchiato peer re-registers; the current value is visible under the macchiato peer in the dashboard."
  type        = string
  default     = "100.105.222.116"
}
