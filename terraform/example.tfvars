# Reference only: copy to an ignored tenant.tfvars and replace placeholders.
tenant_id            = "acme"
domain               = "sign.acme.example"
aws_region           = "eu-west-3"
availability_zone    = "eu-west-3a"
host_ami_id          = "ami-00000000000000000" # Placeholder, never apply as supplied.
document_bucket_name = "replace-with-unique-tenant-bucket"
allowed_client_cidrs = ["192.0.2.0/24"] # Documentation-only network; replace.
# route53_zone_id = "YOUR_EXISTING_ZONE"
