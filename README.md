# External disk backup

[![Tests](https://github.com/heyvaldemar/external-disk-backup/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/external-disk-backup/actions/workflows/tests.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Copy what matters to a removable disk, in a way that cannot quietly do the wrong thing.

## A copy nobody compared is a hypothesis

`--verify` walks the same `BACKUP_SOURCES` the copy walks and asks rsync what differs. The comparison is not the interesting part; classifying what it finds is.

"Missing from the copy" is two different facts. A file older than the last successful backup and absent from the disk is a file the backup **missed**, which is the whole reason to look. A file newer than it simply arrived since, and reporting it is noise. On the machine these rules come from, the first version treated every absence as explained, and the 221-line report it produced turned out to be a race between the 12:00 copy and the 13:00 check — every one of those files was on the disk and identical.

**Without the cutoff, nothing is evidence.** If no successful backup has been recorded, differences are listed and none of them is called a finding, because there is no time to judge them against. The origin machine had this inverted: one missing stamp and a continuously-written log would have been reported as disk corruption.

At the boundary it errs towards silence. The stamp has one-second resolution, so a file written in the same second the backup finished could be either; counted as new, a genuinely missed file is excused for one run and caught by the next, when the cutoff has moved past it.

```bash
external-disk-backup.sh --verify    # compares, copies nothing, moves no stamp
```

The default compare is size and mtime, the same question the copy itself asks. `BACKUP_VERIFY_CHECKSUM=1` reads every byte on both sides instead — on the machine this comes from that is 1.3 TB and four hours, and a verification nobody can afford to run is a verification that does not run.

## The three ways rsync in a timer goes wrong, all of them silently

**The disk is not there.** An unmounted mount point is an ordinary empty directory on the root filesystem. A plain rsync will happily write a hundred gigabytes into it, filling the disk it was protecting you against, and report success. So the target has to prove it is the target: a marker file that lives physically on the removable disk. There is no other way for that file to be missing, so its absence means one thing.

**A mirror is not a backup.** `--delete` protects you from a dead disk and from nothing else. Delete a photo by accident and tomorrow it is gone from the copy too. Here everything deleted or overwritten moves into `_trash/<date>/` and stays for a retention period.

**Nobody notices it stopped.** A backup that silently stops running is the worst failure in this whole area: everything looks fine, and you find out months later on the day you need it. This writes a run stamp and a success stamp for a dead man's switch to threshold on, and the report is always left on disk — including when the run fails, because debugging a backup by running it again is a bad habit.

## And a fourth, which is why it checks its own tools

macOS ships `openrsync`, which **accepts** `--delete` and `--backup-dir` and silently ignores them. Every run reports success and produces a mirror with no versioning: a backup wearing the right clothes and doing none of the work.

So before touching anything real, the script proves the behaviour on two temporary files — delete one, run the flags, check it landed in the backup directory — and refuses to continue if it did not. Not a version string: what the binary actually does.

## Install

```bash
sudo install -m 755 external-disk-backup.sh /usr/local/sbin/external-disk-backup.sh
sudo install -m 644 external-disk-backup@.service external-disk-backup@.timer /etc/systemd/system/
sudo mkdir -p /etc/external-disk-backup
sudo cp external-disk-backup.env.example /etc/external-disk-backup/home.env
sudo chmod 600 /etc/external-disk-backup/home.env
sudo $EDITOR /etc/external-disk-backup/home.env
```

Create the marker on the disk, once, by hand. Doing it by hand is the point: a script that creates its own marker cannot tell a mounted disk from an empty directory.

```bash
touch /mnt/backup/.backup-target
sudo external-disk-backup.sh --check     # validates the target, copies nothing
sudo systemctl enable --now external-disk-backup@home.timer
```

## Watch it, or it will stop without telling you

The two stamps are there to be read. `last-run` moves on every execution, before any verdict; `last-ok` only after a clean one. Point a dead man's switch at both, with a threshold that tolerates one missed run:

```
stamp	the backup ran	/var/lib/external-disk-backup/last-run 2160
stamp	the backup worked	/var/lib/external-disk-backup/last-ok 2880
```

Those two lines are the format used by [deadman-switch](https://github.com/heyvaldemar/deadman-switch), which is where the thresholds belong: it reports over a channel that does not depend on this machine being alive.

## What this does not do

It does not verify the copy can be read back — that is a separate job and a separate schedule; compare checksums monthly rather than trusting size and mtime, because an rsync that skips a file whose size and mtime match is blind to a byte that rotted on the target.

It does not encrypt. A removable disk that leaves the building needs encryption at rest, and that belongs to the filesystem, not to a copying script.

It does not manage the disk. Mounting, `nofail` in fstab, and the SMART health of the target are the host's business.

## Testing

`tests/e2e-external-disk-backup.sh` runs twelve scenarios, and the ones that matter are the refusals: an unmounted target is declined with nothing written to it, a deleted file is still recoverable from the trash afterwards, an overwritten file keeps its previous contents, a run with every source missing fails rather than reporting a backup of nothing, and an rsync that ignores the flags it was given stops the run.

That last one is exercised with a deliberately crippled `rsync` on the `PATH`, because a probe that has only ever seen a working binary is not known to work.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
