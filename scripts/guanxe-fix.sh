#!/system/bin/sh
# guanxe-fix.sh — install Guanxe APKs + extract arm64 native libs for WSA
#
# Usage:
#   guanxe-fix.sh                 # same as --install-and-fix
#   guanxe-fix.sh --fix-libs-only
#   guanxe-fix.sh --install-and-fix
#   guanxe-fix.sh --install /path/to/file.apks
#   guanxe-fix.sh --fix-libs
#
# Drop folder (default): /sdcard/GuanxeFix/incoming
#   Put .apk / .apks / .xapk / .apkm (or a folder of split APKs) there,
#   then run Action in Magisk or: guanxe-fix --install-and-fix

set -u

PKG="${GUANXE_PKG:-com.guanxe.guanxeprime}"
DROP="${GUANXE_DROP:-/sdcard/GuanxeFix}"
INCOMING="$DROP/incoming"
PROCESSED="$DROP/processed"
WORKDIR="/data/local/tmp/guanxe-fix-work"
NEEDED_LIB="libreactnative.so"

log() { echo "[guanxe-fix] $*"; }
die() { log "ERROR: $*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

ensure_dirs() {
  mkdir -p "$INCOMING" "$PROCESSED" "$WORKDIR"
}

bb_unzip() {
  # Prefer Magisk busybox unzip
  if [ -x /data/adb/magisk/busybox ]; then
    /data/adb/magisk/busybox unzip "$@"
  elif have unzip; then
    unzip "$@"
  elif have toybox && toybox unzip -h >/dev/null 2>&1; then
    toybox unzip "$@"
  else
    die "no unzip available"
  fi
}

find_app_dir() {
  # Prefer pm path (works without globbing quirks)
  local base
  base=$(pm path "$PKG" 2>/dev/null | head -n 1 | sed 's/^package://')
  [ -n "$base" ] || return 1
  dirname "$base"
}

arm64_split_path() {
  pm path "$PKG" 2>/dev/null | sed 's/^package://' | grep -E 'arm64|arm64_v8a' | head -n 1
}

libs_ok() {
  local app="$1"
  [ -f "$app/lib/arm64/$NEEDED_LIB" ]
}

extract_libs_from_apk() {
  local apk="$1"
  local dest="$2"
  local tmp="$WORKDIR/libextract"

  rm -rf "$tmp"
  mkdir -p "$tmp" "$dest"

  # Extract only native libs
  bb_unzip -o "$apk" "lib/arm64-v8a/*" -d "$tmp" >/dev/null 2>&1 \
    || bb_unzip -o "$apk" "lib/*/libreactnative.so" -d "$tmp" >/dev/null 2>&1 \
    || die "failed to unzip native libs from $apk"

  local src
  src=$(find "$tmp" -type d -name "arm64-v8a" 2>/dev/null | head -n 1)
  [ -n "$src" ] || src=$(find "$tmp/lib" -type d 2>/dev/null | head -n 1)
  [ -d "$src" ] || die "no arm64-v8a libs inside $apk"

  cp -f "$src"/*.so "$dest/" || die "copy libs failed"
  chmod 755 "$dest"
  chmod 755 "$dest"/*.so
  chown system:system "$dest" "$dest"/*.so 2>/dev/null
  chcon -R u:object_r:apk_data_file:s0 "$dest" 2>/dev/null
  restorecon -RF "$(dirname "$dest")" 2>/dev/null
  log "installed $(ls "$dest"/*.so 2>/dev/null | wc -l | tr -d ' ') .so files → $dest"
}

fix_libs() {
  local app split
  app=$(find_app_dir) || die "$PKG is not installed"
  log "app dir: $app"

  if libs_ok "$app"; then
    log "libs already present ($NEEDED_LIB) — OK"
    return 0
  fi

  mkdir -p "$app/lib/arm64"
  split=$(arm64_split_path)
  if [ -z "$split" ] || [ ! -f "$split" ]; then
    # Fallback: sometimes libs are inside base.apk
    split="$app/base.apk"
  fi
  [ -f "$split" ] || die "could not find arm64 split or base.apk"
  log "extracting libs from: $split"
  extract_libs_from_apk "$split" "$app/lib/arm64"

  libs_ok "$app" || die "lib fix failed — $NEEDED_LIB still missing"
  log "lib fix OK"
}

# Collect APKs from a directory into WORKDIR/apks
collect_apks_from_dir() {
  local src="$1"
  local out="$WORKDIR/apks"
  rm -rf "$out"
  mkdir -p "$out"
  local n=0
  for f in "$src"/*.apk "$src"/*.APK; do
    [ -f "$f" ] || continue
    cp -f "$f" "$out/"
    n=$((n + 1))
  done
  [ "$n" -gt 0 ] || return 1
  echo "$out"
}

# Expand .apks / .xapk / .apkm (zip) into WORKDIR/apks
expand_bundle() {
  local bundle="$1"
  local out="$WORKDIR/apks"
  local tmp="$WORKDIR/bundle"
  rm -rf "$out" "$tmp"
  mkdir -p "$out" "$tmp"
  bb_unzip -o "$bundle" -d "$tmp" >/dev/null || die "failed to unzip $bundle"
  local n=0
  # shellcheck disable=SC2044
  for f in $(find "$tmp" -type f -name "*.apk"); do
    cp -f "$f" "$out/"
    n=$((n + 1))
  done
  [ "$n" -gt 0 ] || die "no .apk files inside $bundle"
  log "expanded $n APK(s) from $(basename "$bundle")"
  echo "$out"
}

install_apk_dir() {
  local dir="$1"
  local list=""
  local f
  for f in "$dir"/*.apk; do
    [ -f "$f" ] || continue
    list="$list $f"
  done
  [ -n "$list" ] || die "no APKs to install in $dir"
  log "pm install-multiple:$list"
  # -r replace, -t allow test, -g grant runtime perms where possible
  pm install-multiple -r -t --user 0 $list || die "pm install-multiple failed"
  log "install OK"
}

pick_incoming() {
  # Prefer explicit bundles, then a folder of apks, then loose apks
  local f
  for f in "$INCOMING"/*.apks "$INCOMING"/*.xapk "$INCOMING"/*.apkm \
           "$INCOMING"/*.APKS "$INCOMING"/*.XAPK "$INCOMING"/*.APKM; do
    [ -f "$f" ] || continue
    echo "$f"
    return 0
  done
  # Loose APKs in incoming
  for f in "$INCOMING"/*.apk "$INCOMING"/*.APK; do
    [ -f "$f" ] || continue
    echo "DIR:$INCOMING"
    return 0
  done
  return 1
}

archive_incoming() {
  local stamp
  stamp=$(date +%Y%m%d-%H%M%S)
  mkdir -p "$PROCESSED/$stamp"
  mv "$INCOMING"/* "$PROCESSED/$stamp/" 2>/dev/null
  log "moved incoming → $PROCESSED/$stamp"
}

install_from_path() {
  local path="$1"
  local apks_dir=""

  case "$path" in
    DIR:*)
      apks_dir=$(collect_apks_from_dir "${path#DIR:}") || die "no APKs in ${path#DIR:}"
      ;;
    *.apks|*.APKS|*.xapk|*.XAPK|*.apkm|*.APKM)
      apks_dir=$(expand_bundle "$path")
      ;;
    *.apk|*.APK)
      rm -rf "$WORKDIR/apks"
      mkdir -p "$WORKDIR/apks"
      cp -f "$path" "$WORKDIR/apks/"
      apks_dir="$WORKDIR/apks"
      ;;
    *)
      if [ -d "$path" ]; then
        apks_dir=$(collect_apks_from_dir "$path") || die "no APKs in $path"
      else
        die "unsupported path: $path"
      fi
      ;;
  esac

  install_apk_dir "$apks_dir"
}

install_from_incoming() {
  local pick
  pick=$(pick_incoming) || {
    log "nothing in $INCOMING — skipping install"
    return 1
  }
  log "incoming: $pick"
  install_from_path "$pick"
  archive_incoming
  return 0
}

cmd_fix_libs_only() {
  ensure_dirs
  if ! pm path "$PKG" >/dev/null 2>&1; then
    log "$PKG not installed — nothing to fix"
    return 0
  fi
  fix_libs
}

cmd_install_and_fix() {
  ensure_dirs
  if install_from_incoming; then
    :
  elif pm path "$PKG" >/dev/null 2>&1; then
    log "using already-installed $PKG"
  else
    die "install $PKG first (Play Store) or drop APKs in $INCOMING"
  fi
  # Give PackageManager a moment to settle paths
  sleep 2
  fix_libs
  log "all done — launch $PKG"
}

# --- main ---
MODE="${1:---install-and-fix}"
case "$MODE" in
  --fix-libs-only|--fix-libs)
    cmd_fix_libs_only
    ;;
  --install-and-fix)
    cmd_install_and_fix
    ;;
  --install)
    [ -n "${2:-}" ] || die "usage: $0 --install <apk|apks|dir>"
    ensure_dirs
    install_from_path "$2"
    sleep 2
    fix_libs
    ;;
  -h|--help)
    sed -n '2,20p' "$0"
    ;;
  *)
    die "unknown option: $MODE (try --help)"
    ;;
esac
