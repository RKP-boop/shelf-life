#!/usr/bin/env python3
"""Creates the release signing key and pushes it to CI, in one command.

Run this yourself rather than having it run for you: it asks for a password,
and a password should not pass through an agent, a chat transcript, or your
shell history. Everything either side of that one prompt is automated.

    python tools/setup_signing.py                      # prompts for a password
    python tools/setup_signing.py --generate-password  # mints a random one

What it does, in order:

    1. Creates ~/shelflife-release.jks with a 2048-bit RSA key.
    2. Writes shelflife_app/android/key.properties pointing at it (gitignored).
    3. Seals the keystore and passwords against the repository public key and
       uploads them as GitHub Actions secrets.
    4. Prints the certificate SHA-1 that Google needs.

Why any of this matters: without a stable signing key, CI falls back to a debug
key that the GitHub runner generates itself. Every build is then a different
app -- Android refuses to update across signing keys -- and Google ties an
OAuth client to one certificate, so sign-in fails no matter which fingerprint
was registered.

The keystore is the one artefact here that cannot be regenerated. Lose it and
the installed app can never be updated, only uninstalled and replaced. Back it
up somewhere safe before shipping the APK to anyone.
"""

from __future__ import annotations

import base64
import getpass
import pathlib
import re
import secrets
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import signing_fingerprints as fp
import upload_signing_secrets as up

ROOT = pathlib.Path(__file__).resolve().parents[1]
KEYSTORE = pathlib.Path.home() / 'shelflife-release.jks'
PROPS = ROOT / 'shelflife_app' / 'android' / 'key.properties'
ALIAS = 'shelflife'

# 27 years. Google Play requires a key valid past 2033; this clears it, and a
# key that expires mid-life is a key that orphans its own app.
VALIDITY_DAYS = '10000'

# No identity questions: none of the nine fields keytool asks for affect a
# self-signed Android key, and skipping them removes nine chances to typo.
DNAME = 'CN=ShelfLife, OU=ShelfLife, O=ShelfLife, C=IN'

NL = chr(10)


def die(message: str) -> None:
    raise SystemExit(NL + '  ' + message + NL)


def generate_password() -> str:
    """Mints the keystore password instead of asking for one.

    Legitimate because this is a build credential, not a personal one: it
    protects a signing key that lives in a gitignored file and in GitHub's
    encrypted secret store, and nothing else in the world uses it. A random 32
    characters is stronger than anything a person would choose and type twice,
    and it means the password never has to travel through a terminal, a
    transcript, or somebody's memory.

    secrets.token_urlsafe, not random: this seeds from the OS entropy pool.
    """
    return secrets.token_urlsafe(24)


def ask_password() -> str:
    print('Choose a password for the signing key.')
    print('Nothing is echoed as you type, and it is never printed or logged.')
    print('Write it down somewhere safe -- it is needed to build again.')
    print('')
    for _ in range(3):
        first = getpass.getpass('  Password (6+ characters): ')
        if len(first) < 6:
            print('  Too short -- keytool requires at least 6.' + NL)
            continue
        if first != getpass.getpass('  Again: '):
            print('  Those did not match.' + NL)
            continue
        return first
    die('Giving up after three attempts. Nothing was created.')
    raise AssertionError('unreachable')


def create_keystore(tool: str, password: str) -> None:
    """Runs keytool with the password on stdin, never on the command line.

    -storepass would work and is what most guides show, but command-line
    arguments are readable from the process table by anything running as this
    user for as long as keytool lives. stdin is not.

    The password is fed twice because keytool asks for it and then to confirm
    it. The keystore is PKCS12 (the default since JDK 9), where the key
    password must equal the store password, so it never asks a third time.
    """
    proc = subprocess.run(
        [tool, '-genkeypair',
         '-keystore', str(KEYSTORE),
         '-alias', ALIAS,
         '-keyalg', 'RSA', '-keysize', '2048',
         '-validity', VALIDITY_DAYS,
         '-dname', DNAME],
        input=password + NL + password + NL,
        capture_output=True, text=True, timeout=180)
    if proc.returncode != 0 or not KEYSTORE.exists():
        die('keytool failed:' + NL + NL + (proc.stderr or proc.stdout).strip())


def write_properties(password: str) -> None:
    """Forward slashes even on Windows: a backslash is an escape here."""
    PROPS.parent.mkdir(parents=True, exist_ok=True)
    store = str(KEYSTORE).replace(chr(92), '/')
    PROPS.write_text(
        '# Created by tools/setup_signing.py. Gitignored -- never commit.' + NL
        + 'storePassword=' + password + NL
        + 'keyPassword=' + password + NL
        + 'keyAlias=' + ALIAS + NL
        + 'storeFile=' + store + NL,
        encoding='utf-8')


def read_fingerprint(tool: str, password: str) -> str | None:
    proc = subprocess.run(
        [tool, '-list', '-v', '-keystore', str(KEYSTORE), '-alias', ALIAS],
        input=password + NL, capture_output=True, text=True, timeout=60)
    match = re.search(r'SHA1:\s*([0-9A-F:]+)', proc.stdout, re.IGNORECASE)
    return match.group(1) if match else None


def upload() -> None:
    """Reuses the sealed-box upload rather than reimplementing it."""
    try:
        from nacl import encoding, public
    except ImportError:
        die('pip install pynacl, then run tools/upload_signing_secrets.py. '
            'The keystore already exists by this point, so re-running this '
            'script would stop rather than overwrite it.')

    props = up.read_properties()
    jks = up.keystore_path(props)
    payload = {
        'ANDROID_KEYSTORE_BASE64': base64.b64encode(jks.read_bytes()).decode(),
        'ANDROID_KEYSTORE_PASSWORD': props['storePassword'],
        'ANDROID_KEY_PASSWORD': props['keyPassword'],
        'ANDROID_KEY_ALIAS': props['keyAlias'],
    }
    tok = up.token()
    _, key = up.api('GET', '/repos/' + up.REPO + '/actions/secrets/public-key',
                    tok)
    box = public.SealedBox(
        public.PublicKey(key['key'].encode(), encoding.Base64Encoder()))
    for name, value in payload.items():
        sealed = base64.b64encode(box.encrypt(value.encode())).decode()
        status, _ = up.api(
            'PUT', '/repos/' + up.REPO + '/actions/secrets/' + name, tok,
            {'encrypted_value': sealed, 'key_id': key['key_id']})
        verb = 'created' if status == 201 else 'updated'
        print('       ' + name.ljust(28) + verb)


def main() -> int:
    tool = fp.keytool()
    if tool is None:
        die('keytool not found. It ships with the JDK -- set JAVA_HOME or put '
            'it on PATH.')

    if KEYSTORE.exists():
        # Overwriting is unrecoverable: the old certificate is the only thing
        # that can sign an update to an already-installed app.
        die(str(KEYSTORE) + ' already exists.' + NL
            + '  Not touching it -- overwriting a keystore orphans every '
              'install signed with it.' + NL
            + '  To reuse it: python tools/upload_signing_secrets.py')

    generated = '--generate-password' in sys.argv
    if generated:
        password = generate_password()
        print('Generating the keystore password rather than asking for one.')
        print('It is written to android/key.properties and uploaded to GitHub')
        print('as an encrypted secret. Nothing else uses it.' + NL)
    else:
        password = ask_password()

    print(NL + '  1/4  creating the keystore')
    create_keystore(tool, password)
    size = KEYSTORE.stat().st_size / 1024
    print('       ' + str(KEYSTORE) + '  (' + format(size, '.1f') + ' KB)')

    print('  2/4  writing android/key.properties')
    write_properties(password)

    print('  3/4  uploading encrypted secrets to GitHub')
    upload()

    print('  4/4  reading the certificate fingerprint')
    sha = read_fingerprint(tool, password)

    del password

    print(NL + '-' * 68)
    if sha:
        print(NL + '  Release SHA-1' + NL)
        print('    ' + sha + NL)
        print('  Paste that into the chat. It is not a secret -- it is a')
        print('  public certificate hash, and Google needs it registered')
        print('  against the Android OAuth client before sign-in works.')
    else:
        print(NL + '  The keystore and secrets are done, but the fingerprint')
        print('  could not be read. Get it with:')
        print('    python tools/signing_fingerprints.py')
    if generated:
        print(NL + '  The password is the storePassword line in')
        print('  shelflife_app/android/key.properties. Copy it into a password')
        print('  manager: that file is gitignored, so a fresh clone will not')
        print('  have it, and without it the keystore cannot be reused.')
    print(NL + '  Back up ' + str(KEYSTORE) + ' somewhere safe.')
    print('  It cannot be regenerated, and without it the app can never be')
    print('  updated -- only uninstalled and replaced.' + NL)
    return 0


if __name__ == '__main__':
    sys.exit(main())
