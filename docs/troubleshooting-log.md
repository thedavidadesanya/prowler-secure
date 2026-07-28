# Troubleshooting Log

This project didn't go in a straight line. Below are the real problems I hit while building it, how I diagnosed them, and how I fixed them. I'm including this because debugging methodology is as much a part of cloud security engineering as the initial design — and because "it just worked" write-ups usually aren't telling the whole story.

---

## 1. Python version mismatch (Prowler requires 3.9–3.12)

**Symptom:** Fresh Ubuntu-on-WSL2 install shipped Python 3.14 by default. Prowler requires 3.9–3.12.

**Diagnosis:** `python3 --version` confirmed the mismatch immediately — no ambiguity here, just an environment gap.

**Fix:** Installed Python 3.12 alongside the system default via the `deadsnakes` PPA, then created an isolated virtual environment (`python3.12 -m venv`) so Prowler's dependencies never touch system Python.

```bash
sudo add-apt-repository ppa:deadsnakes/ppa -y
sudo apt install -y python3.12 python3.12-venv python3.12-dev
python3.12 -m venv ~/prowler-venv
```

---

## 2. Working from the Windows-mounted drive caused silent permission failures

**Symptom:** AWS CLI's installer threw `fchmod (file attributes) error: Operation not permitted` repeatedly during install, along with warnings it couldn't set modification/access times.

**Diagnosis:** I was running commands from `/mnt/c/Users/...` — the Windows filesystem, mounted into WSL2. Windows' NTFS permission model doesn't map cleanly onto Linux's `chmod`/`chown` semantics, so any tool trying to set standard Unix file permissions on that mount silently fails or errors.

**Fix:** Moved all work into the native Linux filesystem (`~`, i.e. `/home/user/`), where full POSIX permissions are supported. This is a good general rule: **do WSL work in the Linux home directory, not the Windows mount**, especially for anything installing packages or setting permissions.

---

## 3. MFA `AssumeRole` failing with "unable to validate MFA code"

**Symptom:** `aws sts get-caller-identity --profile prowler-scan` consistently failed with:
```
AccessDenied: MultiFactorAuthentication failed, unable to validate MFA code.
```

**Diagnosis:** Ruled out clock drift first (a common cause of TOTP failures) by checking `date` against real time — that was fine. The actual cause: the `mfa_serial` value in `~/.aws/config` didn't match the MFA device's real name in IAM. I had assumed the device was named after the IAM user (`prowler-cli-user`), but it was actually registered under a different name (`Duo`).

**Fix:** Pulled the exact MFA device ARN from the IAM console (Users → Security credentials → MFA devices) rather than guessing, and corrected `mfa_serial` in the config to match exactly.

**Lesson:** Never assume a resource's exact name/ARN when it's used in a security-critical config value like a trust policy or MFA serial — always confirm from the source (the console or a CLI describe/list call) rather than reconstructing it from memory.

---

## 4. Malformed `.env` file broke Docker Compose entirely

**Symptom:** `docker compose up -d` failed with:
```
failed to read .env: line 140: unexpected character "/" in variable name
```

**Diagnosis:** An earlier manual attempt to paste an RSA private key directly into `.env` via `nano` had left orphaned raw PEM content sitting outside of any `VAR=value` line — multi-line key material doesn't survive being pasted directly into an `.env` file, which expects single-line values.

**Fix:** Used `awk` to convert the PEM key files into single-line strings with escaped `\n` sequences, then wrote them into `.env` using `printf` (more reliable than `sed` for content containing special characters like `/`), rather than manual copy-paste. Verified using character-length checks on each variable — never printing the actual secret values to the terminal — before and after each edit.

```bash
PRIVATE_KEY=$(awk '{printf "%s\\n", $0}' /tmp/private.pem)
printf 'DJANGO_TOKEN_SIGNING_KEY="%s"\n' "$PRIVATE_KEY" >> .env
```

---

## 5. Docker container OOM-killed under 8 GB total RAM

**Symptom:** The Neo4j/graph-database container (`prowler-neo4j-1`) repeatedly exited with code 137, and API requests started taking 25–30 seconds instead of under 1 second.

**Diagnosis:** `docker stats` showed WSL2's containers already using ~2.7 GB against a ~3.7 GB cap before Neo4j even started. Exit code 137 specifically indicates an out-of-memory kill by the kernel. Neo4j's default configuration alone requested up to 3 GB (1 GB pagecache + 1 GB heap-initial + 1 GB heap-max) — more than the whole system could realistically spare on 8 GB of total RAM.

**Fix:** Made a deliberate trade-off: removed the Neo4j service from `docker-compose.yml` entirely, since it only powers the optional "Attack Paths" graph visualization feature — not core scanning, findings, or compliance functionality. This required removing both the service definition and its `depends_on` reference in the API service.

**Lesson:** Not every feature of a tool is worth the resource cost on constrained hardware. Understanding *what* a component does well enough to know it's safe to cut is as valuable as knowing how to add components.

---

## 6. Celery workers stuck in a 90%+ CPU retry loop

**Symptom:** After fixing the memory issue, `prowler-worker-1` and `prowler-worker-beat-1` were pegged at ~93–95% CPU even at idle.

**Diagnosis:** Logs showed a repeating error:
```
OperationalError: AUTH <password> called without any password configured for the default user.
```
The `.env` file had a strong, freshly generated `VALKEY_PASSWORD`, and the API/worker services were configured to authenticate to Valkey using it — but the Valkey container itself had no `command:` directive telling its server process to actually require a password. Client and server were out of sync: one side insisting on auth, the other not expecting any.

**Fix:** Added an explicit `command: ["valkey-server", "--requirepass", "${VALKEY_PASSWORD}"]` to the Valkey service definition, then force-recreated the container and restarted the dependent workers.

---

## 7. Stale JWT session tokens after rotating signing keys

**Symptom:** Web UI showed "unexpected error" on protected actions; logs showed a wall of `Failed to refresh access token: Invalid or expired token`.

**Diagnosis:** I had regenerated `DJANGO_TOKEN_SIGNING_KEY` / `DJANGO_TOKEN_VERIFYING_KEY` as part of a full environment rebuild. Any browser session token issued under the *old* key pair became cryptographically unverifiable the moment the new keys took effect — the frontend kept trying to use a now-invalid token and looping on refresh failures.

**Fix:** Confirmed by testing in an incognito window (no old cookies) — it worked immediately. Cleared cookies/site data for `localhost:3000` in the regular browser window to resolve it there too.

**Lesson:** Rotating signing keys invalidates *all* previously issued sessions, not just newly requested ones — worth remembering as a side effect any time keys are rotated, even in a lab setting.

---

## 8. Storage exhaustion halting Docker image pulls mid-download

**Symptom:** A laptop sleep event during a large image pull (`prowler-api`, ~1.3 GB) corrupted Docker's daemon state (`segmentation fault` on daemon config read) and separately, C: drive hit 0 GB free.

**Diagnosis:** `Get-PSDrive C` showed 0 GB free. A folder-size scan identified a 17 GB cloud-sync folder (Box) as the largest single consumer, fully downloaded locally rather than set to online-only/on-demand.

**Fix:** Freed space by setting the sync folder to online-only (keeps cloud copies intact, removes local duplication) rather than deleting anything outright — deleting a folder inside a sync client risks propagating the deletion to the cloud copy too. Also ran `docker system prune -a` to reclaim space from unused image layers. Disabled sleep during future large downloads.

---

## General takeaways

- **Verify secrets by length, never by value** — every credential/key check in this project was done via character counts, never by printing the actual secret to a terminal that could be screenshotted or logged.
- **Read the actual error, not the assumed one** — several of these (MFA serial, Valkey auth) looked like the same class of "connection failing" symptom but had completely different root causes, only distinguishable by reading logs closely rather than guessing.
- **Resource constraints are a legitimate design input** — the Neo4j removal wasn't a failure, it was a documented trade-off appropriate for the hardware available.
