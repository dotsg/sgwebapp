#!/usr/bin/env python3
"""Unit tests for the Chromium cookie extractor.

Builds a synthetic cookie database encrypted with a known key, so the AES/KDF
path is exercised without touching the real Chrome profile or the keychain.
"""

import hashlib
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "tools"))
import chrome_cookies as cc  # noqa: E402

PASSWORD = "unit-test-password"
FUTURE = int((1_800_000_000 + cc.CHROME_EPOCH_OFFSET) * 1_000_000)


def encrypt(key, plaintext, hash_prefix=None):
    data = plaintext
    if hash_prefix is not None:
        data = hashlib.sha256(hash_prefix).digest() + data
    pad = 16 - (len(data) % 16)
    data += bytes([pad]) * pad
    proc = subprocess.run(
        ["openssl", "enc", "-e", "-aes-128-cbc", "-nopad",
         "-K", key.hex(), "-iv", cc.AES_IV.hex()],
        input=data, capture_output=True, check=True,
    )
    return b"v10" + proc.stdout


class ExtractorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.key = cc.derive_key(PASSWORD)
        cls.tmp = tempfile.TemporaryDirectory()
        cls.db = os.path.join(cls.tmp.name, "Cookies")
        conn = sqlite3.connect(cls.db)
        conn.execute(
            "CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, "
            "encrypted_value BLOB, path TEXT, expires_utc INTEGER, "
            "is_secure INTEGER, is_httponly INTEGER, samesite INTEGER)"
        )
        rows = [
            (".google.com", "SID", "", encrypt(cls.key, b"secret-sid"), "/", FUTURE, 1, 1, 1),
            (".google.com", "HASHED", "", encrypt(cls.key, b"m118-value", b"google.com"), "/", FUTURE, 1, 1, 2),
            (".github.com", "user_session", "", encrypt(cls.key, b"gh-token"), "/", FUTURE, 1, 1, 0),
            (".evil.example", "leak", "", encrypt(cls.key, b"other-site"), "/", FUTURE, 0, 0, 0),
            (".google.com", "SESSIONONLY", "", encrypt(cls.key, b"transient"), "/", 0, 0, 0, 0),
            (".google.com", "PLAIN", "unencrypted", b"", "/", FUTURE, 0, 0, 0),
            (".google.com", "EXPIRED", "", encrypt(cls.key, b"old"), "/", 1, 0, 0, 0),
        ]
        conn.executemany("INSERT INTO cookies VALUES (?,?,?,?,?,?,?,?,?)", rows)
        conn.commit()
        conn.close()

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def extract(self, domains):
        cookies, _ = cc.read_cookies(self.db, self.key, domains)
        return {c["name"]: c for c in cookies}

    def test_decrypts_standard_value(self):
        self.assertEqual(self.extract(["google.com"])["SID"]["value"], "secret-sid")

    def test_strips_chrome_118_hash_prefix(self):
        self.assertEqual(self.extract(["google.com"])["HASHED"]["value"], "m118-value")

    def test_passes_through_unencrypted_value(self):
        self.assertEqual(self.extract(["google.com"])["PLAIN"]["value"], "unencrypted")

    def test_domain_filter_excludes_other_sites(self):
        self.assertNotIn("leak", self.extract(["google.com", "github.com"]))

    def test_subdomain_matches_registrable_domain(self):
        self.assertIn("user_session", self.extract(["github.com"]))

    def test_skips_session_and_expired_cookies(self):
        got = self.extract(["google.com"])
        self.assertNotIn("SESSIONONLY", got)
        self.assertNotIn("EXPIRED", got)

    def test_preserves_flags_and_expiry(self):
        sid = self.extract(["google.com"])["SID"]
        self.assertTrue(sid["secure"])
        self.assertTrue(sid["httpOnly"])
        self.assertEqual(sid["sameSite"], "Lax")
        self.assertAlmostEqual(sid["expires"], 1_800_000_000, places=3)

    def test_samesite_strict_mapping(self):
        self.assertEqual(self.extract(["google.com"])["HASHED"]["sameSite"], "Strict")

    def test_host_matching_rules(self):
        self.assertTrue(cc.host_matches(".google.com", ["google.com"]))
        self.assertTrue(cc.host_matches("mail.google.com", ["google.com"]))
        self.assertFalse(cc.host_matches("notgoogle.com", ["google.com"]))
        self.assertFalse(cc.host_matches("google.com.evil.net", ["google.com"]))

    def test_pkcs7_stripping(self):
        self.assertEqual(cc.strip_pkcs7(b"abc" + bytes([13]) * 13), b"abc")
        self.assertEqual(cc.strip_pkcs7(b"nopadding-here!!"), b"nopadding-here!!")


if __name__ == "__main__":
    unittest.main(verbosity=2)
