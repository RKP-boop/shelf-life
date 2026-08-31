# Finishing setup — two tasks

Everything else is done. What remains needs your password and your Google
account, which is why it is not automated.

| | Task | Time | Fixes |
|---|---|---|---|
| 1 | Create a signing key | ~2 min, one command | Updatable builds, and a stable certificate for Google |
| 2 | Register that certificate with Google | ~2 min, in the browser | Google sign-in |

Task 1 produces the fingerprint task 2 needs, so do them in order.

## What changed since the last version of this file

The third task — adding `{{ .Token }}` to the Supabase email template — is
**gone, because it is impossible on this project.** Supabase gates template
editing behind custom SMTP, so the Confirm-signup template cannot be changed,
and the default one contains a link with no code. The project-wide send limit
is also 2 emails per hour, and that field is locked as well.

Email sign-up has therefore been removed from the app entirely. Google
sign-in sends no email, so it is unaffected. Guest mode still works with no
account at all. See decision D25 in the design spec.

---

## Task 1 — Create a signing key

### Why

Android refuses to update an app when the new build is signed with a different
key, and Google binds an OAuth client to exactly one certificate. Right now CI
signs with a throwaway debug key that the GitHub runner generates itself, so
every build is effectively a different app and Google sign-in cannot work no
matter what you register.

### Run this

```bash
python tools/setup_signing.py
```

Run it yourself rather than asking me to. It prompts for a password, and a
password should not pass through an agent or a chat transcript. Everything
either side of that one prompt is automated: it creates the keystore, writes
`android/key.properties`, uploads four encrypted secrets to GitHub, and prints
the fingerprint.

It will ask:

```
  Password (6+ characters):
  Again:
```

Nothing echoes as you type — that is normal, not a frozen terminal. **Write
the password down somewhere safe.** You need it to build again.

Expected output:

```
  1/4  creating the keystore
       C:\Users\rakes\shelflife-release.jks  (2.6 KB)
  2/4  writing android/key.properties
  3/4  uploading encrypted secrets to GitHub
       ANDROID_KEYSTORE_BASE64      created
       ANDROID_KEYSTORE_PASSWORD    created
       ANDROID_KEY_PASSWORD         created
       ANDROID_KEY_ALIAS            created
  4/4  reading the certificate fingerprint

  Release SHA-1

    AA:BB:CC:...
```

Copy that SHA-1 — task 2 needs it. It is not a secret; it is a public
certificate hash.

### Two things worth knowing

**Back up `~/shelflife-release.jks`.** It cannot be regenerated. Without it
the installed app can never be updated, only uninstalled and replaced, which
loses whatever the user had stored locally. The script refuses to overwrite an
existing keystore for exactly this reason.

**The keystore and `key.properties` are both gitignored** and never committed.
The password reaches GitHub only as a sealed-box encrypted secret.

Verify the secrets landed:
<https://github.com/RKP-boop/shelf-life/settings/secrets/actions>

---

## Task 2 — Register the certificate with Google

<https://console.cloud.google.com/apis/credentials?project=shelflife-507111>

1. Under **OAuth 2.0 Client IDs**, click the **Android** client — the one that
   is *not* the Web client
2. Find **SHA-1 certificate fingerprint** → **Add fingerprint**
3. Paste the release SHA-1 from task 1
4. Leave the existing debug fingerprint in place. One client holds several, and
   keeping it means local debug builds keep working
5. Check **Package name** reads exactly `com.shelflife.app`
6. **Save**

Give it five minutes to propagate before concluding it did not work.

### Also check the consent screen

<https://console.cloud.google.com/auth/audience?project=shelflife-507111>

If it is still in **Testing**, only accounts listed under **Test users** can
sign in, and to everyone else the app looks broken rather than restricted.
Either add the accounts you plan to test with, or publish — publishing an app
that requests only basic profile scopes does not need Google's verification
review.

---

## Then build

<https://github.com/RKP-boop/shelf-life/actions/workflows/build-apk.yml>

**Run workflow** → **Run workflow**. Roughly 8 minutes.

When it finishes, open the **Report the signing fingerprint** step in the log.
It prints the certificate that actually signed the APK. It must match what you
registered in task 2, and there must be no "Debug-signed" warning.

Download **shelflife-apk** from the run's **Artifacts**, unzip, install
`shelflife.apk`.

---

## Verifying it worked

| Check | Where |
|---|---|
| Google sign-in | Welcome → **Continue with Google** → pick an account → lands in the app |
| Guest mode | Welcome → **Continue without an account** → the explainer → **Continue this way** |
| Receipt scanner | Home → **Photograph a receipt** → a live camera preview, not a dark rectangle |
| Gallery import | On the camera screen, the photo icon bottom-left opens your photo picker |
| Barcode lookup | Scan any packaged product — it should name it rather than asking you to |

If Google sign-in still fails, the fingerprint is the first thing to re-check.
Compare the CI log's **Report the signing fingerprint** output against what
Google Cloud lists, character by character. That mismatch is the cause in
almost every case.
