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

# Network Configuration (Auto-discover Default VPC and Subnets)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group for ECS Fargate Task
resource "aws_security_group" "ecs_sg" {
  name        = "finance-app-ecs-sg"
  description = "Allow inbound traffic on port 3000 for Finance App"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "NextJS/Hono App Port"
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

  tags = {
    Name = "finance-app-ecs-sg"
  }
}

# Elastic Container Registry (ECR) Repository
resource "aws_ecr_repository" "app" {
  name                 = "finance-app-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "finance-app-repo"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "app" {
  name = "finance-app-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "finance-app-cluster"
  }
}

# CloudWatch Log Group for container logging
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/finance-app"
  retention_in_days = 7
}

# IAM Execution Role (for pulling ECR images and pushing CloudWatch logs)
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "finance-app-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM Task Role (for runtime access to AWS services from the container)
resource "aws_iam_role" "ecs_task_role" {
  name = "finance-app-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# ECS Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = "finance-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256" # 0.25 vCPU (AWS Free Tier / Cost Optimization friendly)
  memory                   = "512" # 0.5 GB (AWS Free Tier / Cost Optimization friendly)
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "finance-app-container"
      image     = "${aws_ecr_repository.app.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
        }
      ]
      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
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

# ECS Service
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

  # Allow external deployments (CI/CD) without Terraform resetting the image tag
  lifecycle {
    ignore_changes = [task_definition]
  }
}

# Outputs
output "ecr_repository_url" {
  value       = aws_ecr_repository.app.repository_url
  description = "The URL of the ECR repository"
}

output "ecs_cluster_name" {
  value       = aws_ecs_cluster.app.name
  description = "The name of the ECS Cluster"
}

output "ecs_service_name" {
  value       = aws_ecs_service.app.name
  description = "The name of the ECS Service"
}
