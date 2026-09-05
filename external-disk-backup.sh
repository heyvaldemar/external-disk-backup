#!/bin/bash
# external-disk-backup.sh — copy what matters to a removable disk, in a way
# that cannot quietly do the wrong thing.
#
# WHY THIS IS NOT JUST rsync IN A TIMER. Three things go wrong with that, and
# all three are silent:
#
#   1. THE DISK IS NOT THERE. If /mnt/backup is a mount point and nothing is
#      mounted on it, it is an ordinary empty directory on the root filesystem.
#      A plain rsync will cheerfully "back up" a hundred gigabytes onto the very
#      disk you are protecting against, fill it, and report success. So the
#      target must prove it is the target: a marker file that lives PHYSICALLY
#      on the removable disk. Its absence means the disk is not mounted, and
#      there is no other way for that file to be missing.
#
#   2. A MIRROR IS NOT A BACKUP. `--delete` protects you from a dead disk and
#      from nothing else. Delete a photo by accident and tomorrow it is gone
#      from the copy too. Here everything deleted or overwritten moves into
#      _trash/<date>/ and stays for a retention period. That is the difference
#      between a mirror and a backup.
#
#   3. NOBODY NOTICES IT STOPPED. A backup that silently stops running is the
#      worst failure in any of this: everything looks fine and you find out on
#      the day you need it, months later. This writes a run stamp and a success
#      stamp for a dead man's switch to threshold on, and the report is always
#      left on disk - including when the run fails, because debugging a backup
#      by running it again is a bad habit.
#
#   external-disk-backup.sh                 run it
#   external-disk-backup.sh --check         verify the target and the config, copy nothing
set -uo pipefail

CONF="${1:-}"
[ "$CONF" = "--check" ] && CHECK_ONLY=true || CHECK_ONLY=false

: "${BACKUP_TARGET:?set BACKUP_TARGET to the mounted path of the removable disk}"
: "${BACKUP_MARKER:=.backup-target}"
: "${BACKUP_SOURCES:?set BACKUP_SOURCES to a newline or space separated list of paths}"
TRASH_DAYS="${BACKUP_TRASH_DAYS:-30}"
STATE_DIR="${BACKUP_STATE_DIR:-/var/lib/external-disk-backup}"
REPORT="${BACKUP_REPORT:-$STATE_DIR/last-report}"
RSYNC_EXTRA="${BACKUP_RSYNC_EXTRA:-}"

mkdir -p "$STATE_DIR"
: > "$REPORT"
say() { printf '[%s] %s\n' "$(date -Iseconds)" "$*" | tee -a "$REPORT"; }
die() { say "BACKUP FAILED: $*"; exit 1; }

# The run stamp is written before any verdict: it answers "did this run at
# all", which is a different question from "did it work" and needs a different
# alarm. A watcher thresholding only on success cannot tell a backup that has
# been failing for a week from one that stopped being scheduled a month ago.
date +%s > "$STATE_DIR/last-run"

say "target $BACKUP_TARGET"

# --- can this rsync actually do what the whole design depends on? -------
#
# NOT a version string: a functional probe. macOS ships openrsync, which
# ACCEPTS --delete and --backup-dir and silently ignores them. Every run then
# looks like a success and produces a copy with no versioning at all — a
# mirror wearing a backup's clothes, which is precisely the failure this
# script exists to prevent. So prove the behaviour on two temporary files
# before touching anything real.
probe="$(mktemp -d)"
mkdir -p "$probe/s" "$probe/d" "$probe/t"
: > "$probe/s/gone"
rsync -a "$probe/s/" "$probe/d/" >/dev/null 2>&1
rm -f "$probe/s/gone"
rsync -a --delete --backup --backup-dir="$probe/t" "$probe/s/" "$probe/d/" >/dev/null 2>&1
if [ -e "$probe/d/gone" ] || [ ! -e "$probe/t/gone" ]; then
  rm -rf "$probe"
  die "this rsync accepts --delete and --backup-dir and does not honour them ($(rsync --version 2>/dev/null | head -1)). Everything below would report success and produce a copy with no versioning. Install GNU rsync."
fi
rm -rf "$probe"
say "rsync honours --delete and --backup-dir"


# --- the check that makes all the others meaningful ----------------------
[ -d "$BACKUP_TARGET" ] || die "$BACKUP_TARGET does not exist"
if [ ! -e "$BACKUP_TARGET/$BACKUP_MARKER" ]; then
  die "no $BACKUP_MARKER in $BACKUP_TARGET — the disk is not mounted. Refusing to copy onto the machine this is meant to protect. If the disk IS mounted and this is a first run, create the marker on it: touch $BACKUP_TARGET/$BACKUP_MARKER"
fi
say "marker found, the disk is mounted"

# Free space, as a fact rather than a surprise halfway through.
avail="$(df -Pk "$BACKUP_TARGET" | awk 'NR==2{print $4}')"
say "free on target: $(( avail / 1024 )) MiB"

sources=()
for s in $BACKUP_SOURCES; do
  if [ -e "$s" ]; then sources+=("$s"); else say "WARNING: source $s does not exist, skipping"; fi
done
[ "${#sources[@]}" -gt 0 ] || die "none of the configured sources exist"

if [ "$CHECK_ONLY" = true ]; then
  say "check only: target valid, ${#sources[@]} sources present, copying nothing"
  exit 0
fi

STAMP="$(date +%Y-%m-%d)"
TRASH="$BACKUP_TARGET/_trash/$STAMP"

failed=0
for src in "${sources[@]}"; do
  name="$(basename "$src")"
  dest="$BACKUP_TARGET/$name"
  # rsync creates only the LAST component of a destination path. Give it
  # a/b/c/ where only a exists and it says "No such file or directory" and
  # skips the source entirely — which on the first run here meant eight
  # volumes were quietly not copied.
  mkdir -p "$dest" "$TRASH/$name" || { say "cannot create $dest"; failed=1; continue; }
  say "copying $src"
  # --backup with --backup-dir instead of a bare --delete: everything removed
  # or replaced lands in the dated trash rather than disappearing.
  # shellcheck disable=SC2086
  if rsync -a --delete --backup --backup-dir="$TRASH/$name" \
        --human-readable --stats $RSYNC_EXTRA "$src/" "$dest/" >>"$REPORT" 2>&1; then
    say "  ok: $name"
  else
    rc=$?
    # 24 is "some files vanished before they could be transferred", which is
    # normal on a live system and does not mean the copy is bad.
    if [ "$rc" -eq 24 ]; then
      say "  ok: $name (some files changed while being read)"
    else
      say "  FAILED: $name (rsync exit $rc)"; failed=1
    fi
  fi
done

# Retention on the trash. Without this the thing that makes it a backup is also
# the thing that fills the disk.
if [ "$TRASH_DAYS" -ge 1 ] && [ -d "$BACKUP_TARGET/_trash" ]; then
  find "$BACKUP_TARGET/_trash" -maxdepth 1 -mindepth 1 -type d -mtime "+$TRASH_DAYS" -exec rm -rf {} + 2>/dev/null
  say "trash older than ${TRASH_DAYS}d removed; $(du -sh "$BACKUP_TARGET/_trash" 2>/dev/null | cut -f1) kept"
fi

[ "$failed" -eq 0 ] || die "one or more sources failed — see $REPORT"

say "BACKUP OK: ${#sources[@]} sources to $BACKUP_TARGET"
date +%s > "$STATE_DIR/last-ok"
