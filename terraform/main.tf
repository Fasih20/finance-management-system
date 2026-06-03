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
  type    = string
  default = "us-east-1"
}

# Set this to your registered domain after you buy one via Route 53.
# Leave empty on the very first apply — use alb_dns_name output instead.
variable "domain_name" {
  type        = string
  default     = ""
  description = "e.g. financeapp.click — leave empty until domain is registered"
}

# ─── Network ─────────────────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ALB security group — open 80 to the internet
resource "aws_security_group" "alb_sg" {
  name        = "finance-app-alb-sg"
  description = "Allow HTTP from internet to ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "finance-app-alb-sg" }
}

# ECS security group — only accept traffic from ALB
resource "aws_security_group" "ecs_sg" {
  name        = "finance-app-ecs-sg"
  description = "Allow port 3000 from ALB only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "finance-app-ecs-sg" }
}

# ─── ALB ─────────────────────────────────────────────────────────────────────

resource "aws_lb" "app" {
  name               = "finance-app-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids

  tags = { Name = "finance-app-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = "finance-app-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }

  tags = { Name = "finance-app-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ─── Route 53 (only created when domain_name is set) ─────────────────────────

data "aws_route53_zone" "main" {
  count = var.domain_name != "" ? 1 : 0
  name  = var.domain_name
}

resource "aws_route53_record" "app" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
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

locals {
  ssm_prefix = "/finance-app"

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

  lifecycle {
    ignore_changes = [value]
  }

  tags = { App = "finance-app" }
}

# ─── IAM ─────────────────────────────────────────────────────────────────────

resource "aws_iam_policy" "ssm_read" {
  name = "finance-app-ssm-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameters", "ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/finance-app/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"
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

      environment = [
        { name = "NODE_ENV",                      value = "production" },
        { name = "NEXT_PUBLIC_CLERK_SIGN_IN_URL", value = "/sign-in" },
        { name = "NEXT_PUBLIC_CLERK_SIGN_UP_URL", value = "/sign-up" },
        { name = "AWS_REGION",                    value = var.aws_region },
        # NEXT_PUBLIC_APP_URL is baked into the Docker image at build time via
        # GitHub Actions secret — not set here to avoid task definition churn.
      ]

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

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "finance-app-container"
    container_port   = 3000
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_lb_listener.http]
}

# ─── Outputs ─────────────────────────────────────────────────────────────────

output "alb_dns_name" {
  value       = "http://${aws_lb.app.dns_name}"
  description = "Use this as NEXT_PUBLIC_APP_URL until you have a domain"
}

output "app_url" {
  value       = var.domain_name != "" ? "http://${var.domain_name}" : "http://${aws_lb.app.dns_name}"
  description = "Public URL of the application"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
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
