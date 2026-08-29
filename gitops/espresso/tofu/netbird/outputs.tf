output "macchiato_setup_key" {
  description = "Reusable setup key for macchiato routing peer"
  value       = netbird_setup_key.macchiato.key
  sensitive   = true
}

output "cortado_setup_key" {
  description = "Reusable setup key for cortado routing peer"
  value       = netbird_setup_key.cortado.key
  sensitive   = true
}
