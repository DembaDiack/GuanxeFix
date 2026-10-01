#!/system/bin/sh
# Magisk Action button: install from drop folder (if any) + apply lib fix
MODDIR="${0%/*}"
FIX="$MODDIR/scripts/guanxe-fix.sh"
LOG=/data/local/tmp/guanxe-fix.log

chmod 755 "$FIX" 2>/dev/null
echo "===== $(date) action =====" >> "$LOG"
"$FIX" --install-and-fix >> "$LOG" 2>&1
RC=$?
tail -n 40 "$LOG"
exit $RC
