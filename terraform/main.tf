terraform {
  required_version = ">= 1.5.0"
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

# Dedicated VPC
resource "aws_vpc" "tenant_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name   = "docurama-vpc-${var.tenant_id}"
    Tenant = var.tenant_id
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.tenant_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, 0)
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = {
    Name = "docurama-subnet-public-${var.tenant_id}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.tenant_vpc.id

  tags = {
    Name = "docurama-igw-${var.tenant_id}"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.tenant_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "docurama-rt-${var.tenant_id}"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Dedicated Customer-Managed Encryption Key (CMEK)
resource "aws_kms_key" "tenant_cmek" {
  description             = "Dedicated Docurama CMEK for tenant ${var.tenant_id}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Tenant = var.tenant_id
  }
}

# Security Group
resource "aws_security_group" "tenant_sg" {
  name        = "docurama-sg-${var.tenant_id}"
  description = "Allow inbound HTTPS and SSH allowlist"
  vpc_id      = aws_vpc.tenant_vpc.id

  ingress {
    description = "HTTPS from anywhere (or restricted allowlist)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP to HTTPS redirect"
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

  tags = {
    Name = "docurama-sg-${var.tenant_id}"
  }
}
