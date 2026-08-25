#!/usr/bin/env python3
"""Split a contact sheet of produce renders into individual normalised PNGs.

Uses projection-profile splitting rather than connected-component labelling:
it cuts on empty gutters between items, which keeps a subject's separate
parts together (a garlic bulb and its loose clove stay one item, where blob
labelling would emit two).

Handles two kinds of input:
  * transparent background  -> subject mask taken from the alpha channel
  * flat opaque background  -> background colour sampled from the corners and
                               keyed out; the keyed mask becomes the alpha

Every output is 1024x1024 with the subject's longest edge at 76% of the
canvas, so items read at matching scale in equal-sized UI slots.

Usage:
    python tools/segment_sheet.py <sheet.png> [-o OUTDIR] [--cols N] [--rows N]
                                 [--min-frac 0.004] [--gutter 6] [--tol 40]
"""
from __future__ import annotations

import argparse
import pathlib
import sys

import numpy as np
from PIL import Image

CANVAS = 1024
SUBJECT_FRAC = 0.76


def build_mask(im: Image.Image, tol: int, split_alpha: int = 12) -> tuple[np.ndarray, str]:
    """Return (boolean subject mask, how it was derived)."""
    arr = np.array(im)
    alpha = arr[..., 3]

    # A genuinely transparent sheet has a large fraction of near-zero alpha.
    if (alpha < 16).mean() > 0.02:
        return alpha > split_alpha, "alpha"

    # Otherwise key out a flat background sampled from the four corners.
    rgb = arr[..., :3].astype(np.int16)
    h, w = alpha.shape
    corners = np.array([rgb[0, 0], rgb[0, w - 1], rgb[h - 1, 0], rgb[h - 1, w - 1]])
    bg = np.median(corners, axis=0)
    dist = np.abs(rgb - bg).sum(axis=2)
    return dist > tol, "keyed"


def spans(profile: np.ndarray, gutter: int, floor: float = 0.0) -> list[tuple[int, int]]:
    """Contiguous runs of occupied entries, merging gaps shorter than gutter.

    `floor` is a fraction of the profile's peak. Anything at or below it counts
    as empty, which is what separates items bridged only by faint shadow glow.
    """
    occupied = profile > (floor * profile.max() if floor else 0)
    out: list[list[int]] = []
    start = None
    for i, v in enumerate(occupied):
        if v and start is None:
            start = i
        elif not v and start is not None:
            out.append([start, i])
            start = None
    if start is not None:
        out.append([start, len(occupied)])

    merged: list[list[int]] = []
    for s in out:
        if merged and s[0] - merged[-1][1] < gutter:
            merged[-1][1] = s[1]
        else:
            merged.append(s)
    return [(a, b) for a, b in merged]


def find_cells(mask: np.ndarray, gutter: int, min_frac: float,
               floor: float = 0.0) -> list[tuple[int, int, int, int]]:
    """Bounding boxes of items: split into rows first, then columns within each row.

    Rows before columns is deliberate. Sheets are laid out in rows, and a row's
    own column profile is far cleaner than the whole sheet's, where a tall item
    in one row can bridge a gutter in another.
    """
    total = mask.shape[0] * mask.shape[1]
    cells: list[tuple[int, int, int, int]] = []

    for y0, y1 in spans(mask.sum(axis=1), gutter):
        band = mask[y0:y1, :]
        for x0, x1 in spans(band.sum(axis=0), gutter, floor):
            sub = mask[y0:y1, x0:x1]
            if sub.sum() / total < min_frac:
                continue
            # tighten to the actual content inside the cell
            ys, xs = np.nonzero(sub)
            cells.append((x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1))

    # Already in reading order: the loops walk rows outer, columns inner.
    # Do not re-sort by y — items in one row rarely share a top edge, and
    # bucketing on y reorders them.
    return cells


def normalise(im: Image.Image, mask: np.ndarray, box: tuple[int, int, int, int]) -> Image.Image:
    """Crop one item and place it on a 1024 canvas at the standard scale."""
    x0, y0, x1, y1 = box
    tile = im.crop(box).convert("RGBA")

    # Only a keyed sheet needs the derived mask; a transparent sheet already
    # carries correct soft alpha, and overwriting it would harden the shadows.
    sub = mask[y0:y1, x0:x1]
    a = np.array(tile)[..., 3]
    if (a < 16).mean() <= 0.02:
        arr = np.array(tile)
        arr[..., 3] = np.where(sub, 255, 0).astype(np.uint8)
        tile = Image.fromarray(arr, "RGBA")

    bbox = tile.getchannel("A").getbbox()
    if bbox:
        tile = tile.crop(bbox)

    target = int(CANVAS * SUBJECT_FRAC)
    bw, bh = tile.size
    scale = target / max(bw, bh)
    tile = tile.resize((max(1, round(bw * scale)), max(1, round(bh * scale))), Image.LANCZOS)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(tile, ((CANVAS - tile.width) // 2, (CANVAS - tile.height) // 2), tile)
    return canvas


def contact_sheet(items: list[Image.Image], path: pathlib.Path, cols: int = 6) -> None:
    """Numbered review grid, so each crop can be identified before naming."""
    from PIL import ImageDraw

    cell = 240
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 28)), (250, 247, 242))
    draw = ImageDraw.Draw(sheet)
    for i, item in enumerate(items):
        thumb = item.copy()
        thumb.thumbnail((cell - 24, cell - 24))
        x = (i % cols) * cell + (cell - thumb.width) // 2
        y = (i // cols) * (cell + 28) + 12
        flat = Image.new("RGBA", thumb.size, (255, 255, 255, 255))
        sheet.paste(Image.alpha_composite(flat, thumb).convert("RGB"), (x, y))
        draw.text(((i % cols) * cell + 10, (i // cols) * (cell + 28) + cell + 6),
                  f"#{i + 1}", fill=(30, 40, 35))
    sheet.save(path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("-o", "--outdir", default="segmented")
    ap.add_argument("--gutter", type=int, default=6,
                    help="minimum empty pixels that count as a separator")
    ap.add_argument("--min-frac", type=float, default=0.004,
                    help="drop blobs smaller than this fraction of the sheet")
    ap.add_argument("--tol", type=int, default=40,
                    help="background keying tolerance for opaque sheets")
    ap.add_argument("--split-alpha", type=int, default=12,
                    help="alpha threshold for the SPLITTING mask only; output keeps the original soft alpha")
    ap.add_argument("--floor", type=float, default=0.0,
                    help="column counts at or below this fraction of the row peak count as empty; "
                         "raise it to separate items bridged by soft shadow glow")
    args = ap.parse_args()

    src = pathlib.Path(args.sheet)
    if not src.exists():
        print(f"not found: {src}", file=sys.stderr)
        return 1

    im = Image.open(src).convert("RGBA")
    mask, how = build_mask(im, args.tol, args.split_alpha)
    cells = find_cells(mask, args.gutter, args.min_frac, args.floor)

    out = pathlib.Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)

    items = []
    for i, box in enumerate(cells, 1):
        norm = normalise(im, mask, box)
        norm.save(out / f"item-{i:02d}.png", optimize=True)
        items.append(norm)

    if items:
        contact_sheet(items, out / "_review.png")

    print(f"sheet      : {src.name}  {im.width}x{im.height}")
    print(f"background : {how}")
    print(f"items found: {len(cells)}")
    for i, (x0, y0, x1, y1) in enumerate(cells, 1):
        print(f"  #{i:02d}  box=({x0},{y0})-({x1},{y1})  {x1-x0}x{y1-y0}")
    print(f"\nwrote {len(items)} files to {out}/  plus _review.png for identification")
    if how == "keyed":
        print("\nNOTE: background was keyed, not alpha. Soft shadows and any "
              "anti-aliased edge may show a faint halo. A transparent sheet gives cleaner results.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
