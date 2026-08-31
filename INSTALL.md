# Installing ShelfLife

## For someone you send the APK to

1. Download `shelflife.apk` to the Android phone.
2. Tap it. Android will say the file came from an unknown source — that is
   expected for any app not installed from the Play Store. Tap **Settings**,
   allow installs from whichever app you downloaded with (Chrome, Drive,
   WhatsApp), then go back and tap **Install**.
3. Open ShelfLife.

**Android only.** iPhones cannot install an `.apk`; iOS requires the App Store
or TestFlight.

**Minimum Android version:** 7.0 (Nougat), which is Flutter's current floor.
Anything from roughly 2016 onwards.

### What it asks for, and when

Nothing is asked for on first launch. Permissions are requested at the moment
they are actually needed, and every one of them can be refused without breaking
the app:

| Permission | Asked when | If you say no |
|---|---|---|
| Camera | You open the receipt or barcode scanner | Add things by hand instead |
| Notifications | Just after you add your first item | No reminders; everything else works |

### An account is optional

"Continue without an account" gives you the whole app. If you do want one,
**Google is the only way in** -- there is no email or password to remember. Your kitchen is stored
on the phone. Nothing is sent anywhere, and nothing syncs — if you clear the
app's data or switch phones, it is gone. You can sign in with Google later and
everything you already added comes with you.

---

## For whoever is building the APK

### One-time: create a signing key

Android will not install an unsigned app, and an app signed with the debug key
cannot be updated later by one signed with a real key. Make the key once and
keep it — losing it means every future version installs as a separate app.

One command does all of it -- keystore, `key.properties`, the encrypted upload
to GitHub Actions, and the fingerprint Google needs:

```bash
python tools/setup_signing.py
```

Run it yourself so the password stays yours; it prompts for it and never prints
it. If you would rather do it by hand, the file it writes looks like this:

```properties
storePassword=<the password you just chose>
keyPassword=<the same one, unless you set a separate key password>
keyAlias=shelflife
storeFile=C:/Users/<you>/shelflife-release.jks
```

Use forward slashes in `storeFile` even on Windows.

If `key.properties` is missing, the build still succeeds — it falls back to the
debug key. That is fine for trying it on your own phone and **not** fine for
anything you send to other people.

### Build

```bash
cd shelflife_app

flutter build apk --release --split-per-abi \
  --dart-define=SUPABASE_URL=https://iodzysmxzjfqbrvktzgc.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<the publishable key> \
  --dart-define=GOOGLE_WEB_CLIENT_ID=315114889434-dv8sgsq9ihm5835bqo17cckb40b4g1i2.apps.googleusercontent.com
```

Output, in `build/app/outputs/flutter-apk/`:

| File | Size | Who it is for |
|---|---|---|
| `app-arm64-v8a-release.apk` | 47 MB | **Send this one.** Every phone made since roughly 2016 |
| `app-armeabi-v7a-release.apk` | 39 MB | Older 32-bit phones |
| `app-x86_64-release.apk` | 50 MB | Emulators, a handful of tablets |

Dropping `--split-per-abi` produces one 110 MB universal APK instead. It works
on anything, at the cost of making everyone download all three architectures.
Sending the arm64 build and keeping the 32-bit one in reserve is the better
trade.

Copies are staged in `dist/` as `shelflife.apk` (arm64) and
`shelflife-older-phones.apk`.

### Why it is 47 MB

Roughly half is Google's on-device text-recognition model, which is bundled so
receipt scanning works with no network and nothing leaves the phone. The
Flutter engine is most of the rest.

### Check it before you send it — not optional

```bash
python tools/audit_apk.py dist/shelflife.apk
```

Exits 1 if anything is wrong. It checks four things:

- **The launcher activity actually exists in the APK.** The first build shipped
  with `applicationId` renamed but `MainActivity.kt` left in the old package.
  It compiled, analyzed, passed 211 tests and packaged without a murmur — then
  installed and died with `ClassNotFoundException` before drawing a frame. No
  test that stops at the Dart layer can see that. This one can.
- No service-role key, secret key or signing password is inside the file.
- The build actually received its `--dart-define` values.
- The bundled catalogue, fonts and produce renders are present.

Run it on the exact file you are about to send, every time.

### Google sign-in needs a real signing key when built in CI

Not optional, and the reason is unobvious. With no keystore, Gradle signs with
a debug key — and a GitHub runner generates its *own*, different from any
developer machine. Google binds an Android OAuth client to one signing
certificate, so a debug-signed CI build fails Google sign-in no matter which
SHA-1 you registered. The first CI APK was signed `65:43:FC:15…` while
`18:98:3E:8B…` was registered; that is the whole bug.

So: create the keystore, push it to Actions, register *its* SHA-1.

```bash
# All four steps, one command. It prompts for the password (hidden), creates
# the keystore, writes key.properties, uploads the encrypted secrets, and
# prints the SHA-1 to register with the Android OAuth client.
python tools/setup_signing.py
```

Run it yourself rather than delegating it: the password should not pass through
an agent or a chat transcript. The script refuses to overwrite an existing
keystore, because the old certificate is the only thing that can sign an update
to an already-installed app.

### Google sign-in

**The only account path.** Email sign-up was removed: the Supabase project
cannot send a confirmation code -- template editing is gated behind custom
SMTP, the default template carries a link and no token, and the send limit is
two emails an hour project-wide. See decision D25.

The button appears only when the build is given
`--dart-define=GOOGLE_WEB_CLIENT_ID=...`, which needs two OAuth clients in
Google Cloud and the provider enabled in Supabase first. A build without it
installs and runs and looks correct -- the welcome screen hides an option it
cannot honour -- so `tools/audit_apk.py` fails the artefact rather than letting
that ship. Full steps, including the SHA-1 trap that breaks release builds:
[`docs/google-sign-in-setup.md`](docs/google-sign-in-setup.md).

### If the build fails with "An Application Control policy has blocked this file"

```
Target android_aot_release_android-arm64 failed: ProcessException:
An Application Control policy has blocked this file
  Command: ...\engine\android-arm64-release\windows-x64\gen_snapshot.EXE
```

This is **Windows Smart App Control**, not a problem with the project. It
blocks executables it does not recognise, and `gen_snapshot.exe` — Flutter's
ahead-of-time compiler, which turns Dart into native ARM code — is one of them.

It looks intermittent because Smart App Control judges each binary separately
and its verdicts change as Microsoft's reputation data updates. A build can
succeed, then the same command fails minutes later. Two earlier failures in
this project were misread as CPU contention; they were almost certainly this.

Check whether it is enabled:

```powershell
(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy').VerifiedAndReputablePolicyState
# 0 = off   1 = enforced   2 = evaluation
```

**Your options, and the trade-off is real:**

- **Retry the build.** Sometimes it gets through. Fine once; not a way to work.
- **Turn Smart App Control off** — Windows Security → App & browser control →
  Smart App Control → Off. This is the only reliable fix on this machine, and
  it is **irreversible**: Windows cannot turn it back on without reinstalling
  the operating system. That is Microsoft's design, not a bug. It is a normal
  choice for a development machine and a significant one for a general-purpose
  one. Decide deliberately.
- **Build somewhere else.** CI, another machine, or WSL — none of which are
  subject to it.

Adding a Microsoft Defender exclusion does **not** help. Smart App Control is a
separate mechanism and ignores Defender exclusion lists.

Nothing in this repository changes any of this, and no tooling here will turn
it off for you — a security setting that cannot be undone is not something to
flip on someone's behalf.

### About the keys in the build

`SUPABASE_ANON_KEY` is a publishable key and is meant to be in client
applications. What protects the data is row-level security: every table is
scoped to `auth.uid()`, verified with two real users in
`tools/verify_backend.py`.

The **service-role key must never** appear in the app, the repo, or a build
command. It bypasses row-level security entirely.

### Running it without a backend

Omit both `--dart-define` flags and the app runs entirely on-device: all 52
screens, the seeded catalogue, recipes, reminders and the barcode cache work.
Only accounts and sync are unavailable, and the app says so rather than
failing.
