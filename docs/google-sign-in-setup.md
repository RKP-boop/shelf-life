# Google sign-in — the setup you have to do

The code is done. Google sign-in needs three things registered outside the
repo, and none of them can be created from here: two OAuth clients in Google
Cloud, and the provider switched on in Supabase.

**Until the build is given a client id, the button does not appear at all.**
That is deliberate — an option that fails on tap is worse than no option — so
the app works exactly as it does today until you finish these steps.

---

## 0. Use a project you actually own

Before anything else, check which Google Cloud project you are in.

If the Credentials page shows an API key labelled **"auto created by Firebase"**,
or you see this:

> You don't have permission to view OAuth clients. Required permissions:
> `clientauthconfig.clients.list` ... and `iam.serviceAccounts.list`

then the project was auto-provisioned by Firebase or another Google tool and
your account does not hold Owner on it. You can open the page and create
nothing. The matching error on Service Accounts is the confirmation: it is
several missing permissions, not one setting.

**Create your own project instead** — you become Owner automatically, and none
of this appears:

1. <https://console.cloud.google.com/projectcreate>
2. Name it, leave organisation as *No organisation*, **Create**
3. **Switch to it in the project picker at the top.** Skipping this is the most
   common way to hit the exact same error again a minute later.

ShelfLife does not use Firebase or anything else in Google Cloud. The project
exists only to issue OAuth clients.

Worth ruling out first: check the avatar top-right is the Google account you
mean to be using. With a personal and a work account both signed in, the
console can land you on an org project where your rights really are restricted.

---

## 1. Get your signing SHA-1

Google ties the Android OAuth client to your app's package name *and* the
certificate that signs it. Get the fingerprint first, because step 3 needs it.

**Right now the app is debug-signed**, so use the debug keystore:

```bash
keytool -list -v \
  -keystore "$HOME/.android/debug.keystore" \
  -alias androiddebugkey -storepass android -keypass android
```

Once you create a release keystore (see `INSTALL.md`), get that one too:

```bash
keytool -list -v -keystore "$HOME/shelflife-release.jks" -alias shelflife
```

Copy the `SHA1:` line from the output — a colon-separated hex string.

> **The trap:** a build signed with a certificate Google does not know about
> fails sign-in with a generic message. If you register only the debug SHA-1
> and then ship a release build, Google sign-in breaks for everyone who
> installs it, while still working on your machine. **Register both.** You can
> add fingerprints to the same Android client at any time.

## 2. Create the OAuth consent screen

<https://console.cloud.google.com/apis/credentials/consent>

Pick **External**, fill in the app name, your support email and a developer
email. While the app is in *Testing* only accounts you list as test users can
sign in — worth knowing when it works for you and not for a friend.

## 3. Create two OAuth clients

<https://console.cloud.google.com/apis/credentials> → **Create credentials** →
**OAuth client ID**. You need both of these:

| Type | What to enter | What it is for |
|---|---|---|
| **Android** | Package name `com.shelflife.app`, plus the SHA-1 from step 1 | Lets the phone prove it is really your app |
| **Web** | No redirect URIs needed for the native flow | The audience Supabase validates the token against |

Then add the Supabase callback to the **Web** client's *Authorised redirect
URIs*, which Supabase needs even though the phone never visits it:

```
https://iodzysmxzjfqbrvktzgc.supabase.co/auth/v1/callback
```

Keep the **Web** client's ID and secret. The Android client's ID is never used
in code or config — its only job is to exist with the right fingerprint.

> This is the part that catches people out: **Android passes the *web* client
> id**, not the Android one. The app sends it as `serverClientId`, because that
> is the audience the token is minted for and what Supabase checks.

## 4. Turn the provider on in Supabase

Dashboard → **Authentication** → **Providers** → **Google**:

- Enable it
- **Client ID** — the *Web* client ID from step 3
- **Client Secret** — the *Web* client secret
- Save

## 5. Build with the client id

```bash
flutter build apk --release --split-per-abi \
  --dart-define=SUPABASE_URL=https://iodzysmxzjfqbrvktzgc.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable key> \
  --dart-define=GOOGLE_WEB_CLIENT_ID=<web client id>.apps.googleusercontent.com
```

The button appears on the welcome screen and on sign in. Omit the flag and it
stays hidden.

---

## How it behaves

- **Signs in natively**, through Android's account picker, not a browser. No
  deep link or custom URL scheme to configure.
- **Guest data comes with you.** Google sign-in goes through the same
  `_adopt` path as email, so anything added before signing in keeps its id and
  changes owner. Nothing is lost and nothing is duplicated.
- **Backing out of the picker is silent.** Cancelling is not a failure and
  produces no message.
- **Signing out signs out of Google too.** Otherwise the next attempt silently
  reuses the same account with no picker, which looks like sign-out did not
  work.

## If it does not work

| What you see | Almost always |
|---|---|
| No button at all | The build had no `GOOGLE_WEB_CLIENT_ID` |
| "Google did not complete that sign-in" | SHA-1 not registered, or wrong package name |
| Works for you, not for others | App still in *Testing*, or only the debug SHA-1 registered |
| "not available on this phone" | No Play Services — an emulator image without Google APIs |
| Cannot create an OAuth client at all | Wrong Google Cloud project, or one you do not own — see step 0 |

## About the button's appearance

It carries no Google logo. Their branding guidelines require the official
asset, and a hand-drawn approximation was both inaccurate and — measured at the
20dp the button actually uses — an unreadable coloured blob. The button is
clean typography instead.

If you want the real mark for a public release, download it from Google's
[branding guidelines](https://developers.google.com/identity/branding-guidelines),
drop it at `shelflife_app/assets/brand/google-g.png`, declare `assets/brand/`
in `pubspec.yaml`, and add an `Image.asset` to `GoogleButton` in
`lib/features/auth/screens/auth_screens.dart`. The layout leaves room for it.
