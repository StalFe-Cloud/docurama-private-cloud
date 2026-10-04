# Keep policy construction independent of provider data mocks so offline plans
# assert the exact documents attached to resources, rather than canned JSON.
locals {
  host_trust_policy = {
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole"]
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  }
  bucket_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Action    = ["s3:*"]
        Resource  = [aws_s3_bucket.documents.arn, "${aws_s3_bucket.documents.arn}/*"]
        Principal = "*"
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "RequireKmsEncryption"
        Effect    = "Deny"
        Action    = ["s3:PutObject"]
        Resource  = ["${aws_s3_bucket.documents.arn}/*"]
        Principal = "*"
        Condition = { StringNotEquals = { "s3:x-amz-server-side-encryption" = "aws:kms" } }
      },
      {
        Sid       = "RequireTenantKey"
        Effect    = "Deny"
        Action    = ["s3:PutObject"]
        Resource  = ["${aws_s3_bucket.documents.arn}/*"]
        Principal = "*"
        Condition = { StringNotEquals = { "s3:x-amz-server-side-encryption-aws-kms-key-id" = aws_kms_key.tenant_cmek.arn } }
      }
    ]
  }
  application_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [aws_s3_bucket.documents.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.documents.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = [aws_kms_key.tenant_cmek.arn]
        Condition = {
          StringEquals = { "kms:ViaService" = "s3.${var.aws_region}.${data.aws_partition.current.dns_suffix}" }
          StringLike   = { "kms:EncryptionContext:aws:s3:arn" = [aws_s3_bucket.documents.arn, "${aws_s3_bucket.documents.arn}/*"] }
        }
      }
    ]
  }
  endpoint_policy = {
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
      Resource  = [aws_s3_bucket.documents.arn, "${aws_s3_bucket.documents.arn}/*"]
    }]
  }
}
