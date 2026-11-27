# One-time, shared foundation for all environments. Applied locally by an
# admin (local state, gitignored). Creates: remote-state bucket, ECR repo,
# GitHub OIDC provider and a least-privilege deploy role for GitHub Actions.

terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "app_name" {
  type    = string
  default = "rdicidr"
}

variable "github_repo" {
  type        = string
  description = "owner/repo allowed to assume the deploy role"
  default     = "juanjmaciasv/agentic-devops-aws-terraform"
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = var.app_name, ManagedBy = "terraform", Stack = "bootstrap" }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  state_bucket = "${var.app_name}-tfstate-${local.account_id}"
}

# --- Remote state (S3 native locking, TF >= 1.10) ---

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "state_tls_only" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.state]
}

# --- Container registry (shared; images are promoted devel -> stage by SHA) ---

resource "aws_ecr_repository" "app" {
  name                 = var.app_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # challenge environment: allow clean teardown

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }
      action       = { type = "expire" }
    }]
  })
}

# --- GitHub Actions OIDC (no long-lived AWS keys in GitHub) ---

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_deploy" {
  name = "${var.app_name}-github-deploy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        # Only protected branches (deploy) and PRs (plan) of this repo
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            # deploy jobs run in GitHub environments -> sub is environment:<name>
            "repo:${var.github_repo}:environment:devel",
            "repo:${var.github_repo}:environment:stage",
            # PR plan jobs
            "repo:${var.github_repo}:pull_request",
          ]
        }
      }
    }]
  })
}

# Scoped to what the app stack manages; IAM limited to the app's own roles.
resource "aws_iam_role_policy" "github_deploy" {
  name = "deploy"
  role = aws_iam_role.github_deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TerraformState"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      },
      {
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
          "ecr:DescribeImages", "ecr:DescribeRepositories", "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid      = "AppInfra"
        Effect   = "Allow"
        Action   = ["ecs:*", "elasticloadbalancing:*", "logs:*", "ec2:Describe*", "ec2:*SecurityGroup*", "ec2:CreateTags", "ec2:DeleteTags", "cloudwatch:*"]
        Resource = "*"
      },
      {
        Sid    = "AppRolesOnly"
        Effect = "Allow"
        Action = [
          "iam:GetRole", "iam:CreateRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies", "iam:ListInstanceProfilesForRole", "iam:PassRole",
          "iam:UpdateAssumeRolePolicy",
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${var.app_name}-*-task-execution-role"
      },
      {
        Sid       = "EcsServiceLinkedRole"
        Effect    = "Allow"
        Action    = ["iam:CreateServiceLinkedRole"]
        Resource  = "*"
        Condition = { StringLike = { "iam:AWSServiceName" = ["ecs.amazonaws.com", "elasticloadbalancing.amazonaws.com"] } }
      },
    ]
  })
}

output "state_bucket" { value = aws_s3_bucket.state.bucket }
output "ecr_repository_url" { value = aws_ecr_repository.app.repository_url }
output "deploy_role_arn" { value = aws_iam_role.github_deploy.arn }
