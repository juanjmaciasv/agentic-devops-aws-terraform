variable "aws_region" {
  type        = string
  description = "AWS region for deployment"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Deployment environment"

  validation {
    condition     = contains(["devel", "stage"], var.environment)
    error_message = "environment must be one of: devel, stage."
  }
}

variable "app_name" {
  type        = string
  description = "Application name (also the container name)"
  default     = "rdicidr"
}

variable "container_image" {
  type        = string
  description = "Full ECR image URI including an immutable tag (git SHA). No default: a placeholder image can never run."
}

variable "container_port" {
  type        = number
  description = "Port the container listens on"
  default     = 80
}

variable "health_check_path" {
  type        = string
  description = "Health check endpoint path (served by nginx.conf)"
  default     = "/health"
}

variable "desired_count" {
  type        = number
  description = "Number of ECS tasks to run"
  default     = 2
}

variable "task_cpu" {
  type        = string
  description = "Fargate task CPU units"
  default     = "256"
}

variable "task_memory" {
  type        = string
  description = "Fargate task memory (MiB)"
  default     = "512"
}

variable "log_retention_days" {
  type        = number
  description = "CloudWatch Logs retention"
  default     = 14
}

variable "availability_zones" {
  type        = list(string)
  description = "AZs whose default subnets host the ALB and tasks"
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
