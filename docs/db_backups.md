# Database backups

## Manual backup
```bash
./script/db_backup.sh            # default 14-day retention
./script/db_backup.sh 30        # keep 30 days
bin/rails db:backup             # same, via Rails task
bin/rails db:backup[30]
```
Backups are written to `~/backups/expense-tracker/` as encrypted pg_dump
custom-format files (`.dump.enc`). The directory is created with mode `700` and every
artifact with mode `600` (umask `077`). The destination is outside `~/Documents` so macOS
launchd can write it without Full Disk Access.

`bin/rails db:backup` only runs in `development`; set `ALLOW_DB_BACKUP=1` to override.

## Encryption key
Backups are encrypted with openssl (AES-256-CBC + PBKDF2). Create a key once, outside
the backup directory:
```bash
mkdir -p ~/.config/expense-tracker
openssl rand -base64 32 > ~/.config/expense-tracker/backup.key
chmod 600 ~/.config/expense-tracker/backup.key
```
Set `BACKUP_ENCRYPTION_KEY_FILE` to use another path. The script refuses to run when the
key is missing or readable by group/others. Keep a copy of the key somewhere safe: without
it the backups cannot be restored. Set `BACKUP_ENCRYPTION=none` only for a deliberate
unencrypted backup.

Note: macOS TCC blocks launchd from reading files inside `~/Documents`. Therefore the
launchd job runs a self-contained wrapper at `~/.local/bin/expense-tracker-backup.sh`
instead of `script/db_backup.sh`. The in-repo script remains available for manual use
(`./script/db_backup.sh` or `bin/rails db:backup`). The wrapper must also encrypt with the
same key.

## Restore
```bash
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 \
  -in ~/backups/expense-tracker/expense_tracker_development_YYYYMMDD_HHMMSS.dump.enc \
  -pass file:$HOME/.config/expense-tracker/backup.key |
  pg_restore --host=127.0.0.1 --port=5432 --username=$USER \
    --dbname=expense_tracker_development --clean --if-exists
```
For an unencrypted backup (`BACKUP_ENCRYPTION=none`), pass the `.dump` file directly to
`pg_restore`.

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
