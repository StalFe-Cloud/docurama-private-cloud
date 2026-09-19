# Release and recovery runbook

## Before accepting a tenant

Record the reviewed Git commit, application and edge image digests, approved AMI, Terraform/provider versions, saved plan, account/region, ingress CIDRs, DNS/TLS owner, KMS ARN and bucket name. Keep secrets in approved secret storage, outside Git and Terraform. Verify the Enterprise image implements every required environment contract and closed registration has a tested initial administrator/invitation path.

Prove health, isolated document access and signing with a non-customer fixture. Inspect a newly written object's encryption metadata and EBS encryption against the recorded key. Prove an upload with missing/wrong SSE-KMS headers is denied and the instance role cannot access another bucket. Record tests and approval before routing real traffic.

## Monitoring

Run the operational verifier from an approved external network with a separately trusted fingerprint; alert on any nonzero exit. Use a scheduled monitoring system approved by the customer. No monitor is installed by this repository. Alert on EC2/SSM reachability, EBS usage, app restarts/health, expired or changed certificates, mail failures, backup age, KMS access failures and unexpected AWS policy/configuration changes. EC2 detailed monitoring is enabled, but no CloudWatch alarm destinations are configured.

Store verified historical checkpoints outside the host. Signature checks prove authenticity under the pinned key; they do not prove that an advancing log is a valid extension of previous entries. A consistency monitor must verify those historical chain links and detect shrinkage/replacement. Authorized key rotations need a signed continuity record and an independent fingerprint update.

## Backups and restore rehearsal

Set customer-approved RPO, RTO, backup retention and an independent recovery principal/account. S3 versioning alone is not a backup; the application can delete current versions, and AWS administrators can alter bucket/KMS policies. Decide whether Object Lock, AWS Backup or an independent replicated vault is required. No retention duration is invented here.

For the supplied single-host SQLite layout, schedule a maintenance window, stop application writes, then snapshot or copy the database and all local operational data consistently. Capture the whole SQLite directory (including WAL/SHM if present), environment, necessary signing/trust identities and a manifest of document object versions. Encrypt backups and separate backup administration from the application role. Preserve KMS access for the entire retention period. Live filesystem copies without SQLite coordination are not acceptable.

Restore into an isolated host/bucket with no public ingress and outbound delivery disabled. Use an approved compatible image and controlled schema migration. Restore database/identities and matching S3 object versions; configure the recovery role and KMS key. Check counts, representative document hashes, downloads, signatures, evidence-pack verification, transparency key continuity, registration policy and membership boundaries. Measure actual RPO/RTO, record evidence and destroy only the disposable rehearsal environment after approval.

## Upgrade and rollback

Review schema changes and backup first. Pin the candidate digest, run tests in a restored isolated environment, then explicitly update the installed environment under change control. Bootstrap reruns preserve installed configuration, so merely passing a new environment file does not apply an upgrade. The startup procedure must fail on migration failure and may not accept data loss automatically.

Rollback to the prior image only when its schema is compatible. Otherwise restore the approved consistent database/object backup; plan for writes after the restore point. Never reset trust identities to make a failed verification pass. Keep the prior digest, configuration and verified checkpoint outside the host.

## TLS renewal

Validate certificate expiry, hostname, chain and key match before installation. Preserve encrypted rollback material, install the pair with root-only permissions, test nginx configuration and reload only after the test succeeds. Run the external verifier afterward. Bootstrap intentionally rejects silent TLS identity replacement.

Infrastructure apply, DNS cutover, image publication, live probes against a customer enclave and backup/restore execution remain separately approved operational actions.
