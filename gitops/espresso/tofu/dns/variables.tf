variable "dkim_rsa_pub_michaelbrusegard" {
  description = "Base64-encoded RSA DKIM public key for michaelbrusegard.com (TXT record value, without the v=DKIM1; k=rsa; p= prefix)."
  type        = string
}

variable "dkim_ed25519_pub_michaelbrusegard" {
  description = "Base64-encoded raw 32-byte ed25519 DKIM public key for michaelbrusegard.com (RFC 8463)."
  type        = string
}

variable "dkim_rsa_pub_michbrus" {
  description = "Base64-encoded RSA DKIM public key for michbrus.com (TXT record value, without the v=DKIM1; k=rsa; p= prefix)."
  type        = string
}

variable "dkim_ed25519_pub_michbrus" {
  description = "Base64-encoded raw 32-byte ed25519 DKIM public key for michbrus.com (RFC 8463)."
  type        = string
}
