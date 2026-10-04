mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
}
# Terraform 1.11 supports plan-time ARN overrides without simulated teardown.
# The sole AWS test provider above is mocked: no AWS calls or real resources.
override_resource {
  override_during = plan
  target          = aws_s3_bucket.documents
  values          = { arn = "arn:aws:s3:::docurama-blueprint-tests" }
}
override_resource {
  override_during = plan
  target          = aws_kms_key.tenant_cmek
  values          = { arn = "arn:aws:kms:eu-west-3:123456789012:key/12345678-1234-1234-1234-123456789012" }
}
variables {
  tenant_id            = "test"
  domain               = "sign.example.com"
  availability_zone    = "eu-west-3a"
  host_ami_id          = "ami-0123456789abcdef0"
  document_bucket_name = "docurama-blueprint-tests"
  allowed_client_cidrs = ["192.0.2.0/24"]
}
run "encrypted_isolated_blueprint" {
  command = plan
  assert {
    condition = jsondecode(aws_iam_role.host.assume_role_policy) == {
      Version   = "2012-10-17"
      Statement = [{ Effect = "Allow", Action = ["sts:AssumeRole"], Principal = { Service = "ec2.amazonaws.com" } }]
    }
    error_message = "Only EC2 may assume the application host role."
  }
  assert {
    condition     = aws_instance.host.root_block_device[0].encrypted && !aws_instance.host.root_block_device[0].delete_on_termination
    error_message = "Host data must be encrypted and survive termination."
  }
  assert {
    condition     = aws_instance.host.metadata_options[0].http_tokens == "required" && aws_instance.host.metadata_options[0].http_put_response_hop_limit == 2
    error_message = "Require IMDSv2 and allow container credential-chain access."
  }
  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.documents.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "Document storage must use SSE-KMS."
  }
  assert {
    condition     = aws_s3_bucket_versioning.documents.versioning_configuration[0].status == "Enabled"
    error_message = "Document versions must be retained."
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.documents.block_public_policy && aws_s3_bucket_public_access_block.documents.restrict_public_buckets
    error_message = "Bucket public access must be blocked."
  }
  assert {
    condition     = alltrue([for rule in aws_security_group.tenant_sg.ingress : rule.from_port == 80 || rule.from_port == 443])
    error_message = "Do not open SSH or application/database ports."
  }
  assert {
    condition = alltrue([for rule in aws_security_group.tenant_sg.ingress :
      toset(rule.cidr_blocks) == toset(var.allowed_client_cidrs)
    ])
    error_message = "Every browser ingress rule must preserve the approved CIDR allowlist."
  }
  assert {
    condition = length(jsondecode(aws_s3_bucket_policy.documents.policy).Statement) == 3 && alltrue([
      for statement in jsondecode(aws_s3_bucket_policy.documents.policy).Statement :
      statement.Effect == "Deny" && statement.Principal == "*" &&
      (statement.Sid == "DenyInsecureTransport" ? (
        statement.Action == ["s3:*"] &&
        statement.Resource == [aws_s3_bucket.documents.arn, "${aws_s3_bucket.documents.arn}/*"] &&
        statement.Condition == { Bool = { "aws:SecureTransport" = "false" } }
        ) : statement.Sid == "RequireKmsEncryption" ? (
        statement.Action == ["s3:PutObject"] && statement.Resource == ["${aws_s3_bucket.documents.arn}/*"] &&
        statement.Condition == { StringNotEquals = { "s3:x-amz-server-side-encryption" = "aws:kms" } }
        ) : statement.Sid == "RequireTenantKey" ? (
        statement.Action == ["s3:PutObject"] && statement.Resource == ["${aws_s3_bucket.documents.arn}/*"] &&
        statement.Condition == { StringNotEquals = { "s3:x-amz-server-side-encryption-aws-kms-key-id" = aws_kms_key.tenant_cmek.arn } }
      ) : false)
    ]) && toset([for statement in jsondecode(aws_s3_bucket_policy.documents.policy).Statement : statement.Sid]) == toset(["DenyInsecureTransport", "RequireKmsEncryption", "RequireTenantKey"])
    error_message = "Attached bucket policy must deny insecure transport, missing/wrong SSE-KMS and missing/wrong tenant key."
  }
  assert {
    condition = jsondecode(aws_iam_role_policy.app.policy) == {
      Version = "2012-10-17"
      Statement = [
        { Effect = "Allow", Action = ["s3:ListBucket", "s3:GetBucketLocation"], Resource = [aws_s3_bucket.documents.arn] },
        { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = ["${aws_s3_bucket.documents.arn}/*"] },
        {
          Effect = "Allow", Action = ["kms:Decrypt", "kms:GenerateDataKey"], Resource = [aws_kms_key.tenant_cmek.arn]
          Condition = {
            StringEquals = { "kms:ViaService" = "s3.eu-west-3.amazonaws.com" }
            StringLike   = { "kms:EncryptionContext:aws:s3:arn" = [aws_s3_bucket.documents.arn, "${aws_s3_bucket.documents.arn}/*"] }
          }
        }
      ]
    }
    error_message = "Attached application policy must allow only tenant object operations and S3-scoped tenant KMS use; no bucket creation or version deletion."
  }
  assert {
    condition = jsondecode(aws_vpc_endpoint.s3.policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect   = "Allow", Principal = "*"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [aws_s3_bucket.documents.arn, "${aws_s3_bucket.documents.arn}/*"]
      }]
    }
    error_message = "Endpoint policy must implicitly deny all operations and resources outside the tenant allowlist."
  }
}
run "reject_invalid_tenant" {
  command = plan
  variables { tenant_id = "../unsafe" }
  expect_failures = [var.tenant_id]
}
