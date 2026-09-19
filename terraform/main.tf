terraform {
  required_version = ">= 1.7.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Tenant = var.tenant_id, ManagedBy = "Terraform", Application = "Docurama" }
  }
}

data "aws_partition" "current" {}

locals {
  name = "docurama-${var.tenant_id}"
}

resource "aws_vpc" "tenant_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = local.name }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.tenant_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, 0)
  map_public_ip_on_launch = false
  availability_zone       = var.availability_zone
  tags                    = { Name = "${local.name}-host" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.tenant_vpc.id
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.tenant_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_kms_key" "tenant_cmek" {
  description             = "Docurama tenant ${var.tenant_id}: S3 documents and encrypted EBS"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  lifecycle { prevent_destroy = true }
}
resource "aws_kms_alias" "tenant" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.tenant_cmek.key_id
}

resource "aws_s3_bucket" "documents" {
  bucket        = var.document_bucket_name
  force_destroy = false
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule { object_ownership = "BucketOwnerEnforced" }
}
resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tenant_cmek.arn
    }
    bucket_key_enabled = true
  }
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.documents.arn, "${aws_s3_bucket.documents.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
  # Require explicit SSE-KMS headers: default encryption alone permits overrides.
  statement {
    sid       = "RequireKmsEncryption"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.documents.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }
  statement {
    sid       = "RequireTenantKey"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.documents.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [aws_kms_key.tenant_cmek.arn]
    }
  }
}
resource "aws_s3_bucket_policy" "documents" {
  bucket     = aws_s3_bucket.documents.id
  policy     = data.aws_iam_policy_document.bucket.json
  depends_on = [aws_s3_bucket_public_access_block.documents]
}

data "aws_iam_policy_document" "assume_host" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "host" {
  name               = "${local.name}-host"
  assume_role_policy = data.aws_iam_policy_document.assume_host.json
}
resource "aws_iam_instance_profile" "host" {
  name = "${local.name}-host"
  role = aws_iam_role.host.name
}
data "aws_iam_policy_document" "app" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.documents.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.documents.arn}/*"]
  }
  statement {
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.tenant_cmek.arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${var.aws_region}.${data.aws_partition.current.dns_suffix}"]
    }
    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:s3:arn"
      values   = [aws_s3_bucket.documents.arn, "${aws_s3_bucket.documents.arn}/*"]
    }
  }
}
resource "aws_iam_role_policy" "app" {
  name   = "tenant-documents"
  role   = aws_iam_role.host.id
  policy = data.aws_iam_policy_document.app.json
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.host.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_security_group" "tenant_sg" {
  name        = local.name
  description = "Tenant HTTPS allowlist; no SSH access"
  vpc_id      = aws_vpc.tenant_vpc.id
  ingress {
    description = "Approved browser networks"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_client_cidrs
  }
  ingress {
    description = "HTTP redirect for approved browser networks"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_client_cidrs
  }
  egress {
    description = "TLS APIs, SSM, registry and configured application providers"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  dynamic "egress" {
    for_each = var.smtp_egress_cidrs
    content {
      description = "Explicit SMTP relay allowlist"
      from_port   = var.smtp_port
      to_port     = var.smtp_port
      protocol    = "tcp"
      cidr_blocks = [egress.value]
    }
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.tenant_vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
      Resource  = [aws_s3_bucket.documents.arn, "${aws_s3_bucket.documents.arn}/*"]
    }]
  })
}

# Use an explicitly approved, pre-baked AMI. There is no download-and-execute user data.
resource "aws_instance" "host" {
  ami                     = var.host_ami_id
  instance_type           = var.instance_type
  subnet_id               = aws_subnet.public.id
  vpc_security_group_ids  = [aws_security_group.tenant_sg.id]
  iam_instance_profile    = aws_iam_instance_profile.host.name
  monitoring              = true
  disable_api_termination = true
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2 # Allow the container SDK's instance-role credential chain.
    instance_metadata_tags      = "disabled"
  }
  root_block_device {
    encrypted             = true
    kms_key_id            = aws_kms_key.tenant_cmek.arn
    volume_type           = "gp3"
    volume_size           = var.host_volume_gib
    delete_on_termination = false
  }
  tags       = { Name = local.name }
  depends_on = [aws_iam_role_policy.app, aws_iam_role_policy_attachment.ssm]
  lifecycle { prevent_destroy = true }
}
resource "aws_eip" "host" {
  domain     = "vpc"
  instance   = aws_instance.host.id
  depends_on = [aws_internet_gateway.igw]
}
resource "aws_route53_record" "portal" {
  count   = var.route53_zone_id == null ? 0 : 1
  zone_id = var.route53_zone_id
  name    = var.domain
  type    = "A"
  ttl     = 300
  records = [aws_eip.host.public_ip]
}
