output "oidc_sub_prefix" {
  description = "The fixed prefix in the GitHub OIDC sub claim before the branch name."
  value       = local.oidc_sub_prefix
}

output "oidc_sub_prefix_length" {
  description = "Byte/character length of the fixed OIDC sub prefix."
  value       = local.oidc_sub_prefix_length
}

output "effective_max_branch_length" {
  description = "Maximum allowed branch name length enforced by the ruleset."
  value       = local.effective_max_branch_length
}

output "branch_length_regex" {
  description = "Regex pattern configured on the GitHub repository ruleset."
  value       = local.branch_length_regex
}

output "ruleset_id" {
  description = "ID of the created GitHub repository ruleset."
  value       = github_repository_ruleset.branch_name_max_length.ruleset_id
}
