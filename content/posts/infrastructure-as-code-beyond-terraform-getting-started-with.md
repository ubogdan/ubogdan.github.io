---
title: 'Infrastructure as Code Beyond Terraform: Getting Started with OpenTofu, Policy
  as Code, and Drift Detection'
date: 2026-04-11 19:16:12+02:00
tags:
- terraform
categories:
- DevOps
description: Set up a first OpenTofu workflow with remote state, automated plan reviews,
  and policy checks using OPA. Learn how to detect and remediate configuration drift
  in a team setting.
---

## Introduction

If your infrastructure lives in a cloud console, it lives in someone's memory. Infrastructure as Code (IaC) fixes that by putting changes in version control, where they can be reviewed, tested, and reproduced. For years Terraform was the default tool. Since HashiCorp's 2023 license change to the BSL, many teams have moved to **OpenTofu**, a Linux Foundation project that stays open source (MPL 2.0) and is a drop-in replacement for Terraform's core workflow.

Switching tools is the easy part. The harder part is what makes IaC safe for a team: **remote state** so everyone shares one source of truth, **automated plan reviews** so changes are visible before they land, **policy as code** so guardrails are enforced by machines rather than memory, and **drift detection** so manual console changes don't silently erode your declared configuration. A typical team that adds these four pieces cuts review time on routine changes and catches whole classes of misconfiguration (open SSH ports, missing ownership tags) before they reach production.

In this article, you'll build a first OpenTofu workflow with all four pieces, using AWS and GitHub Actions as the example stack.

## Prerequisites

- Basic familiarity with Terraform-style HCL (resources, variables, outputs)
- An AWS account (the free tier is enough) and the AWS CLI configured locally
- A GitHub repository you can add workflows to
- Git and a terminal
- Comfort reading JSON; no prior Rego (OPA's policy language) experience is needed

Install OpenTofu and verify:

```bash
# macOS
brew install opentofu

# Linux/Windows: see https://opentofu.org/docs/intro/install/
tofu version
```

> 💡 **Tip:** If you have existing Terraform projects, OpenTofu reads the same `.tf` files and state format for Terraform versions up to 1.5.x. Always run `tofu plan` after migrating and confirm it shows no changes before applying anything.

## Setting Up Your First OpenTofu Project

Start with a small, realistic layout:

```text
infra/
├── main.tf
├── backend.tf
├── variables.tf
├── policy/
│   └── main.rego
└── .github/workflows/
```

### A Minimal Configuration

```hcl
# main.tf
terraform {
  required_version = ">= 1.8.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      managed_by = "opentofu"
      owner      = var.owner
    }
  }
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "${var.owner}-artifacts-${var.environment}"
  tags = {
    owner = var.owner
  }
}
```

OpenTofu keeps the `terraform` block name for compatibility, so existing configurations keep working.

### Configuring Remote State

Local state files break down as soon as two people run `tofu apply`. Remote state with locking prevents concurrent writes and gives the team one shared view of reality.

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket       = "acme-tofu-state"
    key          = "prod/network/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true  # native S3 locking, OpenTofu 1.10+
  }
}
```

On versions before 1.10, use a DynamoDB table instead by setting `dynamodb_table = "tofu-locks"`.

Create the state bucket once, outside this configuration, with versioning enabled so you can recover from a corrupted state:

```bash
aws s3api create-bucket --bucket acme-tofu-state \
  --region eu-west-1 \
  --create-bucket-configuration LocationConstraint=eu-west-1
aws s3api put-bucket-versioning --bucket acme-tofu-state \
  --versioning-configuration Status=Enabled

tofu init
```

State often contains secrets such as database passwords. OpenTofu also offers **client-side state encryption** (since 1.7), which encrypts state before it leaves your machine. It's worth enabling for sensitive workloads.

## Automating Plan Reviews in CI

The goal is simple: **no one applies from a laptop**. Every change goes through a pull request, where the plan is generated automatically and posted for reviewers. Merging to `main` applies exactly what was reviewed.

```yaml
# .github/workflows/tofu.yml
name: tofu
on:
  pull_request:
    paths: ["infra/**"]
  push:
    branches: [main]

permissions:
  id-token: write      # OIDC to AWS, no long-lived keys
  contents: read
  pull-requests: write

jobs:
  plan:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: infra
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
        with:
          tofu_version: 1.8.5
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/tofu-plan
          aws-region: eu-west-1
      - run: tofu init -input=false
      - run: tofu fmt -check -recursive
      - run: tofu validate
      - run: tofu plan -input=false -out=tfplan
      - run: tofu show -json tfplan > plan.json
      - uses: actions/upload-artifact@v4
        with:
          name: plan
          path: infra/plan.json
```

A few details matter here:

- **OIDC federation** gives the job short-lived AWS credentials. No access keys are stored in GitHub secrets.
- The plan role should be **read-only** where possible. A separate `tofu-apply` role, usable only from `main`, performs changes.
- `tofu show -json` produces a machine-readable plan that policy tools can inspect in the next step.

> **Tip:** Use a GitHub Environment with required reviewers on the apply job. That gives you a human approval gate for production without extra tooling.

## Policy as Code with OPA

Code review catches many mistakes, but reviewers get tired. **Open Policy Agent (OPA)** lets you encode rules once and enforce them on every plan. We'll use **Conftest**, a thin wrapper that runs Rego policies against structured files like plan JSON.

### Writing Your First Policies

```rego
# policy/main.rego
package main

import rego.v1

taggable := {"aws_instance", "aws_s3_bucket", "aws_db_instance"}

# Rule 1: every taggable resource needs an owner tag
deny contains msg if {
    some rc in input.resource_changes
    rc.type in taggable
    not "delete" in rc.change.actions
    not rc.change.after.tags.owner
    msg := sprintf("%s is missing the required 'owner' tag", [rc.address])
}

# Rule 2: never open SSH to the world
deny contains msg if {
    some rc in input.resource_changes
    rc.type == "aws_vpc_security_group_ingress_rule"
    rc.change.after.cidr_ipv4 == "0.0.0.0/0"
    rc.change.after.from_port <= 22
    rc.change.after.to_port >= 22
    msg := sprintf("%s exposes SSH (port 22) to 0.0.0.0/0", [rc.address])
}

# Rule 3: guard against large destructive changes
deny contains msg if {
    deletes := [rc | some rc in input.resource_changes; "delete" in rc.change.actions]
    count(deletes) > 5
    msg := sprintf("Plan deletes %d resources (limit is 5); requires manual approval", [count(deletes)])
}
```

Run it locally against a plan:

```bash
tofu plan -out=tfplan
tofu show -json tfplan > plan.json
conftest test plan.json --policy policy/
```

A failing run looks like this:

```text
FAIL - plan.json - main - aws_s3_bucket.logs is missing the required 'owner' tag

1 test, 0 passed, 0 warnings, 1 failure, 0 exceptions
```

Add this step to the CI job, after `tofu show`:

```yaml
      - uses: open-policy-agent/setup-opa@v2
      - name: Install conftest
        run: |
          curl -sL https://github.com/open-policy-agent/conftest/releases/download/v0.56.0/conftest_0.56.0_Linux_x86_64.tar.gz | tar xz
          sudo mv conftest /usr/local/bin/
      - run: conftest test plan.json --policy ../policy/
```

> 💡 **Tip:** Start new rules in `warn` mode (use `warn contains msg if` instead of `deny`) for a week. This shows you how many existing resources would violate the rule before you start blocking merges.

## Detecting and Remediating Drift

**Drift** occurs when real infrastructure no longer matches your code or state. Typical causes: an engineer "temporarily" edits a security group during an incident, or an autoscaling tool changes a setting. The danger is that the next `tofu apply` will either silently revert the change or fail confusingly.

### Scheduled Drift Detection

The `-detailed-exitcode` flag makes `tofu plan` script-friendly: exit code `0` means no changes, `1` means error, and `2` means differences exist.

```yaml
# .github/workflows/drift.yml
name: drift-detection
on:
  schedule:
    - cron: "0 6 * * 1-5"   # weekdays at 06:00 UTC
  workflow_dispatch:

permissions:
  id-token: write
  contents: read
  issues: write

jobs:
  drift:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: infra
    steps:
      - uses: actions/checkout@v4
      - uses: opentofu/setup-opentofu@v1
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/tofu-plan
          aws-region: eu-west-1
      - run: tofu init -input=false
      - id: plan
        run: |
          set +e
          tofu plan -input=false -lock=false -detailed-exitcode -no-color > drift.txt
          echo "code=$?" >> "$GITHUB_OUTPUT"
      - name: Open issue on drift
        if: steps.plan.outputs.code == '2'
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh issue create --title "Drift detected in prod/network" \
            --body "$(head -c 60000 drift.txt)" --label drift
      - name: Fail on error
        if: steps.plan.outputs.code == '1'
        run: exit 1
```

Note `-lock=false`: a read-only drift check shouldn't block a teammate's real apply.

### Choosing a Remediation Strategy

When drift is found, the team has three options, and which one is right depends on intent:

1. **Revert the change.** The manual edit was wrong. Run the normal pipeline and `tofu apply` restores the declared state.
2. **Adopt the change.** The edit was legitimate (say, a hotfix that increased an instance size). Update the `.tf` files via pull request so code matches reality.
3. **Accept it in state only.** For harmless attribute changes, use `tofu apply -refresh-only` to update state without touching resources.

For resources created outside OpenTofu, use declarative `import` blocks so the import goes through review too:

```hcl
import {
  to = aws_s3_bucket.legacy_logs
  id = "acme-legacy-logs"
}
```

Run `tofu plan -generate-config-out=generated.tf` to have OpenTofu draft the matching resource block, then clean it up before committing.

## Best Practices

- **Split state by blast radius.** Separate state per environment and per layer (network, data, apps). A 40-resource state plans in seconds and limits the damage of a mistake.
- **Pin versions** of OpenTofu and providers, and commit `.terraform.lock.hcl`.
- **Use OIDC, not static keys,** and separate plan (read-only) and apply roles.
- **Review the plan, not just the diff.** Code that looks harmless can trigger a replacement of a database.
- **Keep policies in their own repo or directory with tests,** and version them like application code.
- **Restrict console access** with read-only default roles and break-glass procedures, so drift is the exception.
- **Tag everything** with `managed_by` and `owner` so unmanaged resources are easy to spot.

## Common Pitfalls

- **Committing state or `.tfvars` with secrets.** Add `*.tfstate*` and secret var files to `.gitignore`, and enable bucket encryption plus state encryption.
- **Applying a different plan than the one reviewed.** Re-planning at apply time can produce different results. Save the plan file (`-out`) and apply that artifact, or at minimum re-run policy checks.
- **Drift alerts nobody reads.** An ignored issue is worse than no check. Route alerts to a channel with an owner and a response-time expectation.
- **Policies that are too strict too early.** Blocking all merges on day one breeds workarounds. Roll out with `warn`, then `deny`.
- **Manual state surgery without backups.** Commands like `tofu state rm` are powerful. Rely on bucket versioning and run `tofu state pull > backup.tfstate` first.

## Real-World Use Cases

**Startup platform team (6 engineers).** Before adopting this workflow, two engineers overwrote each other's changes twice in one quarter. With S3 remote state, locking, and PR-based plans, collisions dropped to zero, and onboarding a new engineer took a day instead of a week.

**Fintech compliance.** An auditor requires proof that no database is publicly accessible. A Rego rule denying `publicly_accessible = true` on `aws_db_instance` is evaluated on every plan, and the CI logs serve as audit evidence.

**Multi-account enterprise.** A nightly drift job across 30 workspaces found that 4 had manual security group edits from incident response. Each produced a ticket, and 3 of the 4 were adopted into code, closing a recurring gap in postmortem follow-up.

## Performance Considerations

- **Plan time scales with resource count** because OpenTofu refreshes each resource. Past ~500 resources per state, plans can take several minutes. Splitting state is the best fix.
- **Parallelism:** `-parallelism=20` (default 10) can speed up large plans, but watch for API rate limits.
- **Cache providers** in CI with `TF_PLUGIN_CACHE_DIR` to avoid re-downloading 300+ MB AWS provider binaries.
- **Use `-refresh=false`** only for quick local iteration, never for drift detection, since refresh is exactly what finds drift.
- OPA evaluation is fast; typical plan JSON files are checked in well under a second.

## Testing Your Setup

Test at three levels:

**1. Static checks** run in seconds on every commit:

```bash
tofu fmt -check -recursive
tofu validate
```

**2. Policy unit tests** verify rules against sample plan fragments:

```rego
# policy/main_test.rego
package main

import rego.v1

test_missing_owner_tag_denied if {
    result := deny with input as {"resource_changes": [{
        "address": "aws_s3_bucket.x",
        "type": "aws_s3_bucket",
        "change": {"actions": ["create"], "after": {"tags": {}}}
    }]}
    count(result) == 1
}
```

```bash
opa test policy/ -v
```

**3. Configuration tests** with the built-in `tofu test` framework. Create `tests/bucket.tftest.hcl`:

```hcl
run "bucket_has_owner_tag" {
  command = plan

  variables {
    owner       = "platform"
    environment = "test"
  }

  assert {
    condition     = aws_s3_bucket.artifacts.tags["owner"] == "platform"
    error_message = "Bucket must carry the owner tag"
  }
}
```

Finally, **test drift detection deliberately**: change a tag in the console, trigger the drift workflow with `workflow_dispatch`, and confirm an issue appears.

## Conclusion

You now have the skeleton of a team-ready IaC practice built on open tooling. Key takeaways:

- **OpenTofu is a practical, open-source successor path** for Terraform workflows, with the same HCL and extra features like state encryption.
- **Remote state with locking** is the foundation for safe collaboration; split it by blast radius.
- **Plan on pull request, apply on merge** makes every infrastructure change reviewable and auditable.
- **OPA policies turn tribal knowledge into automated guardrails,** and rolling them out in warn mode first avoids friction.
- **Scheduled drift detection with clear remediation options** (revert, adopt, or refresh) keeps code and reality aligned.

## Additional Resources

- [OpenTofu Documentation](https://opentofu.org/docs/)
- [OpenTofu State Encryption Guide](https://opentofu.org/docs/language/state/encryption/)
- [Open Policy Agent: Policy Language (Rego)](https://www.openpolicyagent.org/docs/latest/policy-language/)
- [Conftest](https://www.conftest.dev/)
- [setup-opentofu GitHub Action](https://github.com/opentofu/setup-opentofu)
- [AWS: Configuring OIDC in GitHub Actions](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [TFLint](https://github.com/terraform-linters/tflint)