#!/system/bin/sh
# Magisk module installer (runs during flash)

SKIPUNZIP=0
ui_print "- Guanxe WSA Fix"

DROP_DIR="/sdcard/GuanxeFix"
mkdir -p "$DROP_DIR/incoming" "$DROP_DIR/processed"
ui_print "- Drop APKs here: $DROP_DIR/incoming"
ui_print "  Supported: .apk / .apks / .xapk / .apkm"
ui_print "- Then Magisk → Guanxe WSA Fix → Action"
ui_print "- Full docs: HOWTO.md (wide window + new versions)"

# Make main script executable after install
set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755

# Convenience symlink for adb shell / terminal
mkdir -p "$MODPATH/system/bin"
ln -sf "$MODPATH/scripts/guanxe-fix.sh" "$MODPATH/system/bin/guanxe-fix" 2>/dev/null || \
  cp -f "$MODPATH/scripts/guanxe-fix.sh" "$MODPATH/system/bin/guanxe-fix"
set_perm "$MODPATH/system/bin/guanxe-fix" 0 0 0755

ui_print "- Done. Reboot once after first install."
