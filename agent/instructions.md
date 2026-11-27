# Agentic DevOps (AWS + Terraform) Coding Challenge

***FSL Version: V1.0.0***

📌 **Important: Recordings must be submitted in MP4 format through a public Google Drive link.**

- Record your **entire screen (with system clock visible)**
- Start recording **after the environment and agent setup**
- Aim for 60 minutes or less; this is the ideal length. Going over 60 may reduce your score. **Going over 90 minutes is an automatic disqualification:** the challenge will not be reviewed, and you will not move forward in the process.
- The recording must be **one continuous take** — no pauses, edits, or interruptions
- **Do not use external resources** (e.g., StackOverflow, blogs). Official documentation is allowed
- Explain your thinking and decisions as you work

Useful:

- Example recording: React Challenge

---

### Technologies

This challenge is built around the following technology stack:

- **Terraform** — infrastructure provisioning for AWS resources
- **AWS** — ECS Fargate deployment with ALB and ECR
- **GitHub Actions** — CI/CD pipeline configuration
- **Docker** — containerization of the React application

- AI coding tools (e.g., Claude Code, GitHub Copilot, Codex, or similar)

---

<aside>
⚠️

**Note on Using Cloud Providers**

This challenge may involve using third-party cloud platforms such as AWS, Azure, or Google Cloud. You **may be asked to add a credit card** to activate a free-tier or trial account, although **you should not be charged** under normal use. We recommend reviewing each provider’s current free-tier policy directly:

- AWS Free Tier
- Azure Free Account
- Google Cloud Free Tier
</aside>

---

## AI Agentic Expectations

You must use AI as the **primary engineer, not just an assistant.**

- **Prompt the AI to diagnose** the issues present in the CI pipeline and Terraform infrastructure configuration
- **Have the AI propose and explain fixes** for each defect found
- **Create agents or workflows** that autonomously investigate, validate, and apply corrections
- **Guide and iterate** through prompts rather than manually editing configuration files
- **Use this <u>prompt</u> as your first message** when starting your project. Interaction logs must be included in the submitted zip file.

We evaluate how effectively you guide AI—not how much code you write manually. Most of the implementation (≈80%+) should be AI-generated.

---

# Setup

You can clone the challenge repository to your local machine with the following command:

{GITHUB-TOKEN}:  `<REDACTED: provide via GH_CHALLENGE_TOKEN env var>`

```bash
git clone https://{GITHUB-TOKEN}@github.com/fullstacklabs/assessment-cc-agentic-devops-aws-terraform-sr-01 --branch v1.0.0
```

---

# What to Expect

The repository you have cloned contains a **partially broken codebase**. Your challenge is not to build from scratch, but to **identify, explain, and fix the issues** present across the CI/CD pipeline and the Terraform infrastructure configuration.

There are issues seeded across two areas:

- The **GitHub Actions CI pipeline** contains defects that cause one or more pipeline steps to fail
- The **Terraform configuration** for AWS infrastructure contains defects that prevent the application from deploying or serving traffic correctly

As you work through each issue, narrate your process clearly. Describe what you observe, what you believe the root cause is, and why your fix addresses it. This narration is as important to the assessment as the fix itself.

---

# FSL DevOps Challenge: Part 1

## **Continuous Integration (CI)**

The repository includes a pre-configured GitHub Actions CI pipeline at `.github/workflows/ci.yaml`. The pipeline is intended to be triggered on any pull request created or updated in the repository, and should run the following steps in order:

1. **Install dependencies**: `npm install`
2. **Lint (ESLint)**: `npm run lint`
3. **Test (Jest)**: `CI=true npm run test`
4. **Build**: `npm run build`

**Your task is to:**

1. Push the repository to your own GitHub account and open a pull request to trigger the pipeline
2. Observe the pipeline output and identify all defects causing steps to fail
3. Fix each defect and verify the full pipeline passes
4. Provide at least one PR showing a **failed pipeline run** and one showing a **fully passing run**, so the progression is visible

### Requirements

- All four pipeline steps must pass cleanly on the final PR
- Each job must only run if its upstream dependency has succeeded
- The pipeline must trigger correctly for PRs from appropriately named branches
- Narrate each failure as you encounter it: what the output tells you, what you believe caused it, and what you are changing to fix it

---

# FSL DevOps Challenge: Part 2

## Continuous Deployment (CD) with Terraform and AWS

The repository includes a Terraform configuration under the `terraform/` directory. It is intended to provision an ECS Fargate deployment on AWS, with the application placed behind an Application Load Balancer (ALB) and health checking enabled.

The configuration is syntactically valid — `terraform validate` will pass — but contains defects that will prevent the infrastructure from functioning correctly once applied.

**Your task is to:**

1. Review the Terraform configuration and identify all defects before or during `terraform apply`
2. Fix each defect and successfully deploy the application to AWS
3. Confirm the application is publicly accessible via the ALB DNS name output by Terraform
4. Ensure the application's health check is passing and the ECS service is running stably

### Environment Setup

The Terraform configuration supports two isolated environments. Provision at minimum the **`devel`** environment:

- Development (`devel`)
- Staging (`stage`)

### Branching Strategy

Maintain the following branch structure in your repository throughout the challenge:

- All new work must be done in `feature/` or `bugfix/` branches branched from `devel`
- Changes merge into `devel` via PR only — no direct pushes
- Only `devel` may merge into `stage` — no other branches may merge directly into `stage`
- Direct pushes to `devel` or `stage` are prohibited

### Deployment Requirements

1. The application must be accessible to anyone with internet access during the challenge recording period
2. The ECS service must be running with healthy targets registered to the ALB
3. The health check must be passing consistently — not intermittently

---

### **⚠️ Generation of the Zip file**

After finishing the challenge and reviewed all is working

1. Remove unnecessary files/folders (e.g. `node_modules`) 
2. ZIP your entire project folder — make sure no files are missing, including folders like `.chat-history`