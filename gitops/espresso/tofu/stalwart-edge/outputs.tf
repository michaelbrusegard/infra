locals {
  # Bootstrap reads this same file for the machine User's Replace permissions.
  # No Query permissions: provider resources read by explicit state/import ID.
  configuration_permissions = toset(jsondecode(file("${path.module}/bootstrap-permissions.json")))
}

output "configuration_permissions" {
  description = "Exact bootstrap-owned machine User Replace permissions. Not the NativeReader identity."
  value       = sort(tolist(local.configuration_permissions))
}
