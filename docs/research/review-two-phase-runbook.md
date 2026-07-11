# Review two-phase approval

Gunshi LGTM is provisional. Karo records the final decision against the same report fingerprint:

`bash scripts/review_approval.sh <cmd_id> karo ACCEPT <report.yaml>`

For changes requested:

`bash scripts/review_approval.sh <cmd_id> karo RC <report.yaml>`

RC invalidates the stored gunshi LGTM. Notifications alone never constitute approval. The fingerprint combines the report SHA-256 and its `commit_hash`.
