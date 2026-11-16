#!/usr/bin/env python3
"""CI helper (macOS runner). Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.

  python3 scripts/ci/asc_profile.py install "Ghostline AppStore CI"
      -> downloads the profile into ~/Library/MobileDevice/Provisioning Profiles/<uuid>.mobileprovision
         and prints  PROFILE_UUID=... / PROFILE_NAME=...  (for $GITHUB_ENV)
  python3 scripts/ci/asc_profile.py app-id com.centricfiber.ghostline
      -> prints the App Store Connect app id, or nothing if the app record does not exist yet
"""
import base64, json, os, sys, time, urllib.parse, urllib.request
from pathlib import Path

import jwt  # PyJWT (pip install pyjwt cryptography)

BASE = "https://api.appstoreconnect.apple.com"


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900,
                       "aud": "appstoreconnect-v1"},
                      Path(os.environ["ASC_KEY_PATH"]).read_text(), algorithm="ES256",
                      headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def get(path):
    req = urllib.request.Request(BASE + path, headers={"Authorization": "Bearer " + token()})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def install(name):
    data = get("/v1/profiles?filter[name]=" + urllib.parse.quote(name) +
               "&fields[profiles]=name,uuid,profileContent,profileState")["data"]
    active = [p for p in data if p["attributes"]["profileState"] == "ACTIVE"]
    if not active:
        sys.exit(f"no ACTIVE profile named {name!r} (run scripts/ci/ios_signing_setup.py on Windows)")
    a = active[0]["attributes"]
    d = Path.home() / "Library/MobileDevice/Provisioning Profiles"
    d.mkdir(parents=True, exist_ok=True)
    (d / f"{a['uuid']}.mobileprovision").write_bytes(base64.b64decode(a["profileContent"]))
    print(f"PROFILE_UUID={a['uuid']}")
    print(f"PROFILE_NAME={a['name']}")


def app_id(bundle):
    data = get("/v1/apps?filter[bundleId]=" + urllib.parse.quote(bundle))["data"]
    for app in data:
        if app["attributes"]["bundleId"] == bundle:
            print(app["id"])
            return


if __name__ == "__main__":
    {"install": install, "app-id": app_id}[sys.argv[1]](sys.argv[2])
