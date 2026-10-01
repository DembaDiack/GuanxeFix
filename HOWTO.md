# Guanxe on WSA — HOWTO

Everything needed to run **Guanxe** (`com.guanxe.guanxeprime`) on **Windows Subsystem for Android** (x86_64 + Magisk), including native-lib fix, wide window, and updating to new versions.

---

## Problems we hit (and why)

| Symptom | Cause | Fix |
|--------|--------|-----|
| App opens then instantly dies | Play only installs **arm64** libs; SoLoader can’t find `libreactnative.so` on WSA | Extract `lib/arm64-v8a/*.so` → app `lib/arm64/` (Magisk module) |
| Want a wide / landscape window | Manifest locks `screenOrientation="portrait"` → letterboxed phone UI | Patch orientation to `fullUser`, **without** rebuilding resources |
| Grey screen / Account crash after “apktool rebuild” | apktool corrupts AppCompat drawables (`rn_edit_text_material`, `abc_switch_thumb_material`, …) | Keep **original** `res/` + `resources.arsc`; only change the manifest |
| Crash: `No BuiltInsLoader implementation` | Signing stripped `META-INF/services/` | When resigning, keep `META-INF/services/*`, only drop `*.SF` / `*.RSA` / `MANIFEST.MF` |
| Install error about `resources.arsc` | Must be **STORED** (uncompressed) + 4-byte zipaligned | Write arsc as `ZIP_STORED`, then uber-apk-signer / zipalign |

**Do not** do a full `apktool` resource decode/rebuild for this app. That path is cursed.

---

## What lives where

```
C:\Users\demba\guanxe-wsa-fix\          ← this project
├── HOWTO.md                              ← this file
├── README.md                             ← Magisk module short readme
├── module.prop / service.sh / action.sh  ← Magisk module
├── scripts\guanxe-fix.sh                 ← on-device: install APKs + lib fix
├── tools\
│   ├── make-wide-apk.ps1                 ← on PC: build wide sideload APKs
│   ├── merge_wide_apk.py                 ← used by the PS1 script
│   └── (downloads apktool / uber-apk-signer on first run)
└── guanxe-wsa-fix.zip                    ← flashable Magisk zip

On device:
  /data/adb/modules/guanxe-wsa-fix/       ← installed Magisk module
  /sdcard/GuanxeFix/incoming/             ← drop new APKs/APKS here
  /sdcard/GuanxeFix/processed/            ← after Action runs
  /data/local/tmp/guanxe-fix.log          ← module log
```

---

## One-time setup

### 1. Magisk module (lib fix — required always)

1. Flash `guanxe-wsa-fix.zip` in Magisk (or copy folder to `/data/adb/modules/guanxe-wsa-fix/`).
2. Reboot once so Magisk mounts it and starts `service.sh`.
3. Magisk → **Guanxe WSA Fix** → **Action** after any fresh install / Play update.

What Action / boot service does:

- Optionally installs from `/sdcard/GuanxeFix/incoming/`
- Extracts arm64 `.so` files into the app’s `lib/arm64/`
- Re-checks every 5 minutes on boot service

### 2. PC tools (only if you want the **wide** build)

- Java 17+ on PATH  
- Script auto-downloads **apktool** + **uber-apk-signer** into `%TEMP%\apktools\`  
- `adb` on PATH (for optional install)

---

## Daily workflows

### A) Play Store update (portrait is fine; widest via dragging)

1. Update Guanxe in Play.
2. Magisk → Guanxe WSA Fix → **Action** (or wait for boot poll).
3. Open Guanxe. Resize the freeform window if you want it bigger (still portrait-locked).

### B) Sideload a new version + lib fix only

1. Put `*.apks` / `*.xapk` / split `*.apk` into `/sdcard/GuanxeFix/incoming/`
2. Magisk → **Action**
3. Launch Guanxe

### C) New version **with wide / landscape unlocked** (recommended desktop UX)

This resigns the app (Play cannot update over it until you uninstall).

#### 1) Get the split APKs

From WSA after Play has the version you want:

```powershell
adb connect 127.0.0.1:58526
adb shell pm path com.guanxe.guanxeprime
# pull each package: path shown (base + arm64 + dpi/lang splits)
adb pull <path> .
```

Or download an `.apks` / `.xapk` bundle (must include **arm64-v8a**).

Put them in a folder, e.g. `C:\Users\demba\GuanxeApks\2.2.9\`:

- `base.apk` (or `*-base*.apk`)
- `split_config.arm64_v8a.apk`
- `split_config.*.apk` (en, hdpi, …)

#### 2) Build the wide package on the PC

```powershell
cd C:\Users\demba\guanxe-wsa-fix
.\tools\make-wide-apk.ps1 -InputDir "C:\Users\demba\GuanxeApks\2.2.9" -OutDir "C:\Users\demba\GuanxeApks\2.2.9-wide"
```

What the script does:

1. `apktool d` decode (edits **manifest only** conceptually; we discard rebuilt resources)
2. Sets `android:screenOrientation="fullUser"`
3. `apktool b` rebuild
4. Merges **original** `res/` + `resources.arsc` (STORED) back in
5. Keeps `META-INF/services/*`
6. Signs base + all splits with the same debug key (uber-apk-signer)
7. Writes ready-to-install APKs into `-OutDir`

#### 3) Install on WSA

```powershell
adb connect 127.0.0.1:58526
adb uninstall com.guanxe.guanxeprime   # ok if it errors
adb install-multiple (Get-ChildItem "C:\Users\demba\GuanxeApks\2.2.9-wide\*.apk").FullName
adb shell su -c "guanxe-fix --fix-libs-only"
# optional: allow free rotation / ignore portrait requests
adb shell wm set-ignore-orientation-request true
adb shell am start -n com.guanxe.guanxeprime/.MainActivity
```

Or copy the wide APKs to `/sdcard/GuanxeFix/incoming/` and tap Magisk **Action** (still run lib fix — Action does both).

#### 4) Resize window (optional)

```powershell
# find task id from: adb shell dumpsys activity activities | findstr guanxe
adb shell am task resizeable <TASK_ID> 2
adb shell am task resize <TASK_ID> 100 50 1750 1050
```

Or just drag the Windows window edges.

---

## Magisk module CLI (on device, root)

```sh
guanxe-fix                  # install from incoming (if any) + fix libs
guanxe-fix --fix-libs-only
guanxe-fix --install /sdcard/GuanxeFix/incoming/foo.apks
```

Env:

- `GUANXE_PKG` (default `com.guanxe.guanxeprime`)
- `GUANXE_DROP` (default `/sdcard/GuanxeFix`)

---

## Updating this toolkit later

1. New Guanxe version → pull splits → `make-wide-apk.ps1` → install-multiple → `guanxe-fix --fix-libs-only`
2. If only Play portrait build → just **Action** after update
3. If Magisk module scripts change → re-zip / re-copy to `/data/adb/modules/guanxe-wsa-fix/` and reboot

Rebuild the flashable zip from the project folder:

```powershell
cd C:\Users\demba\guanxe-wsa-fix
# ensure LF line endings on .sh files, then:
tar -a -cf C:\Users\demba\guanxe-wsa-fix.zip module.prop customize.sh service.sh action.sh README.md HOWTO.md META-INF scripts
```

---

## Quick diagnosis

```powershell
adb connect 127.0.0.1:58526
adb logcat -d | Select-String "SoLoaderDSONotFound|libreactnative|abc_switch_thumb|BuiltInsLoader|FATAL EXCEPTION"
adb shell "ls /data/app/*/com.guanxe.guanxeprime-*/lib/arm64/libreactnative.so"
adb shell "dumpsys package com.guanxe.guanxeprime | grep -E versionName|primaryCpuAbi"
```

| Log / check | Meaning |
|-------------|---------|
| `couldn't find DSO … libreactnative.so` | Run Magisk Action / `--fix-libs-only` |
| `abc_switch_thumb_material` / `@null` drawable | Bad apktool resource rebuild — use `make-wide-apk.ps1` merge path |
| `BuiltInsLoader` | META-INF/services stripped — use updated merge script |
| `resources.arsc` install −124 | arsc not STORED/aligned — rebuild with `make-wide-apk.ps1` |

---

## Current known-good state (as of this write-up)

- Package: `com.guanxe.guanxeprime` **2.2.9**
- Wide sideload: orientation `fullUser` + original resources + services + arm64 lib extract
- Magisk module: `guanxe-wsa-fix` installed under `/data/adb/modules/`
- WSA ADB: `127.0.0.1:58526`
