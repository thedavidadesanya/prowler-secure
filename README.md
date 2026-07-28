# Secure Prowler CLI Setup on AWS

A hands-on project documenting how I deployed [Prowler](https://github.com/prowler-cloud/prowler) — the open-source cloud security scanner — against my personal AWS account using an MFA-gated, least-privilege IAM access pattern, rather than the common (and risky) shortcut of scanning with an admin key.

This repo covers the full journey: the security design decisions, the environment setup (WSL2, Python, AWS CLI), the real debugging problems I hit along the way, and what I found and would remediate from the scan results.

## Why this project

Most walkthroughs of Prowler stop at `pip install prowler && prowler aws`. That works, but it usually runs under a long-lived admin credential, which is exactly the kind of practice a security scanner is supposed to help you avoid. I wanted to build — and be able to explain — the access pattern a real security team would actually use:

- No long-lived admin keys
- MFA required before any scan can run
- Read-only permissions only, scoped to the minimum needed
- A clear, documented trust boundary between "who can authenticate" and "what they're allowed to do"

## Architecture

<img width="1022" height="501" alt="prowler-cli-architecture drawio" src="https://github.com/user-attachments/assets/f086f882-74e9-4e57-90b7-7c4f7e28493d" />

**Access flow:**
1. I authenticate locally as IAM user `prowler-cli-user` (no permissions of its own — programmatic access only)
2. I run `aws sts assume-role` (via a named CLI profile) against `ProwlerScanRole`
3. The role's trust policy only allows `prowler-cli-user` to assume it, **and only with a valid MFA code**
4. AWS STS issues temporary, auto-expiring credentials (1 hour)
5. Prowler CLI uses those temporary credentials to run read-only checks (`SecurityAudit` + `ViewOnlyAccess` managed policies — no write access anywhere)
6. Results are written locally as JSON-OCSF, CSV, and HTML reports

Full write-up: [`docs/iam-setup-guide.md`](docs/iam-setup-guide.md)

## Environment

| Component | Version / Detail |
|---|---|
| OS | Windows 11 + WSL2 (Ubuntu 26.04) |
| Python | 3.12 (via `deadsnakes` PPA, isolated in a venv) |
| Prowler | 5.35.0 (CLI) |
| AWS CLI | v2 |
| MFA | Virtual device (Duo) |

## What I scanned

Initial run scoped to IAM (`--services iam`):

| Result | Count |
|---|---|
| Passed | 110 (75.9%) |
| Failed | 35 (24.1%) |
| — Critical | 2 |
| — High | 17 |
| — Medium | 10 |
| — Low | 6 |

Sanitized findings breakdown and remediation notes: [`docs/findings-summary.md`](docs/findings-summary.md)

## Key security decisions (and why)

| Decision | Reasoning |
|---|---|
| Human-facing role requires MFA | Static keys can leak; MFA means leaked keys alone can't assume the scanning role |
| Separate role for automation (web UI) vs. CLI (human) | MFA can't be supplied by an automated service — mixing the two blurs the trust boundary |
| No permission boundary added | Overkill for a single-admin personal account with an already-scoped, read-only role; would be reconsidered in a multi-admin or CI/CD context |
| `SecurityAudit` + `ViewOnlyAccess` only, no custom policy | Uses AWS's own maintained, least-privilege managed policies rather than hand-rolling permissions |

## Running it yourself

```bash
# Activate the environment
source ~/prowler-venv/bin/activate

# Run a scoped scan
prowler aws --profile prowler-scan --services iam

# Run a full scan
prowler aws --profile prowler-scan

# Run against a compliance framework
prowler aws --profile prowler-scan --compliance cis_4.0_aws
```

Full setup instructions (creating the IAM user, role, trust policy, and CLI profiles from scratch): [`docs/iam-setup-guide.md`](docs/iam-setup-guide.md)

## Lessons learned

Building this wasn't a straight line — I hit and resolved several real infrastructure issues along the way, including a Python version mismatch, a corrupted Docker daemon config, an out-of-memory container crash, and a Celery/Redis authentication mismatch. Full debugging log, including root causes and fixes: [`docs/troubleshooting-log.md`](docs/troubleshooting-log.md)

## What's next

- [ ] Weekly scheduled scan (cron, Mondays)
- [ ] Scan diffing to track posture drift over time
- [ ] Prowler Autonomous Fixer for guided remediation
- [ ] Integration with a SOC-style runbook project for formalized incident response

## Related projects

This is one piece of a broader cloud security portfolio, all running against the same personal AWS environment:
- SageMaker-based anomaly detection for behavioral threat signals
- SOC runbook on EC2 for documented incident response playbooks
- Cloud Resume Challenge with an AI/chat integration layer

---

*Built as part of my preparation for the AWS Certified Security – Specialty exam.*
