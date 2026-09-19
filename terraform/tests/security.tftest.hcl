mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
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
}
run "reject_invalid_tenant" {
  command = plan
  variables { tenant_id = "../unsafe" }
  expect_failures = [var.tenant_id]
}
