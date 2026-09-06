#!/bin/bash
# test_suite.sh - Automated test suite for sgwebapp

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$PROJECT_ROOT/bin/sgwebapp"

TEST_APP_NAME="SGWebAppTestDummy"
TEST_APP_URL="https://example.com"
APPS_DIR="$HOME/Applications"
TARGET_APP="$APPS_DIR/$TEST_APP_NAME.app"

PASSED=0
FAILED=0

pass() {
  echo -e "  \033[32m✔ PASS:\033[0m $1"
  ((PASSED++)) || true
}

fail() {
  echo -e "  \033[31m✘ FAIL:\033[0m $1"
  ((FAILED++)) || true
}

cleanup() {
  if [[ -d "$TARGET_APP" ]]; then
    rm -rf "$TARGET_APP"
  fi
}
trap cleanup EXIT

echo "Running sgwebapp test suite..."

# 1. Test Help and Version
if "$BIN" help >/dev/null; then
  pass "sgwebapp help command exits cleanly"
else
  fail "sgwebapp help command failed"
fi

if "$BIN" version | grep -q "sgwebapp version"; then
  pass "sgwebapp version reports valid version"
else
  fail "sgwebapp version command failed"
fi

# 2. Test Compilation of Border Daemon
if make -C "$PROJECT_ROOT" build >/dev/null; then
  pass "make build compiles Swift border daemon"
else
  fail "make build failed"
fi

# 3. Test Installation
if "$BIN" install "$TEST_APP_NAME" "$TEST_APP_URL" >/dev/null; then
  pass "sgwebapp install command succeeded"
else
  fail "sgwebapp install command failed"
fi

# Verify app bundle structure
if [[ -d "$TARGET_APP" && ( -f "$TARGET_APP/Contents/MacOS/$TEST_APP_NAME" || -f "$TARGET_APP/Contents/MacOS/launcher" ) && -f "$TARGET_APP/Contents/Info.plist" && -f "$TARGET_APP/Contents/Resources/AppIcon.icns" && -f "$TARGET_APP/Contents/Resources/sgwebapp.json" ]]; then
  pass "Generated .app bundle has all required files (launcher, Info.plist, AppIcon.icns, sgwebapp.json)"
else
  fail "Generated .app bundle is missing expected files"
fi

# 4. Test List
if "$BIN" list | grep -F "$TEST_APP_NAME" >/dev/null; then
  pass "sgwebapp list discovers installed web app"
else
  fail "sgwebapp list did not find installed web app"
fi

# 5. Test Border Daemon Lifecycle
if "$BIN" border start >/dev/null; then
  pass "sgwebapp border start starts daemon"
else
  fail "sgwebapp border start failed"
fi

if "$BIN" border status | grep -F "running" >/dev/null; then
  pass "sgwebapp border status reports running"
else
  fail "sgwebapp border status check failed"
fi

if "$BIN" border stop >/dev/null; then
  pass "sgwebapp border stop terminates daemon"
else
  fail "sgwebapp border stop failed"
fi

# 6. Test Removal
if "$BIN" remove "$TEST_APP_NAME" >/dev/null; then
  pass "sgwebapp remove command succeeded"
else
  fail "sgwebapp remove command failed"
fi

if [[ ! -d "$TARGET_APP" ]]; then
  pass "Target app bundle was completely deleted"
else
  fail "Target app bundle still exists after remove"
fi

echo ""
echo "Test Summary: $PASSED passed, $FAILED failed."
if (( FAILED > 0 )); then
  exit 1
fi
