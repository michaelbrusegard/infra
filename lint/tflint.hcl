plugin "terraform" {
  enabled = true
  preset  = "all"
}

rule "terraform_documented_outputs" {
  enabled = false
}

rule "terraform_documented_variables" {
  enabled = false
}

rule "terraform_standard_module_structure" {
  enabled = false
}
