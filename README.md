# Docurama Private Cloud — Managed Single-Tenant VPC Blueprints

**Target Environment:** Dedicated Customer Enclaves · Regulated Enterprises · 21 CFR Part 11 · Banking & Defense

---

## 1. Executive Summary

Docurama Private Cloud is an enterprise infrastructure suite designed to deploy and manage completely isolated, single-tenant instances of the Docurama eSignature and document execution engine within dedicated Virtual Private Clouds (VPCs).

Unlike public multi-tenant SaaS, Private Cloud provides:
1. **Physical & Logical Compute Isolation:** Dedicated virtual machines / container clusters per tenant.
2. **Customer-Managed Encryption Keys (CMEK):** Storage encryption keys managed in customer Cloud KMS (AWS KMS, Google Cloud KMS, Azure Key Vault, or HashiCorp Vault).
3. **Dedicated Corporate Domain:** Custom hostname (e.g. `https://sign.acme-corp.eu`) with enterprise SSL/TLS certificate.
4. **Dedicated PKI & Qualified Timestamps (QTSA):** Private X.509 signing authorities and enterprise-specific RFC 3161 TSA server connections.
5. **Regulatory Enclaves:** Automated 21 CFR Part 11 signature manifestations, biometric capture, and immutable append-only audit log sealing.

---

## 2. Directory Structure

```
Docurama-Private-Cloud/
├── compose/
│   ├── docker-compose.vpc.yml     # Hardened single-tenant compose definition
│   ├── .env.tenant.template       # Environment configuration blueprint
│   └── nginx.tenant.conf          # TLS termination & reverse proxy template
├── terraform/
│   ├── main.tf                    # Dedicated VPC, subnets, firewall rules, compute
│   ├── variables.tf               # Tenant parameters (CIDR, domain, region)
│   └── outputs.tf                 # Public IP, DNS records, endpoints
├── scripts/
│   ├── provision-tenant-vpc.sh    # Automated end-to-end tenant bootstrap
│   └── verify-compliance.sh       # Post-deployment validation script
└── docs/
    ├── ARCHITECTURE.md            # Deep-dive architecture and threat model
    └── 21-CFR-PART-11.md          # FDA Part 11 validation guide
```

---

## 3. Quick Deployment Workflow

```bash
# 1. Provision dedicated VPC and host infrastructure
cd terraform
terraform init
terraform apply -var="tenant_name=acme" -var="domain=sign.acme-corp.eu"

# 2. Bootstrap the tenant container enclave
cd ../scripts
./provision-tenant-vpc.sh --tenant acme --domain sign.acme-corp.eu

# 3. Verify compliance and live cryptographic sealing
./verify-compliance.sh --domain sign.acme-corp.eu
```
