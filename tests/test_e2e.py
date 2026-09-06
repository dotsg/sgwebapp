"""End-to-end test for the native runtime.

Installs a real .app against a throwaway local web server and drives it, to
prove three things that unit tests cannot: cookies staged by `import-cookies`
reach the page before its first request, `window.open` popups actually load,
and cookies for shared domains are written back to the jar.

Launches a GUI app, so it needs a logged-in desktop session.
"""

import http.server
import json
import os
import shutil
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SANDBOX = tempfile.mkdtemp(prefix="sgwebapp-e2e-")
CONFIG = os.path.join(SANDBOX, "config")
APPS = os.path.join(SANDBOX, "Applications")
for d in (CONFIG, APPS):
    os.makedirs(d, exist_ok=True)

hits = []
PAGE = """<!doctype html><meta charset=utf-8><title>e2e</title><script>
fetch('/report?cookie=' + encodeURIComponent(document.cookie));
window.open('/popup', '_blank');
</script><body>main</body>"""
POPUP = "<!doctype html><meta charset=utf-8><title>popup</title><body>popup loaded</body>"

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = urllib.parse.urlparse(self.path)
        hits.append(self.path)
        body = {"/": PAGE, "/popup": POPUP}.get(path.path, "ok")
        data = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *a): pass

srv = socketserver.TCPServer(("127.0.0.1", 0), H)
port = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
url = f"http://127.0.0.1:{port}/"
print("serving", url)

env = dict(os.environ, SGWEBAPP_CONFIG_DIR=CONFIG, SGWEBAPP_APPS_DIR=APPS)

# Treat the test host as a shared-login domain so the export path is exercised.
with open(os.path.join(CONFIG, "config.json"), "w") as f:
    json.dump({"share_login": True, "shared_cookie_domains": ["127.0.0.1"]}, f)
subprocess.run([f"{REPO}/bin/sgwebapp", "install", "E2ETest", url],
               env=env, check=True, capture_output=True)

meta = json.load(open(f"{APPS}/E2ETest.app/Contents/Resources/sgwebapp.json"))
bundle_id = meta["bundle_id"]
print("bundle id:", bundle_id)

# Stage a cookie exactly the way `sgwebapp import-cookies` does.
os.makedirs(f"{CONFIG}/pending", exist_ok=True)
jar = {"version": 1, "cookies": [{
    "name": "sgwebapp_e2e", "value": "injected-ok", "domain": "127.0.0.1",
    "path": "/", "expires": time.time() + 86400,
    "secure": False, "httpOnly": False, "sameSite": None,
}]}
with open(f"{CONFIG}/pending/{bundle_id}.json", "w") as f:
    json.dump(jar, f)

proc = subprocess.Popen([f"{APPS}/E2ETest.app/Contents/MacOS/E2ETest"], env=env,
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
# Long enough for the debounced post-navigation export (5s) to fire, so the
# jar is written even though the app is about to be killed rather than quit.
time.sleep(12)
proc.terminate()
try: proc.wait(timeout=5)
except subprocess.TimeoutExpired: proc.kill()
srv.shutdown()

jar_path = os.path.join(CONFIG, "cookiejar.json")
jar_names = []
jar_mode = None
if os.path.exists(jar_path):
    jar_names = [c["name"] for c in json.load(open(jar_path)).get("cookies", [])]
    jar_mode = oct(os.stat(jar_path).st_mode & 0o777)

print("\nrequests seen:")
for h in hits: print("  ", h[:120])

report = [h for h in hits if h.startswith("/report")]
cookie_value = ""
if report:
    q = urllib.parse.parse_qs(urllib.parse.urlparse(report[0]).query)
    cookie_value = q.get("cookie", [""])[0]

results = {
    "main page loaded": any(h == "/" for h in hits),
    "cookie injected before first load": "sgwebapp_e2e=injected-ok" in cookie_value,
    "window.open popup actually loaded": any(h == "/popup" for h in hits),
    "pending file consumed": not os.path.exists(f"{CONFIG}/pending/{bundle_id}.json"),
    "cookie exported back to the shared jar": "sgwebapp_e2e" in jar_names,
    "jar written with 0600 permissions": jar_mode == "0o600",
}
print("\ncookie header seen by page:", cookie_value or "(none)")
print("jar contents:", jar_names, "mode:", jar_mode)
print()
ok = True
for k, v in results.items():
    print(("  PASS: " if v else "  FAIL: ") + k)
    ok = ok and v
shutil.rmtree(SANDBOX, ignore_errors=True)
sys.exit(0 if ok else 1)
