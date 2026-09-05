# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.0.0] - 2026-09-05

### Added

- **A marker file that has to live on the removable disk.** An unmounted mount
  point is an ordinary empty directory, and a backup written there fills the
  disk it was meant to protect while reporting success. The run refuses without
  the marker, and says how to create it.
- **Versioned trash instead of a bare `--delete`.** Everything deleted or
  overwritten moves to `_trash/<date>/` and stays for a retention period. That
  is the difference between a mirror and a backup.
- **A functional probe of rsync itself.** macOS ships openrsync, which accepts
  `--delete` and `--backup-dir` and silently ignores them, so every run would
  report success and produce a copy with no versioning. The script proves the
  behaviour on two temporary files and refuses to continue if the flags are not
  honoured. Not a version string: what the binary actually does.
- **Two stamps and a report that survives failure.** `last-run` is written
  before any verdict, `last-ok` only after a clean one, so a watcher can tell a
  backup that keeps failing from one that stopped being scheduled. The report is
  always left on disk, because debugging a backup by running it again is a bad
  habit.
- **Parent directories created before the copy starts.** rsync creates only the
  last component of a destination path and skips the source entirely otherwise,
  with one line of explanation — which is how eight volumes were quietly not
  copied on a first run.
- **Twelve end-to-end scenarios**, most of them refusals, including one run
  against a deliberately crippled `rsync` so the probe is known to fire.

[Unreleased]: https://github.com/heyvaldemar/external-disk-backup/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/external-disk-backup/releases/tag/v1.0.0
