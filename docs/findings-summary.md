# Findings Summary & Remediation Notes

Scan scope: `--services iam`, run against a personal/lab AWS account using the access pattern documented in [`iam-setup-guide.md`](iam-setup-guide.md).

Specific resource names, ARNs, and account identifiers are omitted throughout — this document focuses on the *categories* of findings and how I'd approach remediating them, which is the transferable part.

## Aggregate results

| Metric | Value |
|---|---|
| Total IAM checks run | 145 |
| Passed | 110 (75.9%) |
| Failed | 35 (24.1%) |
| Critical | 2 |
| High | 17 |
| Medium | 10 |
| Low | 6 |

Consistent across two independent runs (initial setup and a later CLI rebuild), confirming the scan results reflect actual account state rather than a fluke or tooling error.

## Common IAM finding categories (illustrative)

Prowler's IAM checks generally cluster into a few recognizable themes. Below are the categories most likely to appear in a personal/lab account's IAM findings, along with how each would typically be remediated. (Exact check IDs and affected resources are intentionally omitted here — this reflects general Prowler IAM check categories, not a resource-by-resource account audit.)

### Credential hygiene
- Unused IAM users, roles, or access keys older than a threshold (commonly 90 days)
- **Remediation approach:** deactivate or delete unused credentials; for keys still in use, establish a rotation cadence (e.g. every 90 days) rather than leaving them static indefinitely

### MFA coverage
- IAM users with console access but no MFA enabled
- Root account without hardware or virtual MFA
- **Remediation approach:** enforce MFA account-wide via an SCP (if using AWS Organizations) or a targeted IAM policy condition; for a single-account setup, manually verify MFA is enabled on every console user, prioritizing root

### Overly permissive policies
- Policies granting wildcard actions (`"Action": "*"`) or wildcard resources (`"Resource": "*"`) where a narrower scope would suffice
- **Remediation approach:** use IAM Access Analyzer's policy generation feature to derive a minimal policy from actual CloudTrail usage, then replace the broad policy incrementally, monitoring for access errors before removing the old one

### Privilege escalation paths
- IAM policies that, combined, allow a principal to grant itself additional permissions (e.g. `iam:CreatePolicyVersion`, `iam:PassRole` combined with permissive service access)
- **Remediation approach:** these require the most careful review — the fix isn't always "remove the permission" since some are needed for legitimate administrative work; the priority is knowing they exist and limiting which principals hold them

### Password policy gaps
- Account password policy not meeting length, complexity, rotation, or reuse-prevention baselines
- **Remediation approach:** update the account-wide IAM password policy in one step via the console or CLI; this is usually the fastest, highest-leverage fix available since it applies immediately to all users

## What I'd prioritize first

Given the severity distribution (2 Critical, 17 High), the practical remediation order I'd follow:

1. **Both Critical findings** — by definition these represent the most direct path to account compromise or major exposure; addressed immediately regardless of effort required
2. **MFA and credential hygiene findings among the High tier** — typically the highest ROI, since they're usually configuration toggles rather than architectural changes
3. **Overly permissive policy findings** — higher effort (requires understanding what a policy is actually used for before narrowing it), but high value
4. **Medium/Low findings** — addressed on a rolling basis, often batched into a maintenance cadence rather than treated as urgent

## Why this matters beyond "check passed/failed"

Running the scan is the easy part. The actual skill — and what I'd want to demonstrate to an employer — is this triage judgment: understanding *why* a finding matters, what realistic remediation looks like, and what order of operations avoids breaking legitimate access while closing the gap. A scanner that just reports red/green without this layer of judgment isn't adding much value on its own.

## Next steps

- [ ] Re-run with `--compliance cis_4.0_aws` to map findings to a named framework
- [ ] Track remediation of the 2 Critical findings through to a verified re-scan showing PASS
- [ ] Expand scope beyond IAM to S3, EC2, and VPC in a follow-up scan
