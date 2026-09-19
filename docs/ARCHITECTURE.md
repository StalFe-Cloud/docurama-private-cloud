# Architecture and security boundaries

An approved client network reaches the tenant's public Elastic IP on ports 80/443. Nginx redirects HTTP and terminates HTTPS using supplied certificates. The application has no published host port and runs on a private Docker bridge as UID/GID 10001. SQLite, portal/evidence identities stored in the database, and local operational files live on a KMS-encrypted EBS root volume. Document bytes use a private, versioned S3 bucket through a gateway VPC endpoint.

The host's instance profile grants only list/location and get/put/delete object operations in this tenant bucket, plus decrypt/data-key use of the tenant KMS key through S3 with the bucket encryption context. It cannot create buckets, alter policies or delete object versions. AWS Systems Manager's managed core policy separately supplies host administration. No SSH key or port is configured. Require IMDSv2; metadata hop limit 2 permits the container AWS credential chain. Every process able to reach instance metadata on this host can obtain that role; do not co-host untrusted workloads.

S3 blocks public access, disables ACLs, versions objects, requires HTTPS and rejects uploads without explicit SSE-KMS using this exact KMS ARN. Bucket defaults also specify the key. S3 bucket keys are enabled; IAM allows the bucket and object encryption contexts. Existing objects would require a separate audited migration to prove encryption parity; this repository creates a fresh bucket.

KMS rotation is enabled and deletion has a 30-day waiting period. Terraform protects key, bucket and host from destruction; EC2 termination protection is enabled and EBS is retained on termination. These measures prevent some accidental loss but are not backup, object lock, immutable audit storage or disaster recovery.

Ingress is an explicit IPv4 allowlist. HTTPS egress permits registries, SSM and configured APIs; SMTP egress requires an explicit CIDR list. AWS's VPC DNS resolver is used. The S3 gateway endpoint policy permits only this bucket's operations. This is not an air-gapped system or proof of region-confined outbound data. Public Rekor witnessing is disabled. Review all application integrations and outbound destinations before making confidentiality or residency claims.

The supplied host is one VM in one AZ, with standard EC2 tenancy. There is no physical-host exclusivity, load balancer, multi-AZ database, autoscaling or automated failover. The AMI is operator-approved and supplied explicitly. Application bootstrapping is separate from infrastructure provisioning; no passwords, certificates or image credentials are embedded in Terraform state or EC2 user data.

AWS implementation references:

- [S3 SSE-KMS and request encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/specifying-kms-encryption.html)
- [S3 policy examples for transport and encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-bucket-policies.html)
- [Terraform AWS instance metadata and encrypted block devices](https://registry.terraform.io/providers/hashicorp/aws/5.100.0/docs/resources/instance)
