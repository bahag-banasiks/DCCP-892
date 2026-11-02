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

---

## Datadog to GitHub Actions kill-switch test

The [Datadog test workflow](.github/workflows/datadog-chatbot-kill-switch-test.yml)
accepts `workflow_dispatch` events only. It has no repository permissions, cloud
credentials, checkout, or deployment steps. It validates its inputs and writes a
simulated `chatbot_enabled=false` result to the run summary. It never stops a
service or re-enables a chatbot.

### 1. Configure a restricted GitHub credential

Create a fine-grained GitHub personal access token owned by an account with access
to `bahag-banasiks/DCCP-892`. Select only this repository and grant repository
**Actions: Read and write** permission. Set an expiration. Store the token directly
in a Datadog connection, never in the workflow, its inputs, or this repository.

### 2. Create the Datadog HTTP connection

In Datadog, open **Workflow Automation > Connections > New Connection**:

- Select **HTTP** and name it `github-dccp-892-test`.
- Set the authentication base URL to `https://api.github.com`.
- Select **Token Auth**, with token name `githubToken` and your token as its value.
- Configure the connection's request header `Authorization` to
  `Bearer {{ githubToken }}`. Token Auth does not automatically add the header.
- Restrict connection editing and grant Resolver access only to the workflow's
  execution identity.

See [Datadog HTTP connection documentation](https://docs.datadoghq.com/actions/connections/http/).

### 3. Create and test the Datadog automation

Create a workflow named `DCCP-892 chatbot kill-switch test` in
**Workflow Automation**. Add a **Monitor** trigger and connect it to an
**HTTP > Make request** step using `github-dccp-892-test`.

Configure the step as follows:

- Method: `POST`
- URL:
  `https://api.github.com/repos/bahag-banasiks/DCCP-892/actions/workflows/datadog-chatbot-kill-switch-test.yml/dispatches`
- Header `Accept`: `application/vnd.github+json`
- Header `X-GitHub-Api-Version`: `2022-11-28`
- Header `Content-Type`: `application/json`
- JSON body:

  ```json
  {
    "ref": "main",
    "inputs": {
      "monitor_id": "manual-test",
      "alert_state": "ALERT"
    }
  }
  ```

Run the Datadog workflow manually first. GitHub normally returns HTTP **204** for
an accepted dispatch; acceptance does not mean the GitHub job has completed.
Check the GitHub Actions run and its summary:

<https://github.com/bahag-banasiks/DCCP-892/actions/workflows/datadog-chatbot-kill-switch-test.yml>

Verify that the run succeeds and reports **SIMULATION ONLY**. HTTP errors must
fail the Datadog step; do not suppress them or treat them as successful shutdowns.

### 4. Attach it to a test monitor only

After the manual test succeeds:

1. Add a string workflow input named `monitor_id` (default `manual-test`).
2. Replace `manual-test` in the HTTP body with the workflow input using Datadog's
   variable picker.
3. Keep `alert_state` fixed to `ALERT`. Enable automatic triggering for the Monitor
   trigger, save, and publish the workflow.
4. Edit a non-production monitor, select **Add Workflow**, select this workflow,
   and configure its `monitor_id` input as `{{id}}`.
5. Keep the generated workflow mention inside an alert-only block:

   ```text
   {{#is_alert}}
   @workflow-YOUR-GENERATED-HANDLE(monitor_id="{{id}}")
   {{/is_alert}}
   ```

   Use the actual mention generated by Datadog, not the placeholder above. Do not
   add it outside the block or to recovery, warning, or no-data notifications.
6. Trigger the test monitor and verify both the Datadog execution and the GitHub
   run with its numeric monitor ID. Repeated alerts may create additional harmless
   runs; recovery must not dispatch a run.

See [Datadog monitor triggers](https://docs.datadoghq.com/actions/workflows/trigger/#monitor-triggers).
Published workflow executions may incur Datadog charges.

### Production considerations

This tests dispatch and input validation, not a real kill switch. For production,
use a backend-enforced, idempotent "set disabled" operation, authenticate it with
least privilege, verify the disabled state, and notify on failure. Start with
manual re-enablement. GitHub runner queuing and monitor evaluation delays make
this unsuitable for an instantaneous circuit breaker.
