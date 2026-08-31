# Email verification — one change you need to make in Supabase

The app now asks for a **six-digit code** after sign-up. Supabase's default
confirmation email does not contain one, so it has to be added to the template.
Until you do, the code screen appears and no code arrives.

## Why a code and not the link

Supabase's default confirmation email carries a link. Tapping it opens a
browser, confirms the account there, and **the app never finds out** — it sits
on the confirmation screen indefinitely. Making a link return to the app needs
an Android App Link: a domain you control, a verified `assetlinks.json` hosted
on it, and manifest intent filters. That is a lot of moving parts to bring
someone back to an app they never meant to leave.

A code typed into the app closes the loop without leaving it, and it is the
pattern most people in India already expect.

## The change

Supabase dashboard → **Authentication** → **Emails** → **Confirm signup**.

Add `{{ .Token }}` to the template. Replacing the link entirely is cleaner —
two ways to confirm one account is just a way to get one of them wrong:

```html
<h2>Confirm your ShelfLife account</h2>

<p>Your code is:</p>

<p style="font-size:28px;font-weight:700;letter-spacing:6px">{{ .Token }}</p>

<p>Enter it in the app. It expires in an hour.</p>

<p style="color:#5C6B64;font-size:13px">
  If you did not sign up for ShelfLife, you can ignore this email.
</p>
```

Save. That is the whole change.

## Check it worked

Sign up with an address you can read, and confirm the email contains six
digits rather than a link. If it still shows a link, the template did not save
— Supabase silently keeps the old one if the editor is left without saving.

## Related settings worth knowing

| Setting | Where | Note |
|---|---|---|
| **Confirm email** | Authentication → Providers → Email | Must stay **on**. Turned off, Supabase confirms accounts silently and no code is ever sent — the code screen would then never be satisfiable. Verified as on. |
| Rate limits | Authentication → Rate Limits | Supabase caps confirmation mail per hour. The app enforces a 60-second cooldown on "send it again" so a user cannot burn through the allowance in a few taps. |
| OTP expiry | Authentication → Providers → Email | One hour by default. The app says so on screen. |

## How the app behaves

- **Submits on the sixth digit.** No button press needed, though the button is
  there for anyone who prefers it.
- **Only digits are accepted**, since a letter can never match.
- **Autofill works.** The field is marked as a one-time code, so Android's
  suggestion strip offers it straight from the email on most devices.
- **Guest data is adopted at verification, not at sign-up.** An unconfirmed
  account might never be confirmed; moving someone's kitchen onto it early
  would strand their data.
- **A wrong code is phrased as a correction, not a failure**, and the boxes
  outline in amber rather than red — nothing has broken, a digit is wrong.
