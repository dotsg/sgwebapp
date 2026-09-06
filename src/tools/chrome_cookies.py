#!/usr/bin/env python3
"""Extract cookies from a Chromium browser profile into an sgwebapp cookie jar.

Chromium on macOS keeps cookies in a SQLite database whose values are encrypted
with AES-128-CBC. The key is derived from a password held in the login keychain
under "<Browser> Safe Storage", so reading it triggers a keychain prompt the
first time a given binary asks.

Everything is passed via argv; nothing is interpolated into a shell or into
source code.
"""

import argparse
import base64
import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile

# Chromium's fixed KDF parameters on macOS.
KDF_SALT = b"saltysalt"
KDF_ITERATIONS = 1003
KDF_KEY_LENGTH = 16
AES_IV = b" " * 16

# Chrome timestamps are microseconds since 1601-01-01.
CHROME_EPOCH_OFFSET = 11644473600

BROWSERS = {
    "chrome": ("Google/Chrome", "Chrome Safe Storage", "Chrome"),
    "brave": ("BraveSoftware/Brave-Browser", "Brave Safe Storage", "Brave"),
    "edge": ("Microsoft Edge", "Microsoft Edge Safe Storage", "Microsoft Edge"),
    "chromium": ("Chromium", "Chromium Safe Storage", "Chromium"),
}


class ExtractError(Exception):
    pass


def keychain_password(service, account):
    try:
        out = subprocess.run(
            ["security", "find-generic-password", "-w", "-s", service, "-a", account],
            capture_output=True, check=True,
        )
    except FileNotFoundError:
        raise ExtractError("`security` command not found; is this macOS?")
    except subprocess.CalledProcessError:
        raise ExtractError(
            f"Could not read '{service}' from the login keychain.\n"
            "  Either the browser has never run, or you denied the keychain prompt.\n"
            "  Re-run and choose Allow when macOS asks."
        )
    return out.stdout.decode("utf-8").rstrip("\n")


def derive_key(password):
    return hashlib.pbkdf2_hmac(
        "sha1", password.encode("utf-8"), KDF_SALT, KDF_ITERATIONS, KDF_KEY_LENGTH
    )


def aes_cbc_decrypt(key, ciphertext):
    """Decrypt with openssl; macOS ships LibreSSL and Python has no AES."""
    proc = subprocess.run(
        ["openssl", "enc", "-d", "-aes-128-cbc", "-nopad",
         "-K", key.hex(), "-iv", AES_IV.hex()],
        input=ciphertext, capture_output=True,
    )
    if proc.returncode != 0:
        raise ExtractError("openssl failed: " + proc.stderr.decode("utf-8", "replace").strip())
    return proc.stdout


def strip_pkcs7(data):
    if not data:
        return data
    pad = data[-1]
    if 1 <= pad <= 16 and data[-pad:] == bytes([pad]) * pad:
        return data[:-pad]
    return data


def decrypt_value(key, encrypted, plain_value):
    if plain_value:
        return plain_value
    if not encrypted:
        return ""
    if encrypted[:3] not in (b"v10", b"v11"):
        # Not encrypted at all (very old profiles).
        return encrypted.decode("utf-8", "replace")

    plaintext = strip_pkcs7(aes_cbc_decrypt(key, encrypted[3:]))

    # Chrome 118+ prefixes the plaintext with a 32-byte SHA-256 of the eTLD+1.
    # There is no version flag for it, so fall back to stripping when the value
    # does not decode cleanly as text.
    try:
        return plaintext.decode("utf-8")
    except UnicodeDecodeError:
        return plaintext[32:].decode("utf-8", "replace")


def host_matches(host_key, domains):
    host = host_key[1:] if host_key.startswith(".") else host_key
    host = host.lower()
    for d in domains:
        d = d.lower().lstrip(".")
        if host == d or host.endswith("." + d):
            return True
    return False


def read_cookies(db_path, key, domains):
    # Chrome holds a lock on the live database; work on a copy.
    with tempfile.TemporaryDirectory() as tmp:
        copy = os.path.join(tmp, "Cookies")
        shutil.copy2(db_path, copy)
        for suffix in ("-wal", "-shm"):
            side = db_path + suffix
            if os.path.exists(side):
                shutil.copy2(side, copy + suffix)

        conn = sqlite3.connect(copy)
        try:
            rows = conn.execute(
                "SELECT host_key, name, value, encrypted_value, path, "
                "       expires_utc, is_secure, is_httponly, samesite "
                "FROM cookies"
            ).fetchall()
        finally:
            conn.close()

    cookies = []
    skipped = 0
    for host_key, name, value, encrypted_value, path, expires_utc, secure, httponly, samesite in rows:
        if domains and not host_matches(host_key, domains):
            continue
        try:
            decrypted = decrypt_value(key, encrypted_value, value)
        except ExtractError:
            skipped += 1
            continue
        if not decrypted:
            skipped += 1
            continue

        # Session cookies (expires_utc == 0) cannot be replayed usefully.
        if not expires_utc:
            skipped += 1
            continue
        expires = expires_utc / 1_000_000 - CHROME_EPOCH_OFFSET
        if expires <= 0:
            skipped += 1
            continue

        cookies.append({
            "name": name,
            "value": decrypted,
            "domain": host_key,
            "path": path or "/",
            "expires": expires,
            "secure": bool(secure),
            "httpOnly": bool(httponly),
            "sameSite": {1: "Lax", 2: "Strict"}.get(samesite),
        })
    return cookies, skipped


def main():
    ap = argparse.ArgumentParser(description="Extract Chromium cookies into an sgwebapp jar.")
    ap.add_argument("--browser", default="chrome", choices=sorted(BROWSERS))
    ap.add_argument("--profile", default="Default")
    ap.add_argument("--domain", action="append", default=[],
                    help="Only export cookies for this domain (repeatable). Required unless --all-domains.")
    ap.add_argument("--all-domains", action="store_true")
    ap.add_argument("--out", required=True, help="Destination jar JSON file ('-' for stdout).")
    ap.add_argument("--cookie-db", help="Override the path to the Cookies database.")
    args = ap.parse_args()

    if not args.domain and not args.all_domains:
        ap.error("give at least one --domain, or --all-domains to export everything")

    subdir, service, account = BROWSERS[args.browser]
    db_path = args.cookie_db or os.path.expanduser(
        f"~/Library/Application Support/{subdir}/{args.profile}/Cookies"
    )
    if not os.path.exists(db_path):
        raise ExtractError(f"No cookie database at {db_path}")

    key = derive_key(keychain_password(service, account))
    cookies, skipped = read_cookies(db_path, key, [] if args.all_domains else args.domain)

    jar = {"version": 1, "cookies": cookies}
    payload = json.dumps(jar, indent=2)
    if args.out == "-":
        sys.stdout.write(payload)
    else:
        os.makedirs(os.path.dirname(os.path.abspath(args.out)) or ".", exist_ok=True)
        # Cookies are credentials: never let the jar exist world-readable.
        fd = os.open(args.out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(payload)

    print(f"exported {len(cookies)} cookies ({skipped} skipped)", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except ExtractError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)
