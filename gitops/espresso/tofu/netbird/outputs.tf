output "macchiato_setup_key" {
  description = "Reusable setup key for macchiato routing peer"
  value       = netbird_setup_key.macchiato.key
  sensitive   = true
}
