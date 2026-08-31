# Finishing setup — three tasks

Everything in the app is built. These three need your accounts and your
password, which is why they are not automated.

Do them in this order. Task 1 produces the fingerprint task 2 needs.

| | Task | Time | Fixes |
|---|---|---|---|
| 1 | Create a signing key and push it to CI | ~4 min | Updatable builds, and a stable certificate for Google |
| 2 | Register that certificate with Google | ~2 min | Google sign-in |
| 3 | Add the OTP token to the Supabase email | ~2 min | The sign-up code actually arriving |

---

## Task 1 — Create a signing key

### Why

Android will not let one app be updated by a build signed with a different
key. Right now CI signs with a throwaway debug key that GitHub's runner
generates itself, so every build is effectively a different app — and Google
binds an OAuth client to one certificate, which is why sign-in fails.

**Keep the file you create forever.** Lose it and you can never update the
installed app; users would have to uninstall and reinstall, losing local data.

### 1.1 Create the keystore

Open a terminal in the project and run this. `keytool` is not on your PATH, so
use the full path:

```bash
"/c/Program Files/Microsoft/jdk-17.0.20.101-hotspot/bin/keytool" -genkey -v \
  -keystore "$HOME/shelflife-release.jks" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias shelflife
```

It will prompt you:

| Prompt | What to enter |
|---|---|
| `Enter keystore password` | **Choose a password. Write it down somewhere safe.** Minimum 6 characters. Nothing is echoed as you type — that is normal |
| `Re-enter new password` | The same one |
| `What is your first and last name?` | Your name, or press Enter |
| The next five questions (unit, organisation, city, state, country) | Press Enter to skip each — none of them matter for a private app |
| `Is CN=..., correct?` | Type `yes` |
| `Enter key password for <shelflife>` | **Press Enter** to reuse the keystore password. Simpler, and the tooling assumes it |

`-validity 10000` is about 27 years. Google Play requires a key valid past
2033; this comfortably clears it.

### 1.2 Point the build at it

Create the file `shelflife_app/android/key.properties` with this content,
substituting your password and your Windows username:

```properties
storePassword=YOUR_PASSWORD_HERE
keyPassword=YOUR_PASSWORD_HERE
keyAlias=shelflife
storeFile=C:/Users/rakes/shelflife-release.jks
```

Two things that catch people out:

- **Forward slashes** in `storeFile`, even on Windows. Backslashes are escape
  characters in a properties file.
- Both passwords are the same if you pressed Enter at the key-password prompt.

This file is gitignored and never committed. Neither is the `.jks`.

### 1.3 Push it to CI

```bash
python tools/upload_signing_secrets.py
```

This reads `key.properties`, base64-encodes the keystore, and uploads four
encrypted secrets to GitHub. **The password is read from the file and never
printed**, so it stays out of your terminal history and out of this
conversation.

You should see:

```
  ANDROID_KEYSTORE_BASE64      created
  ANDROID_KEYSTORE_PASSWORD    created
  ANDROID_KEY_PASSWORD         created
  ANDROID_KEY_ALIAS            created
```

Confirm they landed:
<https://github.com/RKP-boop/shelf-life/settings/secrets/actions>

### 1.4 Get the fingerprint

```bash
python tools/signing_fingerprints.py
```

Copy the **release** SHA-1 it prints — a colon-separated hex string. Task 2
needs it.

---

## Task 2 — Register the certificate with Google

<https://console.cloud.google.com/apis/credentials?project=shelflife-507111>

1. Under **OAuth 2.0 Client IDs**, click your **Android** client (the one that
   is *not* the Web client)
2. Find **SHA-1 certificate fingerprint**
3. **Add fingerprint** — paste the release SHA-1 from step 1.4
4. Leave the existing debug fingerprint in place. A client can hold several,
   and keeping it means local debug builds keep working
5. Check **Package name** reads exactly `com.shelflife.app`
6. **Save**

Changes can take a few minutes to propagate. If sign-in fails immediately
after saving, wait five minutes and try again before assuming something is
wrong.

### While you are there

If the OAuth consent screen is still in **Testing**, only accounts you have
listed can sign in — which looks exactly like a broken app to anyone else.

<https://console.cloud.google.com/auth/audience?project=shelflife-507111>

Either add the accounts you plan to test with under **Test users**, or publish
the app. Publishing an app that only requests basic profile scopes does not
require Google's verification review.

---

## Task 3 — Make the sign-up code arrive

<https://supabase.com/dashboard/project/iodzysmxzjfqbrvktzgc/auth/templates>

Select **Confirm signup** and replace the template body with this:

```html
<h2>Confirm your ShelfLife account</h2>

<p>Your code is:</p>

<p style="font-size:28px;font-weight:700;letter-spacing:6px">{{ .Token }}</p>

<p>Enter it in the app. It expires in an hour.</p>

<p style="color:#5C6B64;font-size:13px">
  If you did not sign up for ShelfLife, you can ignore this email.
</p>
```

Then **Save**. Supabase silently keeps the old template if you navigate away
without saving, so confirm the change stuck by reopening the page.

`{{ .Token }}` is the six-digit code. The default template only contains a
confirmation *link*, which is why no code was arriving — the app asks for
digits that were never sent.

### Why a code rather than the link

Tapping the link opens a browser. The account is confirmed there, but the app
never finds out and waits on the code screen indefinitely. Making a link
return to the app needs an Android App Link: a domain you control, a verified
`assetlinks.json` hosted on it, and manifest intent filters. A code closes the
loop without leaving the app.

---

## Then build

<https://github.com/RKP-boop/shelf-life/actions/workflows/build-apk.yml>

**Run workflow** → **Run workflow**.

Roughly 8 minutes. When it finishes, check the **Report the signing
fingerprint** step in the log: it prints the certificate that actually signed
the APK. It should match what you registered in task 2, and there should be no
"Debug-signed" warning.

Download **shelflife-apk** from the run's **Artifacts** section, unzip, and
install `shelflife.apk`.

---

## Verifying it worked

| Check | Where |
|---|---|
| Google sign-in | Welcome screen → **Continue with Google** → pick an account → lands in the app |
| Email sign-up | **Create an account** → a six-digit code arrives → entering it signs you in |
| Receipt scanner | Home → **Photograph a receipt** → a live camera preview, not a dark rectangle |
| Gallery import | On the camera screen, the photo icon bottom-left opens your photo picker |
| Barcode lookup | Scan any packaged product — it should name it rather than asking you to |

If Google sign-in still fails after all three tasks, the fingerprint is the
thing to re-check first. Compare the CI log's **Report the signing
fingerprint** output against what Google Cloud lists, character by character.
That mismatch is the cause in almost every case.
