#!/bin/bash
# test_suite.sh - Automated test suite for sgwebapp
#
# The suite runs entirely inside a temporary HOME-like sandbox: it never reads
# or writes the developer's real ~/.config/sgwebapp or ~/Applications.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$PROJECT_ROOT/bin/sgwebapp"

SANDBOX="$(mktemp -d)"
export SGWEBAPP_CONFIG_DIR="$SANDBOX/config"
export SGWEBAPP_APPS_DIR="$SANDBOX/Applications"
mkdir -p "$SGWEBAPP_CONFIG_DIR" "$SGWEBAPP_APPS_DIR"

TEST_APP_NAME="SGWebAppTestDummy"
TEST_APP_URL="https://example.com"
TARGET_APP="$SGWEBAPP_APPS_DIR/$TEST_APP_NAME.app"

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

check() {
  # check <description> <command...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

cleanup() {
  "$BIN" border stop >/dev/null 2>&1 || true
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

echo "Running sgwebapp test suite (sandbox: $SANDBOX)..."

# ---------------------------------------------------------------- basics
check "sgwebapp help command exits cleanly" "$BIN" help

version_out=$("$BIN" version)
if grep -q "sgwebapp version" <<<"$version_out"; then
  pass "sgwebapp version reports valid version"
else
  fail "sgwebapp version command failed"
fi

check "make build compiles the Swift binaries" make -C "$PROJECT_ROOT" build

# make runs each recipe line in its own shell, so an early `exit 0` does not
# skip the following line: `make lint` must still succeed without shellcheck.
check "make lint succeeds whether or not shellcheck is installed" make -C "$PROJECT_ROOT" lint

# ---------------------------------------------------------------- install
check "sgwebapp install command succeeded" "$BIN" install "$TEST_APP_NAME" "$TEST_APP_URL"

if [[ -d "$TARGET_APP" && ( -f "$TARGET_APP/Contents/MacOS/$TEST_APP_NAME" || -f "$TARGET_APP/Contents/MacOS/launcher" ) && -f "$TARGET_APP/Contents/Info.plist" && -f "$TARGET_APP/Contents/Resources/AppIcon.icns" && -f "$TARGET_APP/Contents/Resources/sgwebapp.json" ]]; then
  pass "Generated .app bundle has all required files"
else
  fail "Generated .app bundle is missing expected files"
fi

if plutil -lint "$TARGET_APP/Contents/Info.plist" >/dev/null 2>&1; then
  pass "Generated Info.plist is valid property list XML"
else
  fail "Generated Info.plist is malformed"
fi

if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$TARGET_APP/Contents/Resources/sgwebapp.json" 2>/dev/null; then
  pass "Generated sgwebapp.json is valid JSON"
else
  fail "Generated sgwebapp.json is malformed"
fi

# An ampersand in the name and URL must not corrupt the plist or the metadata.
AMP_NAME='Rock & Roll "quoted"'
if "$BIN" install "$AMP_NAME" "https://example.com/?a=1&b=2" >/dev/null 2>&1 \
   && plutil -lint "$SGWEBAPP_APPS_DIR/$AMP_NAME.app/Contents/Info.plist" >/dev/null 2>&1 \
   && python3 -c "import json,sys; json.load(open(sys.argv[1]))" \
        "$SGWEBAPP_APPS_DIR/$AMP_NAME.app/Contents/Resources/sgwebapp.json" >/dev/null 2>&1; then
  pass "Names and URLs containing & and quotes produce valid plist and JSON"
else
  fail "Special characters in name/URL corrupt the generated bundle"
fi
rm -rf "$SGWEBAPP_APPS_DIR/$AMP_NAME.app"

# Two apps whose names have no ASCII letters must not collide on bundle id.
"$BIN" install "微博" "https://weibo.com" >/dev/null 2>&1 || true
"$BIN" install "知乎" "https://zhihu.com" >/dev/null 2>&1 || true
id_a=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['bundle_id'])" \
        "$SGWEBAPP_APPS_DIR/微博.app/Contents/Resources/sgwebapp.json" 2>/dev/null || echo a)
id_b=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['bundle_id'])" \
        "$SGWEBAPP_APPS_DIR/知乎.app/Contents/Resources/sgwebapp.json" 2>/dev/null || echo a)
if [[ "$id_a" != "$id_b" ]]; then
  pass "Non-ASCII app names get distinct bundle identifiers ($id_a vs $id_b)"
else
  fail "Non-ASCII app names collide on bundle identifier ($id_a)"
fi
rm -rf "$SGWEBAPP_APPS_DIR/微博.app" "$SGWEBAPP_APPS_DIR/知乎.app"

# ---------------------------------------------------------------- safety
if "$BIN" install "$TEST_APP_NAME" "$TEST_APP_URL" --engine bogus >/dev/null 2>&1; then
  fail "install accepted an invalid --engine value"
else
  pass "install rejects an invalid --engine value"
fi

if "$BIN" install "X" "https://example.com" --engine >/dev/null 2>&1; then
  fail "install accepted an option with no value"
else
  pass "install reports a clear error for a valueless option"
fi

# A foreign .app in the apps dir must never be overwritten or deleted.
FOREIGN="$SGWEBAPP_APPS_DIR/NotOurs.app"
mkdir -p "$FOREIGN/Contents"
echo "original" > "$FOREIGN/Contents/marker"
if "$BIN" install "NotOurs" "https://example.com" >/dev/null 2>&1; then
  fail "install overwrote an app bundle it did not create"
else
  if [[ -f "$FOREIGN/Contents/marker" ]]; then
    pass "install refuses to overwrite a foreign .app bundle"
  else
    fail "install damaged a foreign .app bundle"
  fi
fi
if "$BIN" remove "NotOurs" >/dev/null 2>&1; then
  fail "remove deleted an app bundle it did not create"
else
  pass "remove refuses to delete a foreign .app bundle"
fi
rm -rf "$FOREIGN"

# Path traversal through the app name must be rejected before rm -rf runs.
CANARY="$SANDBOX/canary.app"
mkdir -p "$CANARY"
if "$BIN" remove "../canary" >/dev/null 2>&1; then
  fail "remove accepted a traversing app name"
else
  if [[ -d "$CANARY" ]]; then
    pass "remove rejects path traversal in the app name"
  else
    fail "remove deleted a file outside the apps directory"
  fi
fi

# A crafted config key must not be able to execute code.
MARKER="$SANDBOX/pwned"
"$BIN" config set "x'] = 1; __import__('os').system('touch $MARKER'); data['y" 1 >/dev/null 2>&1 || true
if [[ -e "$MARKER" ]]; then
  fail "config set executes code embedded in the key (injection)"
else
  pass "config set does not execute code embedded in the key"
fi

# ---------------------------------------------------------------- list
list_out=$("$BIN" list)
if grep -F "$TEST_APP_NAME" <<<"$list_out" >/dev/null; then
  pass "sgwebapp list discovers installed web app"
else
  fail "sgwebapp list did not find installed web app"
fi

# ---------------------------------------------------------------- border daemon
check "sgwebapp border start starts daemon" "$BIN" border start

border_out=$("$BIN" border status)
if grep -F "running" <<<"$border_out" >/dev/null; then
  pass "sgwebapp border status reports running"
else
  fail "sgwebapp border status check failed"
fi

check "sgwebapp border stop terminates daemon" "$BIN" border stop

# ---------------------------------------------------------------- config
cfg_out=$("$BIN" config)
if grep -q "padding:" <<<"$cfg_out"; then
  pass "sgwebapp config outputs padding setting"
else
  fail "sgwebapp config missing padding output"
fi

"$BIN" config set padding 10.0 >/dev/null
cfg_out=$("$BIN" config)
if grep -q "10.0 pt" <<<"$cfg_out"; then
  pass "sgwebapp config set padding successfully updated configuration"
else
  fail "sgwebapp config set padding failed"
fi

"$BIN" config set share_login false >/dev/null
cfg_out=$("$BIN" config)
if grep -q "share_login:   false" <<<"$cfg_out"; then
  pass "sgwebapp config set share_login stores a real boolean"
else
  fail "sgwebapp config set share_login failed"
fi

if "$BIN" config set nonsense_key 1 >/dev/null 2>&1; then
  fail "config set accepted an unknown key"
else
  pass "config set rejects an unknown key"
fi

"$BIN" config reset >/dev/null
cfg_out=$("$BIN" config)
if grep -q "8.0 pt" <<<"$cfg_out"; then
  pass "sgwebapp config reset restored default 8.0pt padding"
else
  fail "sgwebapp config reset failed"
fi

# ---------------------------------------------------------------- cookies
cookies_out=$("$BIN" cookies status)
if grep -q "cookie jar" <<<"$cookies_out"; then
  pass "sgwebapp cookies status runs with no jar present"
else
  fail "sgwebapp cookies status failed"
fi

check "sgwebapp cookies clear runs cleanly" "$BIN" cookies clear

if "$BIN" import-cookies "NoSuchApp" >/dev/null 2>&1; then
  fail "import-cookies accepted an unknown app name"
else
  pass "import-cookies rejects an unknown app name"
fi

# Domain resolution feeds the cookie filter: getting it wrong silently exports
# nothing (an IP) or too much (a country-code suffix).
domain_case() {
  # domain_case <app> <url> <expected domain>
  local app="$1" url="$2" want="$3"
  "$BIN" install "$app" "$url" >/dev/null 2>&1
  local out
  out=$("$BIN" import-cookies "$app" --dry-run 2>/dev/null || echo "")
  if grep -q "cookies for: $want\b" <<<"$out"; then
    pass "import-cookies resolves $url to $want"
  else
    fail "import-cookies resolved $url to the wrong domain (wanted $want): $out"
  fi
  rm -rf "$SGWEBAPP_APPS_DIR/$app.app"
}
domain_case "DomIP"    "http://127.0.0.1:8080/app"    "127.0.0.1"
domain_case "DomCCTLD" "https://news.sina.com.cn/x"   "sina.com.cn"
domain_case "DomPlain" "https://mail.google.com/mail" "google.com"

# The helper script must be located before anything else runs.
if "$BIN" import-cookies "$TEST_APP_NAME" --dry-run >/dev/null 2>&1; then
  pass "import-cookies --dry-run works without touching the keychain"
else
  fail "import-cookies --dry-run failed"
fi

# ---------------------------------------------------------------- cookie extractor
if python3 "$SCRIPT_DIR/test_chrome_cookies.py" >/dev/null 2>&1; then
  pass "Chrome cookie decryption round-trips (AES-CBC, padding, hash prefix)"
else
  fail "Chrome cookie decryption unit test failed"
fi

# ---------------------------------------------------------------- removal
check "sgwebapp remove command succeeded" "$BIN" remove "$TEST_APP_NAME"

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
