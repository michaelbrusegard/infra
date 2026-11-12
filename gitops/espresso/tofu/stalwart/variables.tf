# These select PROXY parsing, not workload authorization. The consumer must
# restrict the listener to the exact smtp-edge namespace+app Cilium identity.
variable "smtp_edge_proxy_networks" {
  description = "Consumer pod CIDRs for the identity-restricted private PROXY listener."
  type        = list(string)
  default     = ["10.42.0.0/16", "fd42::/56"]
  validation {
    condition = length(var.smtp_edge_proxy_networks) > 0 && alltrue([
      for cidr in var.smtp_edge_proxy_networks :
      can(cidrhost(cidr, 0)) && try(tonumber(split("/", cidr)[1]) >= 8, false)
    ])
    error_message = "Provide valid explicit pod CIDRs with prefixes >= 8 (native Stalwart requirement); identity-based network policy is additionally required."
  }
}

variable "stalwart_endpoint" {
  description = "Internal Stalwart management endpoint."
  type        = string
  default     = "http://stalwart-internal.stalwart.svc.cluster.local:8080"
}
