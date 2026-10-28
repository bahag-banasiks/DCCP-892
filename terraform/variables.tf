variable "repository_owner" {
  description = "GitHub owner of the repository."
  type        = string
  default     = "bahag-banasiks"
}

variable "repository_name" {
  description = "Name of the repository."
  type        = string
  default     = "DCCP-892"

  # Example Terraform validation to cap repository name length so sufficient characters remain for branch names
  validation {
    condition     = length(var.repository_name) <= 50
    error_message = "repository_name must be at most 50 characters so that GitHub OIDC sub claims stay below GCP Workload Identity Federation's 127-byte google.subject limit."
  }
}

variable "enforcement" {
  description = "Ruleset enforcement level: 'active', 'evaluate', or 'disabled'."
  type        = string
  default     = "active"

  validation {
    condition     = contains(["active", "evaluate", "disabled"], var.enforcement)
    error_message = "enforcement must be one of: 'active', 'evaluate', 'disabled'."
  }
}

variable "max_branch_length_override" {
  description = "Optional static override for maximum branch name length. If null, calculated dynamically from the 127-byte GCP google.subject limit."
  type        = number
  default     = null
}

variable "use_enterprise_metadata_rule" {
  description = "Whether to use GitHub Enterprise Cloud 'branch_name_pattern' metadata rule (true for Enterprise orgs, false for personal GitHub Free accounts where metadata rules return HTTP 422)."
  type        = bool
  default     = false
}


