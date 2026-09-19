# Part 11 evidence checklist

This blueprint does not establish 21 CFR Part 11 compliance. Its previous claims of out-of-the-box re-authentication, dual-factor signing and immutable trails were not backed by validated deployment evidence and must not be treated as product guarantees.

No `DOCURAMA_PART11_ENFORCED` or `DOCURAMA_TSA_URL` setting is supplied: those names were not implemented in the inspected application. Use only settings supported and tested by the exact release image. KMS encryption, an isolated VPC and a valid checkpoint signature do not prove regulated signing controls.

Before making a regulated-use claim, the product, security and customer validation owners must approve and retain evidence for:

- Intended use and a validated system lifecycle, including change control and restoration.
- Identity proofing, unique accounts, credential controls, session expiration, authorized access and the exact re-authentication behavior for each signing ceremony.
- Signature manifestations, meaning, binding to the signed record and reproducible independent verification.
- Audit completeness, timestamp sources, access control, retention, tamper detection and authorized correction procedures.
- Any timestamp-authority integration, including an actual RFC 3161 response, trust-chain/signature validation and failure handling.
- SOPs, training, accountability, incident response, electronic-record export and customer retention requirements.

The operational verifier checks TLS, headers, current database/S3 health and an RSA-signed checkpoint against a trusted key. It does not perform a signing ceremony, validate a TSA, prove append-only history or establish any legal/regulatory status.
