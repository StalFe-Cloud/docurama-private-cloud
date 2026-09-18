# Docurama Private Cloud — Managed Single-Tenant VPC Blueprints

> **Docurama SAS** · 1 Rue Marguerin, 75014 Paris, France  
> **Target Environment:** Dedicated Customer Enclaves · Regulated Enterprises · 21 CFR Part 11 · Banking, Defense & Healthcare  
> **Cryptographic Standards:** PAdES (ETSI EN 319 142-1/-2), RFC 3161 TSA, SHA-256, RSA-2048/4096, Sigstore Rekor  
> **Compliance Frameworks:** eIDAS (Regulation EU 910/2014), GDPR (Regulation EU 2016/679), FDA 21 CFR Part 11, NIS2

---

## 1. Executive Summary

**Docurama Private Cloud** is an enterprise infrastructure automation suite designed to provision, configure, and operate completely isolated, single-tenant instances of the Docurama e-Signature and legal evidence platform within dedicated Virtual Private Clouds (VPCs) across AWS, Google Cloud, Microsoft Azure, or on-premises OpenStack/Proxmox clusters.

Unlike shared multi-tenant SaaS, Private Cloud delivers:
1. **Physical & Logical Compute Isolation:** Dedicated virtual machines / container enclaves per tenant with zero cross-tenant resource sharing.
2. **Customer-Managed Encryption Keys (CMEK):** Storage encryption keys generated and retained exclusively within customer Cloud KMS (AWS KMS, Google Cloud KMS, Azure Key Vault, or HashiCorp Vault).
3. **Dedicated Corporate FQDN:** Custom corporate hostname (e.g. `https://sign.acme-corp.eu`) terminated with enterprise-issued TLS certificates.
4. **Dedicated PKI & Qualified Timestamps (QTSA):** Private X.509 signing authorities, custom PKCS#12 hardware certificates, and enterprise-specific RFC 3161 TSA server bindings.
5. **Regulatory 21 CFR Part 11 Enclaves:** Hardened signature manifestations (printed name, UTC timestamp, signature meaning), mandatory biometric/password re-authentication challenges, and immutable append-only audit event ledgers.
6. **Dual Storage Architecture:** Run on high-speed NVMe block storage or connect directly to customer-owned S3 buckets (AWS S3, Ceph RGW, MinIO, or Apache-2.0 SeaweedFS) with full policy parity.
7. **Third-Party Witnessing & Evidence Packs:** Built-in transparency log hash chains with optional Sigstore Rekor witnessing and one-click `.zip` evidence pack exports with offline verifiers (`verify.html`).

---

## 2. Architecture & Topology

```
                  ┌─────────────────────────────────────────────────────────┐
                  │                 Client Web / Mobile Browser             │
                  └────────────────────────────┬────────────────────────────┘
                                               │ TLS 1.3 (Dedicated Domain)
                                               ▼
     ┌─────────────────────────────────────────────────────────────────────────────┐
     │                      Customer Dedicated Enclave / VPC                       │
     │                                                                             │
     │   ┌───────────────────────────────┐     ┌───────────────────────────────┐   │
     │   │   Edge Proxy (Nginx / Caddy)  │────▶│    Docurama Enterprise Core   │   │
     │   │   TLS Termination + Headers   │     │    Next.js 16 Standalone      │   │
     │   └───────────────────────────────┘     └──────────────┬────────────────┘   │
     │                                                        │                    │
     │             ┌───────────────────────────┬──────────────┴──────┬──────────┐  │
     │             ▼                           ▼                     ▼          │  │
     │   ┌───────────────────┐       ┌───────────────────┐ ┌─────────────┐      │  │
     │   │ Persistent SQLite │       │ S3 / CMEK Storage │ │ RFC 3161 TSA│      │  │
     │   │   / PostgreSQL    │       │ Scaleway / AWS /  │ │  & Rekor    │      │  │
     │   │  (Paris / Local)  │       │     SeaweedFS     │ │  Witnessing │      │  │
     │   └───────────────────┘       └───────────────────┘ └─────────────┘      │  │
     └─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Directory Structure

```
Docurama-Private-Cloud/
├── compose/
│   ├── docker-compose.vpc.yml     # Hardened single-tenant compose definition
│   ├── .env.tenant.template       # Environment configuration blueprint (CMEK, S3, TSA)
│   └── nginx.tenant.conf          # TLS termination & reverse proxy template
├── terraform/
│   ├── main.tf                    # Dedicated VPC, subnets, firewall rules, compute
│   ├── variables.tf               # Tenant parameters (CIDR, domain, region)
│   └── outputs.tf                 # Public IP, DNS records, endpoints
├── scripts/
│   ├── provision-tenant-vpc.sh    # Automated end-to-end tenant bootstrap
│   └── verify-compliance.sh       # Post-deployment validation script (health, transparency, TLS)
└── docs/
    ├── ARCHITECTURE.md            # Deep-dive architecture and threat model
    └── 21-CFR-PART-11.md          # FDA Part 11 validation & audit protocol
```

---

## 4. Deployment Workflow

```bash
# 1. Provision dedicated VPC and host infrastructure
cd terraform
terraform init
terraform apply -var="tenant_name=acme" -var="domain=sign.acme-corp.eu"

# 2. Bootstrap the tenant container enclave
cd ../scripts
chmod +x provision-tenant-vpc.sh verify-compliance.sh
./provision-tenant-vpc.sh acme sign.acme-corp.eu

# 3. Verify compliance, health, and cryptographic transparency
./verify-compliance.sh sign.acme-corp.eu
```

---

## 5. Security & Compliance Checklist

- [x] **eIDAS (Regulation EU 910/2014):** PAdES B-B to B-LTA signatures with RFC 3161 timestamps.
- [x] **FDA 21 CFR Part 11:** Signature manifestations, dual-factor authentication, and computer-generated audit trails.
- [x] **GDPR (Regulation EU 2016/679):** Isolated customer enclave with zero telemetry and EU data sovereignty.
- [x] **Customer-Managed Encryption Keys (CMEK):** Object storage encryption keys controlled via customer KMS.
- [x] **Sigstore Rekor Witnessing:** Neutral third-party log anchoring to publicly prove key authenticity.

---

*© 2026 Docurama SAS · 1 Rue Marguerin, 75014 Paris, France · All rights reserved.*
