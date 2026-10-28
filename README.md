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

For `repo:bahag-banasiks/DCCP-892:ref:refs/heads/<branch-name>`:
- Fixed prefix: `repo:bahag-banasiks/DCCP-892:ref:refs/heads/` = **44 bytes**
- Remaining budget for `<branch-name>`: `127 - 44` = **83 bytes**
- **83-char branch** $\rightarrow$ `sub` = **127 bytes** (Succeeds)
- **84-char branch** $\rightarrow$ `sub` = **128 bytes** (Fails in GCP STS with `google.subject` > 127 bytes if unblocked; blocked on `git push` when the GitHub Ruleset is active)

---

## One-Time Secret Setup

This repository contains no credentials, keys, or cloud resource identifiers. Configure the Workload Identity provider and service account as encrypted Actions secrets:

```bash
gh secret set WIF_PROVIDER --body 'projects/<project-number>/locations/global/workloadIdentityPools/<pool>/providers/<provider>'
gh secret set WIF_SERVICE_ACCOUNT --body '<service-account-email>'
```

---

## Step-by-Step Testing Guide

### 1. Test WIF Failure Without Active Ruleset (Optional Negative Control)

Before applying the ruleset (or with `TF_VAR_enforcement=evaluate`):

```bash
# Push an 83-char branch (sub = 127 bytes) -> GitHub Actions WIF succeeds!
./scripts/test-branches.sh push-83

# Push an 84-char branch (sub = 128 bytes) -> Git push succeeds, but GitHub Actions WIF fails (>127 bytes)!
./scripts/test-branches.sh push-84

# Clean up test branches
./scripts/test-branches.sh cleanup
```

### 2. Apply the Branch Length Ruleset via Terraform

```bash
cd terraform
export GITHUB_TOKEN="$(gh auth token)"
terraform init
terraform plan
terraform apply
```

This creates the `branch-name-max-length` ruleset using:
- `operator = "regex"`
- `pattern  = "^.{1,83}$"` (computed dynamically as `127 - length("repo:bahag-banasiks/DCCP-892:ref:refs/heads/")`)
- `negate   = false`

### 3. Verify the Ruleset Blocks Overlong Branches on `git push`

```bash
# 83-char branch -> Allowed by Ruleset AND succeeds in GCP WIF
./scripts/test-branches.sh push-83

# 84-char branch -> Rejected immediately by GitHub Ruleset (GH013: Repository rule violations found)
./scripts/test-branches.sh push-84
```

