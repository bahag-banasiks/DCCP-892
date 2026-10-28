locals {
  # Note: For personal GitHub accounts, GitHub includes numeric @owner_id and @repo_id in OIDC sub:
  #   repo:bahag-banasiks@147695780/DCCP-892@1436820855:ref:refs/heads/<branch> (65-byte prefix -> max 62 chars)
  # For GitHub organizations ( without numeric IDs in sub ):
  #   repo:<org>/<repo>:ref:refs/heads/<branch>
  oidc_sub_prefix        = "repo:bahag-banasiks@147695780/DCCP-892@1436820855:ref:refs/heads/"
  oidc_sub_prefix_length = length(local.oidc_sub_prefix)

  # GCP Workload Identity Federation limit for google.subject is 127 bytes
  gcp_google_subject_limit = 127

  # Dynamic max branch length for this specific owner/repo
  calculated_max_branch_length = local.gcp_google_subject_limit - local.oidc_sub_prefix_length
  effective_max_branch_length  = coalesce(var.max_branch_length_override, local.calculated_max_branch_length)

  # 1) GitHub Enterprise Cloud metadata rule (branch_name_pattern regex):
  branch_length_regex = "^.{1,${local.effective_max_branch_length}}$"

  # 2) GitHub Free / Standard ruleset fallback using fnmatch '?' wildcards (matches any branch >= max_length + 1 chars):
  overlong_fnmatch_pattern = "refs/heads/${join("", [for _ in range(local.effective_max_branch_length + 1) : "?"])}*"
}

resource "github_repository_ruleset" "branch_name_max_length" {
  name        = "branch-name-max-length"
  repository  = var.repository_name
  target      = "branch"
  enforcement = var.enforcement

  conditions {
    ref_name {
      include = var.use_enterprise_metadata_rule ? ["~ALL"] : [local.overlong_fnmatch_pattern]
      exclude = []
    }
  }

  rules {
    creation = var.use_enterprise_metadata_rule ? false : true

    dynamic "branch_name_pattern" {
      for_each = var.use_enterprise_metadata_rule ? [1] : []
      content {
        name     = "Max branch name length (${local.effective_max_branch_length} chars) for GCP WIF google.subject <= 127 bytes"
        operator = "regex"
        pattern  = local.branch_length_regex
        negate   = false
      }
    }
  }
}

