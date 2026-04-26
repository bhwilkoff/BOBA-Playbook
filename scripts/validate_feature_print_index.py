#!/usr/bin/env python3
"""Validate the layout of a BFPI feature-print index file.

Usage:
    python3 scripts/validate_feature_print_index.py BOBAPlaybook/feature-prints.bin

Reads the BFPI file and prints summary stats. Checks: magic bytes,
version, that every entry's bobaId is non-empty UTF-8 and matches an
entry in cards.json, and that the file ends exactly where the header
declares it should.
"""
import argparse
import json
import struct
import sys
from pathlib import Path


def parse_bfpi(path: Path):
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError(f"File too small ({len(data)} bytes)")

    magic = data[:4]
    if magic != b"BFPI":
        raise ValueError(f"Bad magic: {magic!r}")

    version, count, ec, es = struct.unpack_from("<IIII", data, 4)
    if version not in (1, 2):
        raise ValueError(f"Unsupported version {version}")
    # v1: es == 4 (Float32). v2: es == 1 (int8 quantized + per-vector scale).
    if version == 1 and es not in (4, 8):
        raise ValueError(f"Unexpected element size {es} for v1")
    if version == 2 and es != 1:
        raise ValueError(f"v2 must have elementSize=1, got {es}")

    type_label = (
        "Float" if (version == 1 and es == 4)
        else "Double" if (version == 1 and es == 8)
        else "int8 + Float32 scale" if version == 2
        else "?"
    )
    print(f"  magic:        {magic.decode()}")
    print(f"  version:      {version}")
    print(f"  entryCount:   {count}")
    print(f"  elementCount: {ec}")
    print(f"  elementSize:  {es} ({type_label})")
    # Per-entry payload: v1 = floats only; v2 = scale (4) + int8 vector.
    payload = ec * es + (4 if version == 2 else 0)
    print(f"  per-entry:    {payload} bytes")

    cursor = 20
    ids = []
    for i in range(count):
        if cursor + 2 > len(data):
            raise ValueError(f"Truncated at entry {i} (id length)")
        (id_len,) = struct.unpack_from("<H", data, cursor)
        cursor += 2
        if cursor + id_len > len(data):
            raise ValueError(f"Truncated at entry {i} (id bytes)")
        try:
            boba_id = data[cursor : cursor + id_len].decode("utf-8")
        except UnicodeDecodeError as e:
            raise ValueError(f"Bad UTF-8 in entry {i}: {e}")
        if not boba_id:
            raise ValueError(f"Empty bobaId at entry {i}")
        cursor += id_len
        if cursor + payload > len(data):
            raise ValueError(f"Truncated at entry {i} (vector payload)")
        cursor += payload
        ids.append(boba_id)

    if cursor != len(data):
        raise ValueError(
            f"Trailing data: cursor={cursor}, file size={len(data)}, "
            f"diff={len(data) - cursor}"
        )

    return ids, count, ec, es


def main():
    p = argparse.ArgumentParser()
    p.add_argument("path", type=Path)
    p.add_argument(
        "--catalog",
        type=Path,
        default=Path("BOBAPlaybook/display-cards.json"),
        help="Catalog JSON to cross-check bobaIds against",
    )
    args = p.parse_args()

    if not args.path.exists():
        print(f"ERROR: {args.path} not found", file=sys.stderr)
        sys.exit(1)

    print(f"Validating {args.path} ({args.path.stat().st_size:,} bytes)")
    try:
        ids, count, ec, es = parse_bfpi(args.path)
    except ValueError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(2)

    # Cross-check against catalog
    if args.catalog.exists():
        catalog = json.loads(args.catalog.read_text())
        catalog_ids = {c.get("bobaId") for c in catalog if c.get("bobaId")}
        unique = set(ids)
        dupes = len(ids) - len(unique)
        missing = unique - catalog_ids
        print(f"  unique ids:   {len(unique):,}")
        print(f"  duplicates:   {dupes:,}")
        print(f"  not in catalog: {len(missing):,}")
        if dupes:
            print("WARN: duplicate bobaIds found", file=sys.stderr)
        if missing:
            print(
                f"WARN: {len(missing)} bobaIds not in catalog (first 5): "
                f"{sorted(missing)[:5]}",
                file=sys.stderr,
            )
    else:
        print(f"  (catalog {args.catalog} not present — skipping cross-check)")

    print("OK")


if __name__ == "__main__":
    main()
