#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

cp "$repo_root/.github/policy/testdata/empty-plan.json" "$test_dir/plan.json"

cd "$test_dir"
conftest test plan.json --policy "$repo_root/.github/policy" \
  --all-namespaces --output json > iam-findings.json
jq -e 'type == "array"' iam-findings.json >/dev/null
conftest test plan.json --policy "$repo_root/.github/policy" \
  --namespace terraform.guardrail
