#!/usr/bin/env python3
"""Uploads the release-signing secrets to GitHub Actions.

Reads `shelflife_app/android/key.properties` — which is gitignored and which
you create — and pushes the keystore and its passwords to the repository as
encrypted Actions secrets. Each value is sealed against the repository's own
public key before it leaves this machine.

Why this script exists rather than instructions: the keystore password should
not be pasted into a chat, an issue, or a terminal transcript. Run this and it
never appears anywhere but the file you wrote and GitHub's encrypted store.

Why the signing key matters more than it looks: without it, CI falls back to a
debug key, and a GitHub runner generates its *own* debug keystore. Google ties
an Android OAuth client to one signing certificate, so a debug-signed CI build
fails Google sign-in regardless of which SHA-1 you registered.

Prerequisites
    1. A keystore, created by you (see INSTALL.md):
         keytool -genkey -v -keystore ~/shelflife-release.jks \\
           -keyalg RSA -keysize 2048 -validity 10000 -alias shelflife
    2. shelflife_app/android/key.properties pointing at it.
    3. `pip install pynacl`

Usage
    python tools/upload_signing_secrets.py
"""

from __future__ import annotations

import base64
import json
import pathlib
import subprocess
import sys
import urllib.request

REPO = 'RKP-boop/shelf-life'
ROOT = pathlib.Path(__file__).resolve().parents[1]
PROPS = ROOT / 'shelflife_app' / 'android' / 'key.properties'


def read_properties() -> dict[str, str]:
    if not PROPS.exists():
        raise SystemExit(
            f'{PROPS.relative_to(ROOT)} not found.\n'
            'Create the keystore and that file first -- see INSTALL.md.')
    values: dict[str, str] = {}
    for line in PROPS.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, _, value = line.partition('=')
        values[key.strip()] = value.strip()

    missing = [k for k in ('storePassword', 'keyPassword', 'keyAlias',
                           'storeFile') if not values.get(k)]
    if missing:
        raise SystemExit(f'key.properties is missing: {", ".join(missing)}')
    return values


def keystore_path(props: dict[str, str]) -> pathlib.Path:
    raw = pathlib.Path(props['storeFile'])
    # storeFile may be absolute, or relative to the android/ directory the way
    # Gradle resolves it.
    for candidate in (raw, PROPS.parent / raw):
        if candidate.exists():
            return candidate
    raise SystemExit(f'keystore not found at {props["storeFile"]}')


def token() -> str:
    proc = subprocess.run(
        ['git', 'credential', 'fill'],
        input='protocol=https\nhost=github.com\n\n',
        capture_output=True, text=True, timeout=60)
    creds = dict(l.split('=', 1) for l in proc.stdout.splitlines() if '=' in l)
    if 'password' not in creds:
        raise SystemExit('no GitHub credential available; push once first')
    return creds['password']


def api(method: str, path: str, tok: str, body: dict | None = None):
    req = urllib.request.Request(
        f'https://api.github.com{path}', method=method,
        data=json.dumps(body).encode() if body else None,
        headers={'Authorization': f'Bearer {tok}',
                 'Accept': 'application/vnd.github+json',
                 'Content-Type': 'application/json',
                 'User-Agent': 'shelflife-signing'})
    with urllib.request.urlopen(req, timeout=30) as r:
        raw = r.read()
        return r.status, (json.loads(raw) if raw else None)


def main() -> int:
    try:
        from nacl import encoding, public
    except ImportError:
        raise SystemExit('pip install pynacl')

    props = read_properties()
    jks = keystore_path(props)

    secrets = {
        'ANDROID_KEYSTORE_BASE64':
            base64.b64encode(jks.read_bytes()).decode(),
        'ANDROID_KEYSTORE_PASSWORD': props['storePassword'],
        'ANDROID_KEY_PASSWORD': props['keyPassword'],
        'ANDROID_KEY_ALIAS': props['keyAlias'],
    }

    tok = token()
    _, key = api('GET', f'/repos/{REPO}/actions/secrets/public-key', tok)
    pk = public.PublicKey(key['key'].encode(), encoding.Base64Encoder())
    box = public.SealedBox(pk)

    print(f'keystore : {jks}  ({jks.stat().st_size / 1024:.1f} KB)')
    print(f'alias    : {props["keyAlias"]}')
    print('passwords: read from key.properties, never printed\n')

    for name, value in secrets.items():
        sealed = base64.b64encode(box.encrypt(value.encode())).decode()
        status, _ = api('PUT', f'/repos/{REPO}/actions/secrets/{name}', tok,
                        {'encrypted_value': sealed, 'key_id': key['key_id']})
        print(f'  {name:28} {"created" if status == 201 else "updated"}')

    print('\nNext: register this keystore\'s SHA-1 with the Android OAuth '
          'client,\nthen run the workflow. Get the fingerprint with:\n'
          '  python tools/signing_fingerprints.py')
    return 0


if __name__ == '__main__':
    sys.exit(main())
