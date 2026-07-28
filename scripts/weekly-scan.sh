#!/bin/bash
#
# weekly-scan.sh
#
# Runs a full Prowler AWS scan using the MFA-gated `prowler-scan` profile,
# saves timestamped output, and prints a quick pass/fail summary.
#
# This script requires a human to enter an MFA code when prompted —
# it is intentionally NOT designed for unattended/cron execution,
# since the scanning role's trust policy requires MFA by design.
# Run it manually each week (e.g., every Monday) as part of a
# continuous-monitoring habit.
#
# Usage:
#   ./scripts/weekly-scan.sh
#
# Optional: pass a compliance framework to scan against instead of
# the default full check set, e.g.:
#   ./scripts/weekly-scan.sh cis_4.0_aws

set -uo pipefail
# Note: we deliberately do NOT use `set -e` here.
# Prowler exits with a non-zero code whenever it finds FAIL results —
# that's expected, normal behavior (useful for CI/CD gating), not a script error.
# `set -e` would kill this script the moment any FAIL is found, before
# we ever reach the summary output below.

PROFILE="prowler-scan"
VENV_PATH="$HOME/prowler-venv"
BASE_OUTPUT_DIR="$HOME/prowler-scan-history"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
OUTPUT_DIR="$BASE_OUTPUT_DIR/$TIMESTAMP"
COMPLIANCE="${1:-}"

echo "=================================================="
echo " Prowler Weekly Scan"
echo " Timestamp: $TIMESTAMP"
echo " Profile:   $PROFILE"
echo "=================================================="

# Activate the virtual environment
if [ ! -f "$VENV_PATH/bin/activate" ]; then
  echo "ERROR: venv not found at $VENV_PATH. Check the path or recreate it."
  exit 1
fi
# shellcheck disable=SC1091
source "$VENV_PATH/bin/activate"

mkdir -p "$OUTPUT_DIR"

echo ""
echo "You will be prompted for your MFA code shortly."
echo ""

if [ -n "$COMPLIANCE" ]; then
  echo "Running compliance scan: $COMPLIANCE"
  prowler aws \
    --profile "$PROFILE" \
    --compliance "$COMPLIANCE" \
    --output-formats csv json-ocsf html \
    --output-directory "$OUTPUT_DIR" || true
else
  echo "Running full check scan"
  prowler aws \
    --profile "$PROFILE" \
    --output-formats csv json-ocsf html \
    --output-directory "$OUTPUT_DIR" || true
fi
# The `|| true` above intentionally absorbs Prowler's exit code so this
# script continues to the summary section below regardless of whether
# Prowler found FAIL results (expected) or PASS-only results.

echo ""
echo "=================================================="
echo " Scan complete. Results saved to:"
echo " $OUTPUT_DIR"
echo "=================================================="

# Quick pass/fail summary from the CSV output, if present
CSV_FILE=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.csv" | head -n 1)
if [ -n "$CSV_FILE" ]; then
  echo ""
  echo "Quick summary:"
  echo "  PASS: $(grep -c ',PASS,' "$CSV_FILE" || true)"
  echo "  FAIL: $(grep -c ',FAIL,' "$CSV_FILE" || true)"
fi

echo ""
echo "Previous scan runs are stored in: $BASE_OUTPUT_DIR"
echo "Compare two runs manually to check for posture drift, e.g.:"
echo "  diff <(sort OLD_RUN.csv) <(sort NEW_RUN.csv)"
