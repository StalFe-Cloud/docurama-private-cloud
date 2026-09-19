variable "aws_region" {
  description = "Approved AWS region."
  type        = string
  default     = "eu-west-3"
}
variable "tenant_id" {
  description = "Unique tenant identifier."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.tenant_id))
    error_message = "Use 2-31 lowercase letters, digits or hyphens, beginning with a letter."
  }
}
variable "domain" {
  description = "Approved fully qualified portal hostname."
  type        = string
  validation {
    condition     = can(regex("^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,63}$", var.domain))
    error_message = "Supply a fully qualified domain name."
  }
}
variable "vpc_cidr" {
  type    = string
  default = "10.100.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && can(cidrsubnet(var.vpc_cidr, 4, 0)) && try(tonumber(split("/", var.vpc_cidr)[1]) <= 24, false)
    error_message = "Supply an IPv4 VPC CIDR large enough for a host subnet."
  }
}
variable "availability_zone" {
  description = "Explicit AZ in aws_region with capacity for the selected instance."
  type        = string
}
variable "host_ami_id" {
  description = "Approved x86_64 Linux AMI with Docker Engine, Compose v2, SSM agent, Python 3, OpenSSL, curl, util-linux and bash installed."
  type        = string
  validation {
    condition     = can(regex("^ami-[0-9a-f]{17}$", var.host_ami_id))
    error_message = "Supply an approved regional AMI ID; the blueprint does not select an unverified image."
  }
}
variable "instance_type" {
  type    = string
  default = "t3.medium"
}
variable "host_volume_gib" {
  type    = number
  default = 100
  validation {
    condition     = var.host_volume_gib >= 30
    error_message = "At least 30 GiB is required."
  }
}
variable "document_bucket_name" {
  description = "Globally unique tenant bucket name; preserved against accidental destruction."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.document_bucket_name))
    error_message = "Use a valid 3-63 character lowercase S3 bucket name without dots."
  }
}
variable "allowed_client_cidrs" {
  description = "Explicit IPv4 browser ingress allowlist. A public portal requires a reviewed 0.0.0.0/0 entry."
  type        = list(string)
  validation {
    condition     = length(var.allowed_client_cidrs) > 0 && alltrue([for cidr in var.allowed_client_cidrs : can(cidrnetmask(cidr))])
    error_message = "Supply at least one valid IPv4 CIDR."
  }
}
variable "smtp_egress_cidrs" {
  description = "Optional IPv4 SMTP relay networks. HTTPS egress is already allowed."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for cidr in var.smtp_egress_cidrs : can(cidrnetmask(cidr))])
    error_message = "Supply valid IPv4 CIDRs."
  }
}
variable "smtp_port" {
  type    = number
  default = 465
  validation {
    condition     = contains([465, 587], var.smtp_port)
    error_message = "Use an authenticated TLS SMTP relay on port 465 or 587."
  }
}
variable "route53_zone_id" {
  description = "Optional existing public hosted zone; null means DNS is managed externally."
  type        = string
  default     = null
}
