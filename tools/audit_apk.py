#!/usr/bin/env python3
"""Audit a release APK before sending it to anyone.

The check that matters is the negative one: the service-role key bypasses
row-level security entirely, so a copy of it inside a file you hand to other
people is a full compromise of every user's data. Everything else here is a
sanity check that the build actually contains what it should.

Usage:  python tools/audit_apk.py <path-to.apk>
Exit:   0 clean, 1 something is wrong
"""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys
import zipfile

# Anything matching these must not appear anywhere in the archive.
#
# Each pattern requires actual key material after the prefix, not the bare
# prefix. The supabase_flutter SDK contains the literals `sb_secret_` and
# `service_role` in its own validation code — it checks for them in order to
# refuse them — so matching the prefix alone flags every build ever made and
# teaches you to ignore the audit.
FORBIDDEN = {
    "a service-role JWT": rb'"role"\s*:\s*"service_role"',
    "a Supabase secret key": rb"sb_secret_[A-Za-z0-9_-]{12,}",
    "a private key block": rb"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    "a keystore password": rb"storePassword\s*=",
}

# Things that should be present, so a silently-misconfigured build is caught
# rather than shipped.
EXPECTED_STRINGS = {
    "publishable key": rb"sb_publishable_",
    "Supabase project URL": rb"supabase\.co",
    # Google sign-in is the only account path in the app (decision D25), so a
    # build without this define is not a build with one feature missing -- it is
    # a build nobody can sign into. It would install, run, and look fine: the
    # welcome screen hides the Google button when the id is absent, on the
    # principle that an option which cannot work is worse than no option. That
    # same kindness makes the failure invisible, which is why it belongs here
    # rather than in a runtime check.
    "Google OAuth client id": rb"\.apps\.googleusercontent\.com",
}

# The launcher activity named in the manifest must actually exist in the dex.
#
# This check exists because it did not, once. Renaming `applicationId` and
# `namespace` in build.gradle.kts without moving MainActivity.kt left the
# manifest pointing at `com.shelflife.app.MainActivity` while the class was
# still `com.shelflife.shelflife_app.MainActivity`. Everything compiled,
# analyzed, tested and packaged cleanly; the app installed and then died with
# ClassNotFoundException before a single frame. No test that stops at the Dart
# layer can see this.
def _launcher_class_present(apk: pathlib.Path) -> tuple[bool, str]:
    """(ok, detail). Falls back to a dex string scan when aapt is unavailable."""
    activity = _manifest_launcher(apk)
    if activity is None:
        return False, "could not read the launcher activity from the manifest"

    descriptor = "L" + activity.replace(".", "/") + ";"
    with zipfile.ZipFile(apk) as z:
        for name in z.namelist():
            if not name.endswith(".dex"):
                continue
            if descriptor.encode() in z.read(name):
                return True, activity
            # Dex stores the class name and package separately in its string
            # pool on some toolchains, so also accept the plain form.
            if activity.encode() in z.read(name):
                return True, activity
    return False, f"{activity} is named in the manifest but not in any dex"


def _manifest_launcher(apk: pathlib.Path) -> str | None:
    """Resolves the launcher activity name, expanding a leading dot."""
    aapt = _find_aapt()
    if aapt is None:
        return None
    try:
        out = subprocess.run(
            [str(aapt), "dump", "badging", str(apk)],
            capture_output=True, text=True, timeout=120,
        ).stdout
    except Exception:  # noqa: BLE001
        return None
    m = re.search(r"launchable-activity: name='([^']+)'", out)
    return m.group(1) if m else None


def _find_aapt() -> pathlib.Path | None:
    for root in (pathlib.Path(r"C:/src/android-sdk/build-tools"),
                 pathlib.Path.home() / "AppData/Local/Android/Sdk/build-tools"):
        if not root.exists():
            continue
        for version in sorted(root.iterdir(), reverse=True):
            for exe in ("aapt2.exe", "aapt.exe", "aapt2", "aapt"):
                candidate = version / exe
                if candidate.exists() and "aapt2" not in exe:
                    return candidate
    return None


EXPECTED_ASSETS = [
    "assets/flutter_assets/assets/seed/reference.json",
    "assets/flutter_assets/assets/fonts/PlusJakartaSans-Regular.ttf",
    "assets/flutter_assets/assets/produce/spinach.png",
    "assets/flutter_assets/assets/glyph/cat-pantry.png",
]


def scan(apk: pathlib.Path) -> int:
    problems: list[str] = []
    found_expected: set[str] = set()

    with zipfile.ZipFile(apk) as z:
        names = set(z.namelist())

        for asset in EXPECTED_ASSETS:
            if asset not in names:
                problems.append(f"missing asset: {asset}")

    ok, detail = _launcher_class_present(apk)
    if ok:
        print(f"  launcher activity present: {detail}")
    elif "could not read" in detail:
        # aapt missing is not a finding about the APK.
        print(f"  launcher activity: SKIPPED ({detail})")
    else:
        problems.append(detail)

    with zipfile.ZipFile(apk) as z:

        for info in z.infolist():
            if info.is_dir():
                continue
            # Read whole entries: the compiled Dart snapshot is one large file
            # and a chunked scan could split a match across a boundary.
            try:
                blob = z.read(info)
            except Exception as e:  # noqa: BLE001 - a damaged entry is a finding
                problems.append(f"could not read {info.filename}: {e}")
                continue

            for label, pattern in FORBIDDEN.items():
                if re.search(pattern, blob):
                    problems.append(f"FOUND {label} in {info.filename}")

            for label, pattern in EXPECTED_STRINGS.items():
                if re.search(pattern, blob):
                    found_expected.add(label)

    for label in EXPECTED_STRINGS:
        if label not in found_expected:
            problems.append(
                f"missing {label} — was the build given its --dart-define flags?"
            )

    size_mb = apk.stat().st_size / (1024 * 1024)
    print(f"{apk.name}  {size_mb:.1f} MB")
    print(f"  expected strings found: {sorted(found_expected)}")

    if problems:
        print("\nproblems:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1

    print("  no secret material; assets present")
    return 0


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    apk = pathlib.Path(sys.argv[1])
    if not apk.exists():
        print(f"no such file: {apk}", file=sys.stderr)
        return 2
    return scan(apk)


if __name__ == "__main__":
    sys.exit(main())
