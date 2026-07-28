**Secure Prowler CLI Setup on AWS**

A hands-on project documenting how I deployed Prowler — the open-source cloud security scanner — against my personal AWS account using an MFA-gated, least-privilege IAM access pattern, rather than the common (and risky) shortcut of scanning with an admin key.

This repo covers the full journey: the security design decisions, the environment setup (WSL2, Python, AWS CLI), the real debugging problems I hit along the way, and what I found and would remediate from the scan results.

**Why this project**

Most walkthroughs of Prowler stop at pip install prowler && prowler aws. That works, but it usually runs under a long-lived admin credential, which is exactly the kind of practice a security scanner is supposed to help you avoid. I wanted to build — and be able to explain — the access pattern a real security team would actually use:

No long-lived admin keys
MFA required before any scan can run
Read-only permissions only, scoped to the minimum needed
A clear, documented trust boundary between "who can authenticate" and "what they're allowed to do"
