output "vpc_id" { value = aws_vpc.tenant_vpc.id }
output "subnet_id" { value = aws_subnet.public.id }
output "security_group_id" { value = aws_security_group.tenant_sg.id }
output "kms_key_arn" { value = aws_kms_key.tenant_cmek.arn }
output "document_bucket_name" { value = aws_s3_bucket.documents.id }
output "instance_id" { value = aws_instance.host.id }
output "public_ip" { value = aws_eip.host.public_ip }
output "portal_url" { value = "https://${var.domain}" }
output "application_role_arn" { value = aws_iam_role.host.arn }
output "bootstrap_environment" {
  description = "Non-secret values to copy into the deployment environment; image digests and TLS must be supplied separately."
  value = {
    TENANT_ID                    = var.tenant_id
    DOMAIN                       = var.domain
    S3_BUCKET                    = aws_s3_bucket.documents.id
    S3_REGION                    = var.aws_region
    S3_CREDENTIALS_MODE          = "default"
    S3_AUTO_CREATE_BUCKET        = "0"
    S3_SSE_KMS_KEY_ID            = aws_kms_key.tenant_cmek.arn
    DOCURAMA_DEPLOYMENT_MODE     = "private_cloud"
    DOCURAMA_PUBLIC_REGISTRATION = "false"
    REKOR_WITNESS                = "off"
  }
}
