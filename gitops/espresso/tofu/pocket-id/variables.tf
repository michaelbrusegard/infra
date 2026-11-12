variable "pocket_id_api_token" {
  description = "Pocket ID admin API token used by tofu-controller"
  type        = string
  sensitive   = true
}

variable "stalwart_scim_token" {
  description = "Stalwart API key with SCIM and account permissions, used by Pocket ID to provision mailboxes"
  type        = string
  sensitive   = true
}
