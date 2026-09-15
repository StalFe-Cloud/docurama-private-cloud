output "vpc_id" {
  value = aws_vpc.tenant_vpc.id
}

output "subnet_id" {
  value = aws_subnet.public.id
}

output "kms_key_arn" {
  value = aws_kms_key.tenant_cmek.arn
}

output "security_group_id" {
  value = aws_security_group.tenant_sg.id
}
