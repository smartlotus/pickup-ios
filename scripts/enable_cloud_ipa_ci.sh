#!/usr/bin/env bash
set -euo pipefail

# Run once after authorizing GitHub workflow scope:
#   gh auth refresh -h github.com -s workflow
mkdir -p .github/workflows
cp ci/ios-ci-release.yml .github/workflows/ios-ci-release.yml
git add .github/workflows/ios-ci-release.yml
git commit -m "ci: enable macos-26 Xcode 26 IPA & simulator workflow"
git push origin main
gh workflow run ios-ci-release.yml
