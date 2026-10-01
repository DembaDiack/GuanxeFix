#!/system/bin/sh
# Magisk late_start service: re-apply native lib fix after boot / Play updates
MODDIR="${0%/*}"
FIX="$MODDIR/scripts/guanxe-fix.sh"

# Wait until boot is done and package manager is up
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 60 ]; do
  sleep 2
  i=$((i + 1))
done
sleep 10

[ -x "$FIX" ] || chmod 755 "$FIX"

# Fix once at boot
"$FIX" --fix-libs-only >> /data/local/tmp/guanxe-fix.log 2>&1

# Keep watching for updates (Play install replaces app path / empties lib dir)
# Poll every 5 minutes — cheap and reliable without inotify dependency
while true; do
  sleep 300
  "$FIX" --fix-libs-only >> /data/local/tmp/guanxe-fix.log 2>&1
done
