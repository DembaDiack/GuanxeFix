#!/usr/bin/env python3
"""Merge apktool-rebuilt base (new manifest) with original resources + keep META-INF/services."""
from __future__ import annotations

import argparse
import zipfile
from pathlib import Path

SIG_SUFFIXES = (".SF", ".RSA", ".DSA", ".EC")
SIG_NAMES = {"MANIFEST.MF", "ANDROIDD.SF", "ANDROIDD.RSA", "CERT.SF", "CERT.RSA"}


def is_signature(name: str) -> bool:
    if not name.startswith("META-INF/"):
        return False
    base = name.rsplit("/", 1)[-1]
    if base in SIG_NAMES:
        return True
    return any(base.endswith(s) for s in SIG_SUFFIXES)


def merge(built: Path, original: Path, out: Path) -> None:
    if out.exists():
        out.unlink()

    with zipfile.ZipFile(built, "r") as zb, zipfile.ZipFile(original, "r") as zo, zipfile.ZipFile(
        out, "w"
    ) as zout:
        for info in zb.infolist():
            name = info.filename
            if is_signature(name):
                continue
            if name == "resources.arsc" or name.startswith("res/"):
                continue
            data = zb.read(name)
            new = zipfile.ZipInfo(filename=name, date_time=info.date_time)
            new.compress_type = zipfile.ZIP_DEFLATED
            new.external_attr = info.external_attr
            zout.writestr(new, data)

        for info in zo.infolist():
            name = info.filename
            if name != "resources.arsc" and not name.startswith("res/"):
                continue
            data = zo.read(name)
            new = zipfile.ZipInfo(filename=name, date_time=info.date_time)
            new.compress_type = (
                zipfile.ZIP_STORED if name == "resources.arsc" else info.compress_type
            )
            new.external_attr = info.external_attr
            zout.writestr(new, data, compress_type=new.compress_type)

    with zipfile.ZipFile(out) as z:
        arsc = z.getinfo("resources.arsc")
        services = [n for n in z.namelist() if n.startswith("META-INF/services/")]
        print(f"wrote {out} ({out.stat().st_size} bytes)")
        print(f"resources.arsc compress_type={arsc.compress_type} (0=STORED)")
        print(f"META-INF/services entries: {len(services)}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--built", required=True, type=Path, help="apktool-built APK (bad resources OK)")
    p.add_argument("--original", required=True, type=Path, help="original Play base.apk")
    p.add_argument("--out", required=True, type=Path)
    args = p.parse_args()
    merge(args.built, args.original, args.out)


if __name__ == "__main__":
    main()
