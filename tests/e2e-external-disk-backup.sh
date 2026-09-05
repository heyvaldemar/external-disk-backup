#!/bin/bash
# Does it refuse to do the wrong thing?
#
# The scenarios that matter here are the refusals. A backup script that copies
# correctly is easy; one that declines to copy onto the disk it is protecting,
# and that keeps what you deleted by accident, is the whole point.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/external-disk-backup.sh"
WORK="$(mktemp -d)"
PASSED=0; FAILED=0
trap 'rm -rf "$WORK"' EXIT

pass() { echo "  PASS: $1"; PASSED=$((PASSED+1)); }
fail() { echo "  FAIL: $1"; FAILED=$((FAILED+1)); }

run() {
  BACKUP_TARGET="$WORK/target" BACKUP_SOURCES="$WORK/src" \
  BACKUP_STATE_DIR="$WORK/state" BACKUP_TRASH_DAYS="${TRASH_DAYS:-30}" \
  bash "$SCRIPT" "${1:-}" 2>&1
}

echo "=== external disk backup: does it refuse to do the wrong thing? ==="
echo
mkdir -p "$WORK/src/photos" "$WORK/target" "$WORK/state"
echo "one" > "$WORK/src/photos/one.txt"
echo "two" > "$WORK/src/photos/two.txt"

# 1. THE ONE THAT MATTERS. The target directory exists and is empty, exactly as
#    it looks when the removable disk is not mounted. Nothing may be written.
out="$(run)"; rc=$?
if [ $rc -ne 0 ] && [ -z "$(ls -A "$WORK/target")" ]; then
  pass "an unmounted target is refused and nothing is written to it"
else
  fail "it copied onto an unmounted target"; printf '%s\n' "$out" | sed 's/^/        /' | tail -4
fi

# 2. and it says what to do about it, rather than just failing
if printf '%s' "$out" | grep -q "touch $WORK/target/.backup-target"; then
  pass "the refusal tells you how to make it a real target"
else
  fail "the refusal gave no remedy"
fi

# 3. no OK stamp from a refused run, but a RUN stamp all the same
if [ -f "$WORK/state/last-run" ] && [ ! -f "$WORK/state/last-ok" ]; then
  pass "a refused run stamps that it ran and not that it worked"
else
  fail "the stamps do not distinguish running from working"
fi

# ---- now make it a real target
touch "$WORK/target/.backup-target"

# 4. the happy path
out="$(run)"; rc=$?
if [ $rc -eq 0 ] && [ -f "$WORK/target/src/photos/one.txt" ]; then
  pass "with the marker present the sources are copied"
else
  fail "the copy did not happen"; printf '%s\n' "$out" | sed 's/^/        /' | tail -6
fi
if [ -f "$WORK/state/last-ok" ]; then pass "a clean run writes the OK stamp"; else fail "no OK stamp after a clean run"; fi

# 5. A MIRROR IS NOT A BACKUP. Delete something at the source, run again, and
#    it must still be recoverable from the copy.
rm "$WORK/src/photos/one.txt"
run >/dev/null 2>&1
if [ ! -f "$WORK/target/src/photos/one.txt" ] \
   && [ -n "$(find "$WORK/target/_trash" -name 'one.txt' -print -quit 2>/dev/null)" ]; then
  pass "a file deleted at the source is gone from the mirror and kept in the trash"
else
  fail "a deleted file was not recoverable"
  find "$WORK/target" -name 'one.txt' | sed 's/^/        /'
fi

# 6. an overwritten file keeps its previous contents too
echo "changed" > "$WORK/src/photos/two.txt"
run >/dev/null 2>&1
if grep -rq '^two$' "$WORK/target/_trash" 2>/dev/null; then
  pass "an overwritten file's previous contents are kept"
else
  fail "an overwrite destroyed the only copy of the old contents"
fi

# 7. trash retention actually removes old generations
mkdir -p "$WORK/target/_trash/2020-01-01"
touch -t 202001010000 "$WORK/target/_trash/2020-01-01"
TRASH_DAYS=30 run >/dev/null 2>&1
if [ ! -d "$WORK/target/_trash/2020-01-01" ]; then
  pass "trash older than the retention period is removed"
else
  fail "old trash was kept forever, which is how the disk fills"
fi

# 8. the report survives a failure, because debugging a backup by running it
#    again is a bad habit
rm -f "$WORK/target/.backup-target"
run >/dev/null 2>&1
if [ -s "$WORK/state/last-report" ] && grep -q "BACKUP FAILED" "$WORK/state/last-report"; then
  pass "the report is left on disk after a failure, with the reason in it"
else
  fail "the report did not survive the failure"
fi

# 9. a source that does not exist is a warning, not a silent skip and not a
#    reason to abandon the rest
touch "$WORK/target/.backup-target"
out="$(BACKUP_TARGET="$WORK/target" BACKUP_SOURCES="$WORK/src $WORK/nope" \
       BACKUP_STATE_DIR="$WORK/state" bash "$SCRIPT" 2>&1)"
if printf '%s' "$out" | grep -q "source $WORK/nope does not exist" && printf '%s' "$out" | grep -q "BACKUP OK"; then
  pass "a missing source warns loudly and the rest still runs"
else
  fail "a missing source was handled quietly or stopped everything"
fi

# 10. every source missing is a failure, not an empty success
out="$(BACKUP_TARGET="$WORK/target" BACKUP_SOURCES="$WORK/nope1 $WORK/nope2" \
       BACKUP_STATE_DIR="$WORK/state" bash "$SCRIPT" 2>&1)"; rc=$?
if [ $rc -ne 0 ]; then
  pass "nothing to copy is a failure, not a backup of nothing"
else
  fail "it reported success having copied nothing"
fi

# 11. An rsync that accepts --delete and --backup-dir and ignores them must
#     stop the run. This is not hypothetical: macOS ships openrsync, which does
#     exactly that, and every run against it would report success while
#     producing a copy with no versioning at all.
mkdir -p "$WORK/fakebin"
cat > "$WORK/fakebin/rsync" <<'FAKE'
#!/bin/sh
# accepts everything, honours only the copying
args=""
for a in "$@"; do
  case "$a" in --delete|--backup|--backup-dir=*|--human-readable|--stats|-a) ;; *) args="$args $a" ;; esac
done
# shellcheck disable=SC2086
exec /usr/bin/rsync -a $args
FAKE
chmod +x "$WORK/fakebin/rsync"
out="$(PATH="$WORK/fakebin:$PATH" BACKUP_TARGET="$WORK/target" BACKUP_SOURCES="$WORK/src"        BACKUP_STATE_DIR="$WORK/state" bash "$SCRIPT" 2>&1)"; rc=$?
if [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "does not honour them"; then
  pass "an rsync that ignores --delete and --backup-dir stops the run"
else
  fail "a crippled rsync was accepted, which would produce a mirror with no versions"
  printf '%s\n' "$out" | sed 's/^/        /' | tail -4
fi

echo
echo "passed: $PASSED   failed: $FAILED"
[ "$FAILED" -eq 0 ]
