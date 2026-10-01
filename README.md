# Guanxe WSA Fix (Magisk module)

On-device part of the Guanxe-on-WSA toolkit: installs APKs you drop in a folder and extracts **arm64** native libs so Guanxe starts on x86_64 WSA.

**Full guide (wide window, new versions, troubleshooting): see [HOWTO.md](HOWTO.md).**

## Magisk module — what it does

1. **Lib fix (required)** — copies `lib/arm64-v8a/*.so` from the arm64 split into the app’s `lib/arm64/`.
2. **Optional install** — installs from `/sdcard/GuanxeFix/incoming/` (`.apk` / `.apks` / `.xapk` / `.apkm`).
3. **On boot** — re-applies the lib fix (and polls every 5 minutes).

Wide / landscape unlocking is done on the **PC** with `tools/make-wide-apk.ps1` (see HOWTO), then install the signed APKs and run this module’s lib fix.

## Install module

1. Flash `guanxe-wsa-fix.zip` in Magisk (or copy this folder to `/data/adb/modules/guanxe-wsa-fix/`).
2. Reboot once.

## Everyday use

| Goal | Steps |
|------|--------|
| After Play update | Magisk → **Guanxe WSA Fix** → **Action** |
| Sideload new APKs | Drop into `/sdcard/GuanxeFix/incoming/` → **Action** |
| Wide window build | PC: `.\tools\make-wide-apk.ps1 -InputDir ... -OutDir ...` → install-multiple → **Action** / `guanxe-fix --fix-libs-only` |

## CLI (device, root)

```sh
guanxe-fix
guanxe-fix --fix-libs-only
guanxe-fix --install /sdcard/GuanxeFix/incoming/guanxe.apks
```

Log: `/data/local/tmp/guanxe-fix.log`
