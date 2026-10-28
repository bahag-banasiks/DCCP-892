# DCCP-892 — GCP Workload Identity Federation `google.subject` 127-Byte Limit & GitHub Rulesets PoC

## Problem Statement

When authenticating from GitHub Actions to GCP via Workload Identity Federation (WIF), `google.subject` is mapped to `assertion.sub`:

```hcl
"google.subject" = "assertion.sub"
```

For branch pushes (without a job `environment`), GitHub sets `sub` to:

```text
repo:<owner>/<repo-name>:ref:refs/heads/<branch-name>
```

GCP enforces a hard maximum length of **127 bytes** on `google.subject`.

### Length Math

1. **GitHub Organizations (`repo:<org>/<repo-name>:ref:refs/heads/<branch-name>`)**:
   - Fixed characters: `repo:<org>/` + `:ref:refs/heads/`
   - For a 5-char org name, fixed overhead is **27 bytes**, leaving **`length(repo_name) + length(branch_name) <= 100 bytes`**.
2. **Personal GitHub Accounts (`bahag-banasiks/DCCP-892`)**:
   - For personal accounts, GitHub includes numeric owner and repo IDs in `sub`:
     `repo:bahag-banasiks@147695780/DCCP-892@1436820855:ref:refs/heads/<branch-name>`
   - Fixed prefix: `repo:bahag-banasiks@147695780/DCCP-892@1436820855:ref:refs/heads/` = **65 bytes**
   - Remaining budget for `<branch-name>`: `127 - 65` = **62 bytes**
   - **62-char branch** $\rightarrow$ `sub` = **127 bytes** (**Succeeds** in GCP WIF)
   - **63-char branch** $\rightarrow$ `sub` = **128 bytes** (**Fails** in GCP STS with: `The size of mapped attribute google.subject exceeds the 127 bytes limit`)

---

## One-Time Secret Setup

This repository contains no credentials, keys, or cloud resource identifiers. Configure the Workload Identity provider and service account as encrypted Actions secrets:

```bash
gh secret set WIF_PROVIDER --body 'projects/<project-number>/locations/global/workloadIdentityPools/<pool>/providers/<provider>'
gh secret set WIF_SERVICE_ACCOUNT --body '<service-account-email>'
```

---

## Two Ruleset Modes in `terraform/`

1. **GitHub Enterprise Cloud Organization (`use_enterprise_metadata_rule = true`)**:
   Uses `rules.branch_name_pattern` with:
   - `operator = "regex"`
   - `pattern  = "^.{1,<max_length>}$"`
   - `negate   = false`
   *(Note: GitHub gates metadata pattern rules like `branch_name_pattern` and `commit_message_pattern` behind GitHub Enterprise Cloud; on personal GitHub Free accounts, the API returns `HTTP 422 Invalid rule 'branch_name_pattern'`).*

2. **Personal GitHub Free Account Fallback (`use_enterprise_metadata_rule = false`, default in this PoC)**:
   Uses `conditions.ref_name.include = ["refs/heads/???...*"]` (`max_length + 1` single-char `?` wildcards followed by `*`) with `rules.creation = true` to block creating single-segment branches longer than `max_length`.

---

## Step-by-Step Testing Guide

### 1. Apply the Branch Length Ruleset via Terraform

```bash
cd terraform
export GITHUB_TOKEN="$(gh auth token)"
terraform init
terraform plan
terraform apply
```

### 2. Verify the Ruleset & WIF Boundary

```bash
# 62-char branch (sub = 127 bytes) -> Allowed by Ruleset AND succeeds in GCP WIF
./scripts/test-branches.sh push-ok

# 63-char branch (sub = 128 bytes) -> Rejected immediately by GitHub Ruleset (GH013: Repository rule violations found)
./scripts/test-branches.sh push-too-long

# Clean up test branches
./scripts/test-branches.sh cleanup
```

