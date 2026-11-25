# Docurama Private Cloud

AWS infrastructure and host-configuration blueprints for dedicated customer application deployment.

* **Repository:** [https://github.com/StalFe-Cloud/docurama-private-cloud](https://github.com/StalFe-Cloud/docurama-private-cloud)
* **Corporate Entity & Manufacturer:** Docurama is a flagship product engineered and operated by **VOIRIA** (**VOIRIA SASU** · 1 Rue Marguerin, 75014 Paris, France · SIREN 131 914 012 · R.C.S. Paris · TVA FR90131914012).
* **Part of the [StalFe Cloud](https://github.com/StalFe-Cloud) Ecosystem:**
  * [Docurama Cloud (SaaS)](https://github.com/StalFe-Cloud/docurama) — Public cloud multi-tenant platform.
  * [Docurama Enterprise](https://github.com/StalFe-Cloud/docurama-enterprise) — Sovereign on-premises and self-hosted edition.
  * [Docurama Private Cloud](https://github.com/StalFe-Cloud/docurama-private-cloud) — Dedicated AWS tenant VPC infrastructure blueprints.

The blueprint provisions an isolated VPC, allowlisted HTTP/HTTPS ingress, an EC2 host administered with AWS Systems Manager, a persistent encrypted root volume, and a private versioned S3 document bucket. One tenant KMS key protects EBS and S3. Application IAM permissions are scoped to that bucket and key. The Compose application runs as UID/GID 10001 with SQLite on EBS and document bytes in S3.

No deployment has been performed as part of this remediation. Terraform mocked resource assertions and local script tests do not validate a customer's actual AWS permissions, AMI, release image, backups or application behavior.

## Required release contract

Before deploying, obtain approved, accessible digest references for **both** the Enterprise application and nginx. No release digest is supplied or invented in this repository. The application image must include:

- Runtime enforcement of `DOCURAMA_DEPLOYMENT_MODE=private_cloud` and `DOCURAMA_PUBLIC_REGISTRATION=false`.
- `S3_CREDENTIALS_MODE=default` using the EC2 role, `S3_AUTO_CREATE_BUCKET=0`, and explicit `S3_SERVER_SIDE_ENCRYPTION=aws:kms` / `S3_SSE_KMS_KEY_ID` support.
- Startup that fails on unsuccessful database initialization, without automatic acceptance of destructive schema changes.
- The offline `bun /app/bootstrap-admin.js --empty-installation` operator command bundled in the container and its runtime dependencies. Closing public registration does not itself create an administrator.

The application container must support the supplied UID 10001, writable paths, Bun healthcheck and SQLite schema. Validate this contract against the exact image digest before release. An older image may ignore policy settings or silently select local storage; the operational verifier rejects a local-storage fallback.

**Historical baseline:** the September implementation/build/bootstrap checks at Enterprise `d106c71` (upstream `34086af`) are prior-source evidence, not qualification of the current release. **Engineering checkpoint:** Private Cloud `779b8d5dc2485fd3c5e61e99d195ea7432c2a846` passed Linux bootstrap/verifier/release checks and Terraform 1.11.4 format/init/validate/mock-policy checks. Enterprise `25ae19c50e26a423e9d2386e3c76ecaf713c71f3` passed all seven CI checks, including production-image boot, native database restoration, browser 31/31 and real SeaweedFS 7/7. Subsequent source changes require fresh CI. Exact application/nginx image digests, full application source binding and all eight installation acceptance reports remain required; new-source image qualification and customer acceptance are pending. No approved release digest or deployment is supplied by these checkpoints.

## Prepare an infrastructure plan

Terraform >= 1.7 and < 2 is required for the blueprint; the offline test suite requires >= 1.11 and CI pins 1.11.4 with the committed provider lockfile. AWS credentials are needed only for the operator's real plan/deployment; CI uses mock providers.

1. Review [architecture and boundaries](docs/ARCHITECTURE.md), account ownership, region, cost, approved ingress, retention and recovery requirements.
2. Choose an approved regional x86_64 Linux AMI with Docker Engine, Compose v2, Python 3, OpenSSL, curl, bash, util-linux and the SSM agent already installed. The blueprint does not execute network bootstrap scripts.
3. Copy `terraform/example.tfvars` to ignored `terraform/tenant.tfvars`. Replace every placeholder, including `tenant_id`, `host_ami_id`, unique bucket name, explicit AZ and client CIDRs. Supply an existing Route 53 zone ID only if this repository should manage the DNS A record.
4. Set up a customer-approved encrypted remote Terraform state backend with locking and restricted access before a real apply. No secrets should be passed as Terraform variables or user data.

```bash
terraform -chdir=terraform init
terraform -chdir=terraform validate
terraform -chdir=terraform plan -var-file=tenant.tfvars -out=tenant.tfplan
```

Review the saved plan and obtain the infrastructure release decision before applying it. Applying, changing DNS, pulling images and starting containers are separate operational steps. The host, bucket and KMS key have destruction safeguards. Removing safeguards or replacing the host requires an explicit migration/retention plan.

## Prepare the provisioned host

After an approved infrastructure deployment, connect through AWS Systems Manager (no SSH port is opened). Transfer this reviewed repository and configuration using the approved administrative channel. Registry authentication, if required, belongs in root's Docker credential helper and must be configured by the operator.

Populate an external environment file from [the template](compose/.env.tenant.template), using `terraform output bootstrap_environment`. Replace application/nginx digests and provide the corporate SMTP relay if required. No AWS access keys are needed. Supply a trusted TLS full chain and matching private key for the portal hostname.

Run from **any working directory** on the target Linux host:

```bash
sudo bash /path/to/docurama-private-cloud/scripts/provision-tenant-vpc.sh \
  acme sign.acme.example /secure/acme.env /secure/fullchain.pem /secure/privkey.pem
```

This validates inputs, certificate hostname/expiry/key match, prepares `/opt/docurama-tenants/acme`, sets UID/GID 10001 on application directories, and checks Compose syntax. It does not start containers. Set `DOCURAMA_DEPLOY_ROOT` only for an intentional alternative absolute mount path.

The script preserves existing `.env`, TLS and signing material. It never generates an unused self-signed signing identity. A changed or incomplete installed TLS identity fails closed. A supplied replacement environment file is ignored on reruns when the installed `.env` exists; update the installed file explicitly under change control, then rerun validation. Dotenv shell expressions and interpolation are unsupported.

After exact-image qualification, backup preparation and deployment approval, repeat the command with `--start /secure/release/release.json`. The [release evidence gate](docs/RELEASE-EVIDENCE.md) requires an approved decision bound to this installation and both digests, plus intact reports for all required acceptance checks. It validates report completeness and integrity, not their truth or approver authority. This pulls the pinned images, starts Compose and waits for application health. Start success is not acceptance evidence. Bootstrap the initial administrator before routing users, then complete customer-instance signing and recovery acceptance checks.

On an initialized **empty** application database, run the application's offline operator command with `DATABASE_URL` and `DOCURAMA_BOOTSTRAP_EMAIL` set for the intended installation:

```bash
# Run inside the approved application container; this is a secret-manager placeholder.
secret-manager-read-command | bun /app/bootstrap-admin.js --empty-installation
```

The command refuses an existing user or tenant, creates the administrator and audit event atomically, and accepts the password over protected stdin or a one-process secret-manager environment injection. Verify the bundled command is present in the chosen image. From the matching source checkout, the equivalent is `bun scripts/bootstrap-admin.ts --empty-installation` with controlled database access. Never put a password in command arguments, shell history, Git, Terraform or logs. Sign in as that administrator, create the first organization through authenticated `POST /api/workspace/settings` (`op: "org.create"`, `data: {name: "Company"}`), then issue invitations. Dedicated mode refuses subsequent organization creation. See the Enterprise application's `docs/INSTALLATION-BOOTSTRAP.md` for the full contract.

For TLS renewal: validate the new pair, preserve an encrypted rollback copy, atomically install the approved files with root-only permissions, run `docker compose exec docurama-tenant-edge nginx -t`, then reload nginx. Validate the served chain/hostname externally. The script checks certificate identity/expiry; full CA trust is checked by the live verifier.

## Operational verification

Establish the portal public-key SPKI SHA-256 fingerprint through a trusted administrative channel and record it outside the deployment. Do not copy an unverified fingerprint from the endpoint being checked.

```bash
bash scripts/verify-compliance.sh sign.acme.example TRUSTED_64_CHARACTER_HEX_FINGERPRINT
```

Despite its historical filename, this is an **operational verifier**, not a compliance certificate. It returns nonzero on transport/TLS errors, missing headers, unhealthy database/storage, local-storage fallback, invalid/mismatched checkpoint data, stale timestamps, an untrusted public key, or a bad RSA signature. It sends no TSA request and claims no timestamp-authority validation. Concurrent transparency writes can produce a checkpoint/head mismatch; retry that probe, then investigate persistent failures.

Release acceptance additionally requires:

- Invitation-only registration, initial-admin provisioning, cross-tenant authorization and signing re-authentication tests against the exact release.
- Real S3 uploads, downloads, delete/version behavior and AWS evidence that objects and EBS use the expected KMS key; deny tests for wrong encryption/key and out-of-scope access.
- Signing/evidence-pack verification, historical transparency consistency monitoring, approved key rotation and any claimed RFC 3161 / Part 11 controls.
- SMTP delivery, TLS renewal, monitoring/alerting and the recovery drill described in [the operations runbook](docs/OPERATIONS.md).

## Offline validation

```bash
bash -n scripts/*.sh
sudo python3 -m unittest discover -s tests -v
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform test
```

Regression tests mock Docker and curl, use temporary directories, and exercise ownership, repeatability, explicit startup, bad inputs/TLS, failed probes and signature tampering. Terraform tests use only a mocked AWS provider. Both test runs use plans. Terraform 1.11.4 supports plan-time ARN overrides, allowing the attached policy assertions to evaluate while production destruction safeguards remain enabled. No provider apply or AWS resource creation occurs. CI performs these checks and Compose interpolation without starting resources.

Only AWS is implemented. Compute tenancy is standard EC2 tenancy (logical separation, not a dedicated physical host). The host is a single point of failure. PostgreSQL, multi-zone failover, private-only egress and certified timestamp/signing services are outside this blueprint. See [the Part 11 evidence checklist](docs/21-CFR-PART-11.md).

---

*© 2026 VOIRIA SASU (Docurama is a product of VOIRIA) · 1 Rue Marguerin, 75014 Paris, France · SIREN 131 914 012 · All rights reserved.*
