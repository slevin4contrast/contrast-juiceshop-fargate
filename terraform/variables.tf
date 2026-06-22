variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix applied to all resources."
  type        = string
  default     = "juice-shop-contrast"
}

variable "vpc_id" {
  description = "ID of an existing VPC to deploy into."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB (need an internet gateway)."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Subnets for the Fargate tasks. Use private subnets with a NAT gateway so the agent can reach Contrast; public subnets with assign_public_ip also work for a demo."
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Set true if tasks run in public subnets without a NAT gateway. The Contrast agent needs outbound HTTPS to reach the Contrast platform."
  type        = bool
  default     = false
}

variable "container_image" {
  description = "Full image URI for the instrumented Juice Shop image (for example <account>.dkr.ecr.<region>.amazonaws.com/juice-shop-contrast:latest). Defaults to the ECR repo created by this stack."
  type        = string
  default     = ""
}

# --- Contrast agent settings ---

variable "contrast_api_token" {
  description = "Contrast agent token (base64 string from Organization settings > Agent keys). Marked sensitive; passed once into Secrets Manager and never logged. Prefer setting via TF_VAR_contrast_api_token rather than a committed tfvars file."
  type        = string
  sensitive   = true
}

variable "contrast_application_name" {
  description = "Application name reported to Contrast (CONTRAST__APPLICATION__NAME)."
  type        = string
  default     = "juice-shop"
}

variable "contrast_server_name" {
  description = "Stable server name so churning Fargate tasks do not create many server records (CONTRAST__SERVER__NAME)."
  type        = string
  default     = "juice-shop-fargate"
}

variable "contrast_server_environment" {
  description = "Environment reported to Contrast. One of: DEVELOPMENT, QA, PRODUCTION."
  type        = string
  default     = "QA"
}

# --- Fargate sizing ---
# Note: the Contrast docs recommend DOUBLING memory when running Assess.
# 1 vCPU / 2 GB is a sensible starting point for an instrumented Juice Shop demo.

variable "task_cpu" {
  description = "Fargate task CPU units (1024 = 1 vCPU)."
  type        = number
  default     = 1024
}

variable "task_memory" {
  description = "Fargate task memory (MiB). Doubled vs. an uninstrumented app per Contrast guidance for Assess."
  type        = number
  default     = 2048
}

variable "desired_count" {
  description = "Number of running tasks."
  type        = number
  default     = 1
}
