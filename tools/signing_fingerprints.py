#!/usr/bin/env python3
"""Prints the SHA-1 fingerprints Google needs for the Android OAuth client.

Google ties the Android OAuth client to your package name AND the certificate
that signs the app. Register the wrong one and sign-in fails with a generic
message that names nothing.

The trap this exists to prevent: registering only the debug fingerprint. Google
sign-in then works perfectly on your machine and fails for every single person
you send the APK to, because the release build is signed with a different key.
Register both, from the start.

Usage:  python tools/signing_fingerprints.py
"""

from __future__ import annotations

import os
import pathlib
import re
import shutil
import subprocess
import sys

PACKAGE = "com.shelflife.app"


def keytool() -> str | None:
    found = shutil.which("keytool")
    if found:
        return found
    # keytool ships with the JDK; fall back to JAVA_HOME when it is not on PATH.
    java_home = os.environ.get("JAVA_HOME")
    if java_home:
        for name in ("keytool.exe", "keytool"):
            candidate = pathlib.Path(java_home) / "bin" / name
            if candidate.exists():
                return str(candidate)
    return None


def fingerprint(tool: str, keystore: pathlib.Path, alias: str,
                store_pass: str | None) -> str | None:
    cmd = [tool, "-list", "-v", "-keystore", str(keystore), "-alias", alias]
    if store_pass is not None:
        cmd += ["-storepass", store_pass]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True,
                             timeout=60).stdout
    except Exception as e:  # noqa: BLE001
        return f"could not read: {e}"
    match = re.search(r"SHA1:\s*([0-9A-F:]+)", out, re.IGNORECASE)
    return match.group(1) if match else None


def release_keystore() -> tuple[pathlib.Path, str] | None:
    """Reads android/key.properties, which is gitignored and may not exist."""
    props = (pathlib.Path(__file__).resolve().parents[1]
             / "shelflife_app" / "android" / "key.properties")
    if not props.exists():
        return None
    values: dict[str, str] = {}
    for line in props.read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.strip().startswith("#"):
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip()
    store = values.get("storeFile")
    alias = values.get("keyAlias")
    if not store or not alias:
        return None
    return pathlib.Path(store), alias


def main() -> int:
    tool = keytool()
    if tool is None:
        print("keytool not found. It ships with the JDK; set JAVA_HOME or put "
              "it on PATH.", file=sys.stderr)
        return 2

    print(f"Package name:  {PACKAGE}\n")

    debug = pathlib.Path.home() / ".android" / "debug.keystore"
    if debug.exists():
        sha = fingerprint(tool, debug, "androiddebugkey", "android")
        print(f"  debug    SHA-1  {sha or 'not found'}")
        print("           (the key the current APK is signed with)")
    else:
        print("  debug    no debug keystore yet; it appears after the first "
              "Android build")

    release = release_keystore()
    if release is None:
        print("\n  release  none yet. Create one (see INSTALL.md) and add")
        print("           android/key.properties, then re-run this.")
        print("\n  Register the debug fingerprint now so you can test, but add")
        print("  the release one before you send the APK to anybody - sign-in")
        print("  will fail for them otherwise.")
    else:
        path, alias = release
        if not path.exists():
            print(f"\n  release  key.properties points at {path}, which is "
                  "missing")
        else:
            sha = fingerprint(tool, path, alias, None)
            print(f"\n  release  SHA-1  {sha or 'needs the store password'}")
            if sha is None:
                print("           re-run and enter the password when prompted:")
                print(f'           keytool -list -v -keystore "{path}" '
                      f"-alias {alias}")

    print("\nAdd these to the Android OAuth client at")
    print("https://console.cloud.google.com/apis/credentials")
    print("Both can live on the same client. See docs/google-sign-in-setup.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
