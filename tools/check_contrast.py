#!/usr/bin/env python3
"""Assert WCAG AA contrast for every declared ShelfLife token pair.

Exits non-zero on any failure so this is usable as a CI gate.
Large-text threshold (3.0:1) applies at >=24px; everything else needs 4.5:1.

Pairs are declared in tools/token_pairs.json. A pair that is absent is
absent on purpose -- e.g. text/on-deep-tertiary over surface/canvas
measures 3.91:1 and is illegal per decision D12.
"""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def _lin(channel: int) -> float:
    c = channel / 255
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def luminance(hex_colour: str) -> float:
    h = hex_colour.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)


def ratio(fg: str, bg: str) -> float:
    a, b = luminance(fg), luminance(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def main() -> int:
    tokens = json.loads((ROOT / "design/tokens.json").read_text(encoding="utf-8"))
    pairs = json.loads((ROOT / "tools/token_pairs.json").read_text(encoding="utf-8"))
    colours = tokens["colour"]

    failures = []
    for pair in pairs:
        fg_name, bg_name = pair["fg"], pair["bg"]
        if fg_name not in colours or bg_name not in colours:
            failures.append(f"missing token: {fg_name} or {bg_name}")
            print(f"FAIL  ----  missing token: {fg_name} / {bg_name}")
            continue

        fg, bg = colours[fg_name], colours[bg_name]
        needed = 3.0 if pair["minPx"] >= 24 else 4.5
        got = ratio(fg, bg)
        ok = got >= needed
        print(f"{'ok  ' if ok else 'FAIL'} {got:5.2f} (need {needed}) "
              f"{fg_name} {fg} on {bg_name} {bg} - {pair['use']}")
        if not ok:
            failures.append(f"{fg_name} on {bg_name}: {got:.2f} < {needed}")

    print()
    if failures:
        print(f"{len(failures)} contrast failure(s):", file=sys.stderr)
        for f in failures:
            print(f"  - {f}", file=sys.stderr)
        return 1

    print(f"All {len(pairs)} pairs pass WCAG AA.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
