# Logins, cookies and the two engines

## Why there are two engines

On Linux, Omarchy gets a frameless web app by launching `chrome --app` under a
compositor that simply draws no decorations. macOS has no equivalent: the
traffic lights are `NSWindow` buttons drawn by AppKit **inside the browser's own
process**. Removing them from a Chrome window would require injecting code into
Chrome, which in practice means disabling SIP.

So the trade-off is real and cannot be engineered away:

| | Frameless (no traffic lights) | Reuses Chrome's live session |
|---|---|---|
| `--engine native` (default) | yes | no — it has its own WebKit profile |
| `--engine chrome` | no | yes |

The native engine is the default. The Chrome engine is kept as an escape hatch
for the cases WebKit genuinely cannot serve:

- Widevine DRM (Netflix, Spotify Web) does not play in WKWebView.
- Passkeys or enterprise SSO already bound to the Chrome profile.
- Sites you rely on a Chrome extension (uBlock, a password manager) for.

## What "native needs a new login" actually means

Each native app is a separate macOS bundle, and WebKit stores website data under
`~/Library/WebKit/<bundle-id>/`. That path is derived from the bundle identifier
and cannot be redirected through public API — `WKWebsiteDataStore(forIdentifier:)`
only namespaces stores *within* one app, it does not let two apps share one.
So every native web app starts out logged out.

Two mechanisms reduce that cost.

### 1. Seed a login from Chrome — `sgwebapp import-cookies`

```bash
sgwebapp import-cookies "Solaree"                 # its own domain
sgwebapp import-cookies "Gmail" --domain google.com
sgwebapp import-cookies "X" --browser brave --profile "Profile 1"
sgwebapp import-cookies "Solaree" --dry-run       # show the domains, prompt nothing
```

`--dry-run` prints which domains would be read and where the result would be
staged, without touching the keychain. The domain is derived from the app's URL,
which handles IP literals and two-label suffixes such as `com.cn` — worth
checking with `--dry-run` first if the app points at something unusual.

This reads the Chromium cookie database, decrypts it, and stages the cookies at
`~/.config/sgwebapp/pending/<bundle-id>.json`. The next launch injects them
before the first page request, then deletes the staging file.

What you should know before using it:

- **It prompts for keychain access.** The AES key lives in the login keychain as
  "Chrome Safe Storage". macOS will ask; choose Allow. Because the binaries are
  not signed with a stable identity, the prompt can reappear after a rebuild.
- **Only cookies are copied.** Sites that keep their session token in
  `localStorage` or `IndexedDB` — many modern single-page apps — will still ask
  you to sign in. Cookie import is not a general session transfer.
- **It is scoped by default.** With no `--domain`, only the app's own
  registrable domain is exported, so an import never sweeps up unrelated
  credentials.
- **This is the same read that credential-stealing malware performs.** It is
  never done automatically; it only runs when you type the command.

### 2. Share SSO cookies between sgwebapp apps — the jar

Apps cannot share a data store, but they can share cookies. Each native app
imports the jar at launch and merges its own cookies back after each navigation
(and on quit). The practical effect: sign in to Google once in any sgwebapp app,
and the other Google-backed apps are signed in too.

Only cookies whose domain matches the shared list are ever written to the jar:

```
google.com  accounts.google.com  github.com  githubusercontent.com
login.microsoftonline.com  microsoft.com  live.com  appleid.apple.com
okta.com  auth0.com  slack.com  atlassian.com
```

Override or narrow it:

```bash
sgwebapp config set shared_cookie_domains "google.com,github.com"
sgwebapp config set share_login false        # turn syncing off entirely
sgwebapp install "Work" https://... --no-share-login   # per app
sgwebapp cookies status                      # what is in the jar
sgwebapp cookies clear                       # wipe it
```

### Storage and risk

The jar is `~/.config/sgwebapp/cookiejar.json`, written `0600`, in plaintext
JSON. That is weaker than Chrome, which encrypts cookie values at rest with a
keychain-held key. Anything running as your user can read it — which is also
true of Chrome's database, since the same user can request the same keychain
item, but the jar removes even that speed bump.

If that trade is not one you want, `sgwebapp config set share_login false`
disables the jar entirely; each app then keeps its own login and nothing is
written outside WebKit's own storage.
