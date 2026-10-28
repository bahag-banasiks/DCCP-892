locals {
  # GitHub OIDC branch subject format:
  # repo:<owner>/<repo>:ref:refs/heads/<branch>
  oidc_sub_prefix        = "repo:${var.repository_owner}/${var.repository_name}:ref:refs/heads/"
  oidc_sub_prefix_length = length(local.oidc_sub_prefix)

  # GCP Workload Identity Federation limit for google.subject is 127 bytes
  gcp_google_subject_limit = 127

  # Dynamic max branch length for this specific owner/repo
  calculated_max_branch_length = local.gcp_google_subject_limit - local.oidc_sub_prefix_length
  effective_max_branch_length  = coalesce(var.max_branch_length_override, local.calculated_max_branch_length)

  # Regex enforced by GitHub Ruleset branch_name_pattern (evaluated against short branch name without refs/heads/)
  branch_length_regex = "^.{1,${local.effective_max_branch_length}}$"
}

resource "github_repository_ruleset" "branch_name_max_length" {
  name        = "branch-name-max-length"
  repository  = var.repository_name
  target      = "branch"
  enforcement = var.enforcement

  conditions {
    ref_name {
      include = ["~ALL"]
      exclude = []
    }
  }

  rules {
    branch_name_pattern {
      name     = "Max branch name length (${local.effective_max_branch_length} chars) for GCP WIF google.subject <= 127 bytes"
      operator = "regex"
      pattern  = local.branch_length_regex
      negate   = false
    }
  }
}
