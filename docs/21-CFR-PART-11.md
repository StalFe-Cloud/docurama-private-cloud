# 21 CFR Part 11 Compliance & Audit Profile

Docurama Private Cloud includes out-of-the-box controls satisfying the United States Food and Drug Administration (FDA) Title 21 CFR Part 11 requirements for electronic records and electronic signatures.

## Controls Implemented

1. **Signature Manifestations (§ 11.50):**
   - Printed name of the signatory.
   - Exact UTC date and time when the signature was executed.
   - The meaning (such as review, approval, authorship, or witness).
   - Manifested visibly on each page and sealed cryptographically in the PDF certification dict.

2. **Signature Authenticity & Re-Authentication (§ 11.200):**
   - Each electronic signature is unique to one individual and cannot be reused or reassigned.
   - When multiple signatures are executed in a continuous session, the first signature requires credentials + 2FA, and subsequent executions mandate password or token re-confirmation.

3. **Computer-Generated Audit Trails (§ 11.10(e)):**
   - Immutable, timestamped, operator-independent audit trails logging date and time of operator entries and actions.
   - Block height cryptographic sealing prevents alteration of historical records.
