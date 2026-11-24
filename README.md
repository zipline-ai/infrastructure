# Infrastructure
Configuration to Initialize Zipline Infrastructure

We are using OpenTofu to manage the infrastructure

## Onboarding with an AI agent

[`skills/zipline-onboarding/SKILL.md`](skills/zipline-onboarding/SKILL.md) walks an agent through a
customer deployment: minimal tfvars, `tofu apply`, `zipline admin install`, `zipline admin doctor`
and a first backfill. It writes `zipline-onboarding-report.md` with each step's status and any
blockers. To use it with Claude Code, copy the directory to `~/.claude/skills/` (or the
equivalent skills directory for another agent) and ask the agent to onboard Zipline.

## Zipline on GCP Steps

Initialize to gcloud and select the project you want to use
* ``` gcloud auth application-default login ```
* ``` gcloud init ```

Enter the zipline-gcp directory and initialize the infrastructure
* ``` cd zipline-gcp ```
* ``` tofu init ```
* ``` tofu apply ```
Fill in your company name as the customer_name variable and select the region you want to deploy to.


## Zipline on AWS Steps

Initialize to  and select the project you want to use
* ``` aws configure sso ```

Enter the AWS orchestration wrapper directory and initialize the infrastructure
* ``` cd aws/zipline-orchestration ```
* ``` ../../pull_crucible_config.sh aws ```
* ``` tofu init -reconfigure -backend-config=backend.hcl ```
* ``` tofu apply ```
Fill in your company name as the customer_name variable and select the region you want to deploy to.
