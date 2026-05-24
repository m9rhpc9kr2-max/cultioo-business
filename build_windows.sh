#!/bin/bash
set -e

# ─────────────────────────────────────────────────────────────────────────────
# Cultioo Business – Windows Release Build Script
# Triggers: Windows .exe installer via GitHub Actions
# ─────────────────────────────────────────────────────────────────────────────

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="cultioo_business"

# Read version from pubspec.yaml
VERSION=$(grep '^version:' "$APP_DIR/pubspec.yaml" | sed 's/version: //' | sed 's/+.*//' | tr -d ' ')
echo "▶ Version: $VERSION"
echo "▶ Platform: Windows"

# ─────────────────────────────────────────────────────────────────────────────
# Trigger Windows EXE build via GitHub Actions
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Triggering Windows EXE build via GitHub Actions …"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if command -v gh &>/dev/null; then
  cd "$APP_DIR"
  # Check if inside a git repo with a remote
  if git remote get-url origin &>/dev/null; then
    gh workflow run build_desktop.yml
    echo "✓ GitHub Actions workflow triggered."
    echo ""
    echo "  → Download the Windows installer from:"
    REPO=$(git remote get-url origin | sed 's/.*github.com[:/]//' | sed 's/\.git$//')
    echo "    https://github.com/$REPO/actions"
    echo ""
    echo "  The installer will be named: cultioo_business_setup.exe"
  else
    echo "⚠ No git remote found. Push the repo to GitHub first."
    exit 1
  fi
else
  echo "⚠ GitHub CLI (gh) not installed."
  echo "  → Install with: brew install gh"
  echo "  → Then authenticate: gh auth login"
  echo ""
  echo "  Alternatively, push to GitHub and the Windows EXE will be built"
  echo "  automatically via GitHub Actions."
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Done!"
echo "  Windows: Check GitHub Actions for cultioo_business_setup.exe"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
