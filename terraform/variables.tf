variable "aws_region" {
  description = "AWS Region for tenant deployment"
  type        = string
  default     = "eu-west-3" # Paris
}

variable "tenant_id" {
  description = "Unique alphanumeric identifier for the tenant (e.g. acme)"
  type        = string
  default     = "acme"
}

variable "domain" {
  description = "FQDN for the tenant portal (e.g. sign.acme-corp.eu)"
  type        = string
  default     = "sign.acme-corp.eu"
}

variable "vpc_cidr" {
  description = "Dedicated CIDR block for the tenant VPC"
  type        = string
  default     = "10.100.0.0/16"
}
