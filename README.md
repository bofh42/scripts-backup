# scripts-backup
Scripts to make backups with borg and / or restic.

# Description
To do recuring backup with borg and / or restic is here a script to do that.

## Installation
* clone the repository
* follow [README.setup-borg](share/doc/README.setup-borg.md) or [README.setup-restic](share/doc/README.setup-restic.md)

## All targets in one cron job
`bin/backup-all.sh <type> [tool ...]` runs every configured target (`CFG_DEST_[1-9]=` in `etc/<tool>.conf`)
for one type (mandatory) and all tools or just the given ones (borg, restic).
hourly, daily, weekly, monthly use forget (keep rules), any other type like `pre-reinstall` is kept until you delete it.
`CFG_IGN_<id>` in `etc/<tool>.conf` ignores a target, comma separated: `backup-all` (backup-all.sh), `init-state` (init-state-files.sh),
`nagios` (the check skips its state file, set by the next backup run) or `all`. `<tool>backup.sh -<id>` still works.
Use [cron.example-all](share/doc/cron.example-all) instead of one cron line per target.
