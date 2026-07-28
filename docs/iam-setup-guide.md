# IAM Setup Guide: MFA-Gated Least-Privilege Access for Prowler

This guide walks through building the exact access pattern used in this project: an IAM user with no direct permissions, that can only assume a scoped, read-only role, and only after presenting a valid MFA code. No long-lived admin credentials are ever used to run scans.

All account IDs, ARNs, and role names below are illustrative — replace with your own.

## Why this pattern instead of just using access keys directly

A single IAM user with `AdministratorAccess` and a static access key pair is the fastest way to get Prowler running — and the fastest way to create a serious liability. If that key pair ever leaks (committed to a repo, exposed in a log, phished), an attacker has standing, permanent access to everything in the account.

The pattern here adds two independent barriers:
1. **The user itself can do nothing** except assume one specific role — even a fully compromised key pair is useless without also passing MFA.
2. **The role itself can do nothing but read** — `SecurityAudit` and `ViewOnlyAccess` are AWS-maintained managed policies with no write, delete, or modify permissions anywhere.

## Step 1: Create the IAM user

1. IAM Console → **Users** → **Create user**
2. Name: `prowler-cli-user`
3. Do **not** enable console access — this user only needs programmatic access
4. Don't attach any permissions policies directly at this stage

## Step 2: Enable MFA on the user

1. IAM → Users → `prowler-cli-user` → **Security credentials** tab
2. Under "Multi-factor authentication (MFA)" → **Assign MFA device**
3. Choose an authenticator app (any TOTP-compatible app — Google Authenticator, Authy, Duo, 1Password, etc.)
4. Scan the QR code and confirm with two consecutive codes
5. **Copy the exact MFA device ARN shown after setup** — you'll need this later, and it's easy to assume it matches the username when it might not (see the troubleshooting log for what happens when it doesn't)

## Step 3: Create the scanning role with a custom trust policy

1. IAM → **Roles** → **Create role**
2. Trusted entity type: **Custom trust policy** (not "AWS service" — that's for services like EC2/Lambda assuming a role, not a human user)
3. Paste the following, replacing the placeholder account ID and username:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::YOUR_ACCOUNT_ID:user/prowler-cli-user"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "Bool": {
          "aws:MultiFactorAuthPresent": "true"
        }
      }
    }
  ]
}
```

The `Condition` block is what makes this MFA-gated — without a valid MFA session, the assume-role call is denied outright, regardless of whether the caller has valid access keys.

4. Attach two AWS-managed policies:
   - `SecurityAudit`
   - `ViewOnlyAccess`
5. Name the role `ProwlerScanRole`

## Step 4: Allow the user to assume the role (and nothing else)

1. IAM → Users → `prowler-cli-user` → **Add permissions** → **Create inline policy**
2. JSON editor:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::YOUR_ACCOUNT_ID:role/ProwlerScanRole"
    }
  ]
}
```

3. Name it `AllowAssumeProwlerScanRole`

Note this is deliberately narrow: `prowler-cli-user` can assume exactly one role and cannot call any other AWS API directly.

## Step 5: Generate access keys

1. IAM → Users → `prowler-cli-user` → **Security credentials** → **Create access key**
2. Use case: **Command Line Interface (CLI)**
3. Save the Access Key ID and Secret Access Key somewhere secure (password manager) — this is the only time the secret is shown

## Step 6: Configure the AWS CLI locally

```bash
aws configure --profile prowler-cli-user
```

Enter the access key ID, secret, and your preferred region.

Then edit `~/.aws/config` to add the role-assumption profile:

```ini
[profile prowler-scan]
role_arn = arn:aws:iam::YOUR_ACCOUNT_ID:role/ProwlerScanRole
source_profile = prowler-cli-user
mfa_serial = arn:aws:iam::YOUR_ACCOUNT_ID:mfa/YOUR_MFA_DEVICE_NAME
region = us-east-1
```

Use the **exact** MFA serial ARN from Step 2 — don't assume it matches the username.

Lock down the credentials file:

```bash
chmod 600 ~/.aws/credentials
```

## Step 7: Test the full chain

```bash
aws sts get-caller-identity --profile prowler-scan
```

This should prompt for an MFA code, then return an identity like:

```json
{
  "UserId": "AROAEXAMPLE:botocore-session-...",
  "Account": "123456789012",
  "Arn": "arn:aws:sts::123456789012:assumed-role/ProwlerScanRole/botocore-session-..."
}
```

The `assumed-role/ProwlerScanRole` in the ARN confirms the full chain worked: MFA passed, role assumed, temporary credentials issued.

## Step 8: Run Prowler using the profile

```bash
source ~/prowler-venv/bin/activate
prowler aws --profile prowler-scan
```

## A note on permission boundaries

I deliberately did **not** add a permission boundary on top of this role. Permission boundaries are most valuable when multiple people or automated pipelines can create/modify IAM entities, guarding against someone accidentally granting more access than intended. In a single-admin personal account, with a role that's already scoped to two AWS-managed read-only policies, a boundary adds complexity without meaningfully reducing risk. This would be revisited in a multi-admin or CI/CD context.

## A note on automation vs. human access

This role is intentionally unsuitable for automated tooling (like a scheduled scan or a backend service) because MFA requires a human to type a code. For anything that needs to run unattended, use a **separate** role/user pair without the MFA condition, scoped just as tightly on the permissions side, so the human-facing MFA boundary and the automation boundary are never mixed.
