# Database backups

## Manual backup
```bash
./script/db_backup.sh            # default 14-day retention
./script/db_backup.sh 30        # keep 30 days
bin/rails db:backup             # same, via Rails task
bin/rails db:backup[30]
```
Backups are written to `~/backups/expense-tracker/` as pg_dump custom-format (`.dump`) files
(outside `~/Documents` so macOS launchd can write them without Full Disk Access).

Note: macOS TCC blocks launchd from reading files inside `~/Documents`. Therefore the
launchd job runs a self-contained wrapper at `~/.local/bin/expense-tracker-backup.sh`
instead of `script/db_backup.sh`. The in-repo script remains available for manual use
(`./script/db_backup.sh` or `bin/rails db:backup`).

## Restore
```bash
pg_restore --host=127.0.0.1 --port=5432 --username=$USER \
  --dbname=expense_tracker_development --clean --if-exists \
  db/backups/expense_tracker_development_YYYYMMDD_HHMMSS.dump
```

## Daily automatic backup (macOS)

Option A — cron (simplest):
```bash
crontab -e
# add:
0 2 * * * /Users/joseuribe/Documents/Development/ai-code/expense-tracker/script/db_backup.sh >> /Users/joseuribe/Documents/Development/ai-code/expense-tracker/log/db_backup.log 2>&1
```

Option B — launchd (recommended on macOS, survives sleep): create
`~/Library/LaunchAgents/com.expense-tracker.db-backup.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.expense-tracker.db-backup</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/joseuribe/Documents/Development/ai-code/expense-tracker/script/db_backup.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>2</integer>
    <key>Minute</key><integer>0</integer>
  </dict>
  <key>StandardOutPath</key><string>/Users/joseuribe/Documents/Development/ai-code/expense-tracker/log/db_backup.log</string>
  <key>StandardErrorPath</key><string>/Users/joseuribe/Documents/Development/ai-code/expense-tracker/log/db_backup.log</string>
</dict>
</plist>
```
Then load it:
```bash
launchctl load ~/Library/LaunchAgents/com.expense-tracker.db-backup.plist
```
