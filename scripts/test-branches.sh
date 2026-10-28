#!/usr/bin/env bash
set -euo pipefail

# For repo:bahag-banasiks/DCCP-892:ref:refs/heads/<branch>
# Fixed prefix length = 44 bytes ("repo:bahag-banasiks/DCCP-892:ref:refs/heads/")
# Max branch length for 127-byte google.subject = 127 - 44 = 83 bytes.

PREFIX="test-wif-"
# 83 chars total -> 44 + 83 = 127 bytes (exact boundary: passes WIF and passes ruleset)
BRANCH_83="${PREFIX}$(printf 'a%.0s' {1..74})"
# 84 chars total -> 44 + 84 = 128 bytes (exceeds 127 bytes: fails WIF without ruleset, blocked by ruleset when active)
BRANCH_84="${PREFIX}$(printf 'b%.0s' {1..75})"

echo "Branch 83 chars (${#BRANCH_83} bytes -> sub = $((44 + ${#BRANCH_83})) bytes):"
echo "  $BRANCH_83"
echo "Branch 84 chars (${#BRANCH_84} bytes -> sub = $((44 + ${#BRANCH_84})) bytes):"
echo "  $BRANCH_84"
echo ""

case "${1:-help}" in
  push-83)
    git checkout -B "$BRANCH_83"
    git push -u origin "$BRANCH_83"
    git checkout main
    ;;
  push-84)
    git checkout -B "$BRANCH_84"
    git push -u origin "$BRANCH_84"
    git checkout main
    ;;
  cleanup)
    git push origin --delete "$BRANCH_83" 2>/dev/null || true
    git push origin --delete "$BRANCH_84" 2>/dev/null || true
    git branch -D "$BRANCH_83" 2>/dev/null || true
    git branch -D "$BRANCH_84" 2>/dev/null || true
    ;;
  *)
    echo "Usage: $0 {push-83|push-84|cleanup}"
    exit 1
    ;;
esac
