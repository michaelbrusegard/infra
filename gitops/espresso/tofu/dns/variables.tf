variable "dkim_rsa_pub_michaelbrusegard" {
  description = "Base64-encoded RSA DKIM public key for michaelbrusegard.com (TXT record value, without the v=DKIM1; k=rsa; p= prefix)."
  type        = string
}

variable "dkim_ed25519_pub_michaelbrusegard" {
  description = "Base64-encoded ed25519 DKIM public key for michaelbrusegard.com."
  type        = string
}

variable "mta_sts_id" {
  description = "MTA-STS policy id (bump to roll a new policy version). Only consumed once migration records are uncommented in main.tf."
  type        = string
  default     = "v1"
}
