#!/bin/sh
# One-time setup after cloning: installs the pinned SwiftLint into .tools/
# and turns on the team's git hooks in .githooks/.
set -eu

SWIFTLINT_VERSION="0.65.1"
SWIFTLINT_SHA256="c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"
SWIFTLINT_URL="https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip"

cd "$(git rev-parse --show-toplevel)"
SWIFTLINT=".tools/swiftlint"

if [ -x "$SWIFTLINT" ] && [ "$("$SWIFTLINT" version)" = "$SWIFTLINT_VERSION" ]; then
  echo "SwiftLint $SWIFTLINT_VERSION is already installed."
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  echo "Downloading SwiftLint $SWIFTLINT_VERSION..."
  curl -fsSL "$SWIFTLINT_URL" -o "$tmp/swiftlint.zip"
  actual=$(shasum -a 256 "$tmp/swiftlint.zip" | cut -d ' ' -f 1)
  if [ "$actual" != "$SWIFTLINT_SHA256" ]; then
    echo "Checksum mismatch, not installing. Expected $SWIFTLINT_SHA256, got $actual." >&2
    exit 1
  fi
  mkdir -p .tools
  unzip -o -q "$tmp/swiftlint.zip" swiftlint -d .tools
  chmod +x "$SWIFTLINT"
  echo "Installed SwiftLint $("$SWIFTLINT" version) in .tools/."
fi

git config core.hooksPath .githooks
echo "Git hooks are on (.githooks)."
