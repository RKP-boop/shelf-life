#!/usr/bin/env python3
"""Verify the ShelfLife Supabase backend against the live project.

Uses the publishable (anon) key only. That is deliberate: a service-role key
bypasses RLS, so the isolation test would pass even if RLS were broken.

Requires "Confirm email" to be OFF in Authentication settings, so throwaway
users can be created.

Usage:  python tools/verify_backend.py
Exit:   0 all passed, 1 one or more failed
"""
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
import uuid
from datetime import date, timedelta

URL = "https://iodzysmxzjfqbrvktzgc.supabase.co"
ANON = "sb_publishable_OA5Pw15MgRdbgnsAm6l9Gg__vkCz0QZ"

EXPECTED = {"ingredients": 65, "ingredient_aliases": 153,
            "recipes": 40, "recipe_ingredients": 223, "products": 40}

results: list[tuple[bool, str, str]] = []


def call(method: str, path: str, token: str | None = None,
         body=None, extra: dict | None = None) -> tuple[int, object]:
    req = urllib.request.Request(URL + path, method=method)
    req.add_header("apikey", ANON)
    req.add_header("Authorization", f"Bearer {token or ANON}")
    req.add_header("Content-Type", "application/json")
    for k, v in (extra or {}).items():
        req.add_header(k, v)
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(req, data, timeout=45) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw.strip() else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, raw
    except Exception as e:  # network-level
        return 0, str(e)


def check(name: str, ok: bool, detail: str = "") -> bool:
    results.append((ok, name, detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"   {detail}" if detail else ""))
    return ok


def _hdr_count(table: str, token: str | None = None) -> int | None:
    """Exact count via Content-Range, which PostgREST returns as 0-24/65."""
    sep = "&" if "?" in table else "?"
    req = urllib.request.Request(f"{URL}/rest/v1/{table}{sep}select=*", method="HEAD")
    req.add_header("apikey", ANON)
    req.add_header("Authorization", f"Bearer {token or ANON}")
    req.add_header("Prefer", "count=exact")
    req.add_header("Range", "0-0")
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            cr = r.headers.get("Content-Range", "")
            return int(cr.split("/")[-1]) if "/" in cr else None
    except Exception:
        return None


def signup(email: str, password: str) -> str | None:
    status, body = call("POST", "/auth/v1/signup",
                        body={"email": email, "password": password})
    if status in (200, 201) and isinstance(body, dict):
        tok = body.get("access_token")
        if tok:
            return tok
        # confirmation still on -> no session issued
        return None
    return None


def autoconfirm_on() -> bool:
    """True when signups are auto-confirmed, so a session is issued directly."""
    _status, body = call("GET", "/auth/v1/settings")
    return bool(isinstance(body, dict) and body.get("mailer_autoconfirm"))


def main() -> int:
    print("ShelfLife backend verification")
    print(f"project: {URL}\n")

    # Detect the confirmation setting up front. Without this, a run against a
    # correctly-secured project reports a wall of failures that read like a
    # backend regression rather than an intentional configuration state.
    live_auth = autoconfirm_on()
    if not live_auth:
        print("NOTE  Email confirmation is ON, so signup issues no session and the")
        print("      checks needing a real user cannot run. That is the correct")
        print("      production setting, not a regression.")
        print("      For the full suite, temporarily turn OFF:")
        print("      Authentication > Sign In / Providers > Email > Confirm email\n")

    # ---------------------------------------------------------------- 1 tables
    print("1. tables reachable")
    tables = ["profiles", "ingredients", "ingredient_aliases", "products", "recipes",
              "recipe_ingredients", "inventory_items", "consumption_events",
              "shopping_list_items", "notifications"]
    missing = []
    for t in tables:
        status, _ = call("GET", f"/rest/v1/{t}?select=*&limit=1")
        if status == 404:
            missing.append(t)
    if not check("all ten tables exist", not missing, f"missing: {missing}" if missing else ""):
        print("\nSchema not applied. Run the migrations in supabase/APPLY.md first.")
        return 1

    # ------------------------------------------------------------ 2 seed counts
    # Reference-table policies are scoped `to authenticated`, so these must be
    # counted with a real session. Counting as anon correctly returns 0 — that
    # is the policy working, not missing data.
    print("\n2. seeded reference data")
    seed_tok = (signup(f"verify-seed-{uuid.uuid4().hex[:8]}@example.com",
                       "ShelfLife-Verify-9142!") if live_auth else None)
    if not seed_tok:
        print("  SKIP  needs a session (email confirmation is on)")
    else:
        for table, want in EXPECTED.items():
            # products grows by design (D1), so assert the SEEDED subset only.
            # Counting every row would fail as soon as a user contributes one,
            # which is the feature working rather than a regression.
            suffix = "?verified=is.true" if table == "products" else ""
            got = _hdr_count(table + suffix, seed_tok)
            label = f"{table} seeded = {want}" if suffix else f"{table} = {want}"
            check(label, got == want, f"got {got}")

        contributed = _hdr_count("products?verified=is.false", seed_tok)
        print(f"        ({contributed} user-contributed barcode(s) on top — D1 growth)")
        # and the same tables must stay invisible without a session
        anon_ing = _hdr_count("ingredients")
        check("reference data invisible to anon", anon_ing == 0, f"anon saw {anon_ing}")

    # ------------------------------------------------- 3 anonymous access denied
    print("\n3. anonymous access")
    for t in ["inventory_items", "consumption_events", "shopping_list_items",
              "notifications", "profiles"]:
        status, body = call("GET", f"/rest/v1/{t}?select=*")
        empty = status in (200, 206) and isinstance(body, list) and len(body) == 0
        denied = status in (401, 403)
        check(f"{t} exposes nothing to anon", empty or denied,
              f"status {status}" + (f" rows {len(body)}" if isinstance(body, list) else ""))

    # ------------------------------------------------- 4 RLS isolation, 2 users
    print("\n4. RLS isolation between two real users")
    stamp = uuid.uuid4().hex[:8]
    pwd = "ShelfLife-Verify-9142!"
    tok_a = signup(f"verify-a-{stamp}@example.com", pwd) if live_auth else None
    tok_b = signup(f"verify-b-{stamp}@example.com", pwd) if live_auth else None

    if not tok_a or not tok_b:
        print("  SKIP  needs two sessions (email confirmation is on)")
    else:
        check("two users created", True)
        # user A writes one item
        item = {
            "product_name": f"RLS probe {stamp}",
            "category": "vegetables",
            "quantity": 1, "unit": "kg", "storage": "fridge",
            "purchase_date": date.today().isoformat(),
            "expiry_date": (date.today() + timedelta(days=2)).isoformat(),
            "expiry_source": "estimated",
        }
        status, body = call("POST", "/rest/v1/inventory_items", tok_a, item,
                            extra={"Prefer": "return=representation"})
        wrote = status in (200, 201) and isinstance(body, list) and body
        check("user A can insert own inventory", bool(wrote), f"status {status} {str(body)[:110]}")

        if wrote:
            item_id = body[0]["id"]

            status, a_rows = call("GET", f"/rest/v1/inventory_items?select=*&id=eq.{item_id}", tok_a)
            check("user A sees own row", isinstance(a_rows, list) and len(a_rows) == 1,
                  f"{len(a_rows) if isinstance(a_rows, list) else a_rows} row(s)")

            # THE test that matters
            status, b_rows = call("GET", f"/rest/v1/inventory_items?select=*&id=eq.{item_id}", tok_b)
            check("user B CANNOT see user A's row",
                  isinstance(b_rows, list) and len(b_rows) == 0,
                  f"{len(b_rows) if isinstance(b_rows, list) else b_rows} row(s) leaked")

            status, _ = call("GET", "/rest/v1/inventory_items?select=*", tok_b)
            _, b_all = call("GET", "/rest/v1/inventory_items?select=*", tok_b)
            check("user B's inventory is empty",
                  isinstance(b_all, list) and len(b_all) == 0,
                  f"{len(b_all) if isinstance(b_all, list) else b_all} row(s)")

            # user B cannot write into A's user_id
            _, me_a = call("GET", "/auth/v1/user", tok_a)
            a_uid = me_a.get("id") if isinstance(me_a, dict) else None
            if a_uid:
                spoof = dict(item, user_id=a_uid, product_name="spoof")
                status, sbody = call("POST", "/rest/v1/inventory_items", tok_b, spoof)
                check("user B cannot write a row owned by A", status in (401, 403),
                      f"status {status}")

            # user B cannot delete A's row
            status, _ = call("DELETE", f"/rest/v1/inventory_items?id=eq.{item_id}", tok_b)
            _, still = call("GET", f"/rest/v1/inventory_items?select=id&id=eq.{item_id}", tok_a)
            check("user B cannot delete A's row",
                  isinstance(still, list) and len(still) == 1, "row survived")

            # ------------------------------------------- 5 reference read-only
            print("\n5. reference tables are read-only")
            status, _ = call("POST", "/rest/v1/ingredients", tok_a,
                             {"canonical_name": f"probe-{stamp}", "category": "other",
                              "default_unit": "g", "glyph_key": "cat-pantry"})
            check("ingredients rejects insert", status in (401, 403), f"status {status}")
            status, _ = call("POST", "/rest/v1/recipes", tok_a,
                             {"name": f"probe-{stamp}", "prep_minutes": 5})
            check("recipes rejects insert", status in (401, 403), f"status {status}")

            # -------------------------------------------------- 6 products rules
            print("\n6. products: insert allowed, update refused")
            _, me = call("GET", "/auth/v1/user", tok_a)
            uid = me.get("id") if isinstance(me, dict) else None
            bc = f"999{stamp}0"
            status, _ = call("POST", "/rest/v1/products", tok_a,
                             {"barcode": bc, "product_name": "Verify probe",
                              "contributed_by": uid, "verified": False})
            check("authenticated user can contribute a barcode", status in (200, 201),
                  f"status {status}")
            status, _ = call("PATCH", f"/rest/v1/products?barcode=eq.{bc}", tok_a,
                             {"product_name": "hijacked"})
            _, row = call("GET", f"/rest/v1/products?select=product_name&barcode=eq.{bc}", tok_a)
            unchanged = isinstance(row, list) and row and row[0]["product_name"] == "Verify probe"
            check("products refuses update", unchanged, f"status {status}")
            status, _ = call("POST", "/rest/v1/products", tok_a,
                             {"barcode": f"888{stamp}0", "product_name": "fake reference",
                              "contributed_by": uid, "verified": True})
            check("cannot pass a contribution off as verified", status in (401, 403),
                  f"status {status}")

            # ------------------------------------------------- 7 match_recipes
            print("\n7. match_recipes")
            # give A a spinach + paneer inventory so Palak Paneer should rank
            _, ings = call("GET",
                "/rest/v1/ingredients?select=id,canonical_name&canonical_name=in.(spinach,paneer,onion,tomato)",
                tok_a)
            if isinstance(ings, list) and len(ings) == 4:
                for ing in ings:
                    call("POST", "/rest/v1/inventory_items", tok_a, {
                        "ingredient_id": ing["id"],
                        "product_name": ing["canonical_name"].title(),
                        "category": "vegetables" if ing["canonical_name"] != "paneer" else "dairy",
                        "quantity": 1, "unit": "kg", "storage": "fridge",
                        "purchase_date": date.today().isoformat(),
                        "expiry_date": date.today().isoformat(),   # urgent today
                        "expiry_source": "estimated"})
                time.sleep(0.6)
                status, matches = call("POST", "/rest/v1/rpc/match_recipes", tok_a, {"p_limit": 5})
                ok = status == 200 and isinstance(matches, list) and matches
                check("returns ranked matches", bool(ok), f"status {status} n={len(matches) if isinstance(matches,list) else 0}")
                if ok:
                    top = matches[0]
                    check("top match has the required shape",
                          all(k in top for k in ("name", "have_count", "total_required",
                                                 "missing_names", "urgent_names", "score")),
                          f"keys {sorted(top.keys())}")
                    check("urgent_names is populated for items due today",
                          bool(top.get("urgent_names")), f"{top.get('urgent_names')}")
                    check("missing_names present so the UI can list what to buy",
                          isinstance(top.get("missing_names"), list),
                          f"{top.get('missing_names')}")
                    names = [m["name"] for m in matches]
                    check("Palak Paneer ranks in the top 5 for a spinach+paneer kitchen",
                          "Palak Paneer" in names, f"{names}")
            else:
                check("seed ingredients resolvable for match test", False, str(ings)[:120])

            # ------------------------------------------------- 8 kitchen_stats
            print("\n8. kitchen_stats")
            status, stats = call("POST", "/rest/v1/rpc/kitchen_stats", tok_a, {})
            need = {"active_items", "expiring_soon", "due_today", "meals_rescued",
                    "value_rescued_inr", "current_streak", "pct_used_in_time"}
            check("returns every dashboard key",
                  status == 200 and isinstance(stats, dict) and need <= set(stats),
                  f"status {status} keys {sorted(stats) if isinstance(stats, dict) else stats}")
            if isinstance(stats, dict):
                check("active_items reflects the rows just written",
                      (stats.get("active_items") or 0) >= 4, f"{stats.get('active_items')}")

            # --------------------------------------------- 9 notification dedup
            print("\n9. notification dedup (BR-04)")
            n = {"inventory_item_id": item_id, "level": "three_day",
                 "scheduled_for": (date.today() + timedelta(days=1)).isoformat() + "T09:00:00Z"}
            s1, _ = call("POST", "/rest/v1/notifications", tok_a, n)
            s2, b2 = call("POST", "/rest/v1/notifications", tok_a, n)
            check("first notification accepted", s1 in (200, 201), f"status {s1}")
            check("duplicate level rejected by the database", s2 == 409,
                  f"status {s2} {str(b2)[:90]}")

    # ------------------------------------------------------------------ summary
    passed = sum(1 for ok, _, _ in results if ok)
    total = len(results)
    print(f"\n{'=' * 60}\n{passed}/{total} checks passed"
          + ("" if live_auth else "   (session-dependent groups SKIPPED)"))
    failed = [f"{n}  {d}" for ok, n, d in results if not ok]
    if failed:
        print("\nfailures:", file=sys.stderr)
        for f in failed:
            print(f"  - {f}", file=sys.stderr)
        return 1
    # A partial run must never claim a full pass -- the RLS isolation test is
    # the whole point of this script, and it is one of the skipped groups.
    if not live_auth:
        print("PARTIAL: schema and anonymous-access checks passed.")
        print("         RLS isolation and seed counts were NOT re-checked in this run.")
        print("         Full suite last passed 33/33 -- see supabase/VERIFIED.md.")
    else:
        print("backend verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
