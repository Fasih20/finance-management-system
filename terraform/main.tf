terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS Region to deploy resources"
}

variable "app_url" {
  type        = string
  default     = "http://localhost:3002"
  description = "Public URL of the application (update after ALB/ECS IP is known)"
}

# Used to build SSM ARNs
data "aws_caller_identity" "current" {}

# ─── Network ─────────────────────────────────────────────────────────────────

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "ecs_sg" {
  name        = "finance-app-ecs-sg"
  description = "Allow inbound traffic on port 3000 for Finance App"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "NextJS App Port"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "finance-app-ecs-sg" }
}

# ─── ECR ─────────────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "app" {
  name                 = "finance-app-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "finance-app-repo" }
}

# ─── SSM Parameters ──────────────────────────────────────────────────────────
# Created with placeholder values. After `terraform apply`, populate real
# values via:
#   aws ssm put-parameter --name "/finance-app/<KEY>" \
#     --value "<real-value>" --type SecureString --overwrite

locals {
  ssm_prefix = "/finance-app"

  # These are injected at runtime via ECS secrets — sensitive values only.
  # Note: NEXT_PUBLIC_* vars are also baked into the Next.js build, so pass
  # them as Docker build-args too (--build-arg KEY=value).
  secret_params = toset([
    "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY",
    "CLERK_PUBLISHABLE_KEY",
    "CLERK_SECRET_KEY",
    "DATABASE_URL",
    "PLAID_CLIENT_TOKEN",
    "PLAID_SECRET_TOKEN",
    "LEMONSQUEEZY_STORE_ID",
    "LEMONSQUEEZY_PRODUCT_ID",
    "LEMONSQUEEZY_API_KEY",
    "LEMONSQUEEZY_WEBHOOK_SECRET",
    "AWS_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY",
    "GEMINI_API_KEY",
  ])
}

resource "aws_ssm_parameter" "secrets" {
  for_each = local.secret_params

  name  = "${local.ssm_prefix}/${each.key}"
  type  = "SecureString"
  value = "placeholder"

  # Terraform creates the parameter but never overwrites a real value you set
  lifecycle {
    ignore_changes = [value]
  }

  tags = { App = "finance-app" }
}

# ─── IAM ─────────────────────────────────────────────────────────────────────

resource "aws_iam_policy" "ssm_read" {
  name        = "finance-app-ssm-read"
  description = "Allow ECS execution role to read SecureString params for finance-app"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["ssm:GetParameters", "ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/finance-app/*"
      },
      {
        # Required to decrypt SecureString params encrypted with the AWS-managed SSM key
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:key/alias/aws/ssm"
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "finance-app-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ssm_read" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ssm_read.arn
}

resource "aws_iam_role" "ecs_task_role" {
  name = "finance-app-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# ─── ECS ─────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/finance-app"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "app" {
  name = "finance-app-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "finance-app-cluster" }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "finance-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "finance-app-container"
      image     = "${aws_ecr_repository.app.repository_url}:latest"
      essential = true

      portMappings = [{
        containerPort = 3000
        hostPort      = 3000
      }]

      # Non-sensitive config — safe to store as plain env vars
      environment = [
        { name = "NODE_ENV",                      value = "production" },
        { name = "NEXT_PUBLIC_CLERK_SIGN_IN_URL", value = "/sign-in" },
        { name = "NEXT_PUBLIC_CLERK_SIGN_UP_URL", value = "/sign-up" },
        { name = "NEXT_PUBLIC_APP_URL",           value = var.app_url },
        { name = "AWS_REGION",                    value = var.aws_region },
      ]

      # Secrets pulled from SSM at container startup — ECS decrypts and injects
      secrets = [
        for param in sort(tolist(local.secret_params)) : {
          name      = param
          valueFrom = aws_ssm_parameter.secrets[param].arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "finance-app-service"
  cluster         = aws_ecs_cluster.app.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# ─── Outputs ─────────────────────────────────────────────────────────────────

output "ecr_repository_url" {
  value       = aws_ecr_repository.app.repository_url
  description = "Push Docker images here"
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.app.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}

output "ssm_parameter_paths" {
  value       = [for p in aws_ssm_parameter.secrets : p.name]
  description = "Populate these with real values after terraform apply"
}
