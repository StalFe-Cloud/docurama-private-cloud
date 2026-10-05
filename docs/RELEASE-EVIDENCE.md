# Release evidence gate

`--start` requires an operator-reviewed release evidence JSON file. Prepare-only
provisioning remains available without it. Qualify the exact application and nginx
digests in a separately approved isolated acceptance environment before starting
the customer deployment. This gate does not create that environment or authorize
an infrastructure deployment. The file records a release decision, not a regulatory
certification; the validator checks completeness, installation/image binding and
report integrity, not the truth of reports or the identity/authority of an approver.

Copy `release-evidence.template.json` and replace every placeholder. Every check
must pass and reference a non-secret report with its SHA-256. Report paths are
relative to the JSON file and must stay within its directory (including after
symlink resolution). Store reports and decisions in approved restricted evidence
storage outside Git. Do not include passwords, session tokens, TLS private keys,
environment file contents or customer documents. Preserve the original reviewed
reports; a changed or missing report fails validation.

Required reports:

| Check | Minimum acceptance evidence |
| --- | --- |
| runtime_contract | Exact app/edge digests, full Enterprise source commit, SQLite build provider, UID 10001, writable mounts, Bun healthcheck, closed registration/private cloud, role-based S3 and no local fallback |
| migration_failure | Provider-specific migration assets in image, successful clean/upgrade migration and failed migration refusing boot; no automatic destructive push or migration bypass |
| admin_bootstrap | Bundled offline command and dependencies, empty-installation admin creation/audit, refusal on existing users/tenants |
| invitation_and_tenant_isolation | Closed public signup, authenticated first organization, dedicated-mode limits, invitations and cross-tenant authorization denials |
| s3_kms_and_access_denials | Real upload/download/version behavior; expected KMS on object/EBS; missing/wrong encryption/key and out-of-scope bucket denials |
| signing_and_evidence | Signing reauthentication, document/evidence verification, pinned checkpoint identity and any specifically claimed signing/timestamp controls |
| backup_restore | Approved RPO/RTO/retention; coordinated SQLite backup plus document-version manifest; isolated restore with hashes/signatures/key continuity and measured recovery |
| monitoring_and_tls | Named alert owner/destinations, failed-probe alarm test, certificate renewal and trust check, capacity/mail/backup/KMS alerts and historical consistency monitoring |

Validate offline without contacting any service:

```bash
python3 scripts/validate-release.py /secure/release/release.json /secure/acme.env acme sign.acme.example
```

After the separately approved infrastructure and release decisions:

```bash
sudo bash scripts/provision-tenant-vpc.sh acme sign.acme.example /secure/acme.env /secure/fullchain.pem /secure/privkey.pem --start /secure/release/release.json
```

The installed `.env` is authoritative on reruns. Evidence must match its digests.
Requalify changed images and explicitly update installed configuration under change
control. Perform customer-instance verification, admin bootstrap and final traffic
acceptance afterward; staging qualification cannot prove the customer's IAM, AMI,
TLS, integration configuration or restored state.

Portable local checks (temporary files only, no subprocesses/services):

```bash
python3 -B -m unittest discover -s tests -p test_release.py -v
```

The full `test_blueprint.py` suite requires Linux tools; ownership tests require
root and use temporary directories plus mocked Docker/curl. Terraform mock tests
now inspect the actual attached policy JSON instead of substituting empty policies.
The sole test AWS provider is mocked. Both runs use plans, with Terraform 1.11.4
plan-time ARN overrides for attached policy assertions. These tests require
Terraform >= 1.11. Production destruction safeguards remain enabled; no provider
apply or cloud resource creation occurs.
They still do not evaluate live AWS authorization. Run the documented Terraform
format/validate/mock tests with the locked provider before accepting this change.

## Evidence lineage and pending qualification

The prior Private Cloud engineering checkpoint is `779b8d5dc2485fd3c5e61e99d195ea7432c2a846`; the prior Enterprise all-green checkpoint is `25ae19c50e26a423e9d2386e3c76ecaf713c71f3`. Their CI evidence is source-specific and must not be attributed to later edits or substituted for an approved image digest. Requalify the new source and exact SQLite application/nginx digests, retain the full application source commit and all eight report categories above, and obtain the installation release decision before `--start`. Do not prefill pending reports as passed from mocked IAM or synthetic SeaweedFS evidence.
