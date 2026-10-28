#!/usr/bin/env bash
set -euo pipefail

# For personal account bahag-banasiks/DCCP-892, GitHub includes numeric owner/repo IDs in OIDC sub:
# repo:bahag-banasiks@147695780/DCCP-892@1436820855:ref:refs/heads/<branch>
# Fixed prefix length = 65 bytes
# Max branch length for 127-byte google.subject = 127 - 65 = 62 bytes.

PREFIX="test-wif-"
# 62 chars total -> 65 + 62 = 127 bytes (exact boundary: passes WIF)
BRANCH_OK="${PREFIX}$(printf 'a%.0s' {1..53})"
# 63 chars total -> 65 + 63 = 128 bytes (exceeds 127 bytes: fails WIF)
BRANCH_TOO_LONG="${PREFIX}$(printf 'b%.0s' {1..54})"

echo "Branch OK       (${#BRANCH_OK} bytes -> sub = $((65 + ${#BRANCH_OK})) bytes):"
echo "  $BRANCH_OK"
echo "Branch TOO_LONG (${#BRANCH_TOO_LONG} bytes -> sub = $((65 + ${#BRANCH_TOO_LONG})) bytes):"
echo "  $BRANCH_TOO_LONG"
echo ""

case "${1:-help}" in
  push-ok)
    git checkout -B "$BRANCH_OK"
    git push -u origin "$BRANCH_OK"
    git checkout main
    ;;
  push-too-long)
    git checkout -B "$BRANCH_TOO_LONG"
    git push -u origin "$BRANCH_TOO_LONG"
    git checkout main
    ;;
  cleanup)
    git push origin --delete "$BRANCH_OK" 2>/dev/null || true
    git push origin --delete "$BRANCH_TOO_LONG" 2>/dev/null || true
    git branch -D "$BRANCH_OK" 2>/dev/null || true
    git branch -D "$BRANCH_TOO_LONG" 2>/dev/null || true
    ;;
  *)
    echo "Usage: $0 {push-ok|push-too-long|cleanup}"
    exit 1
    ;;
esac
