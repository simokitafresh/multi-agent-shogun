# cmd_4411 オフサイト退避・隔離復元runbook

- 実施日: 2026-08-29 JST
- tool: `scripts/shogun_backup.py`
- Drive folder: `shogun-offsite-backups` (`1EOqd51NF4ZplAJrJrhhLQWXoPGCnumgI`)
- 暗号鍵: repo外の `/home/simokitafresh/.config/shogun/backup.key`（mode 600）。鍵はDriveへ送らない。

## 定期退避

```bash
python3 scripts/shogun_backup.py --backup \
  --root /home/simokitafresh/multi-agent-shogun \
  --dm-root /mnt/c/Python_app/DM-signal \
  --key-file /home/simokitafresh/.config/shogun/backup.key \
  --drive-folder shogun-offsite-backups
```

退避はmemory DBのSQLite online backup→gzip、`projects`/`queue`のtar.gz、
`logs/gate_metrics.log`のgzip、DM-signalの全`.env*` tarをAES-256-CBC(PBKDF2)で暗号化し、
artifactごとにDriveへuploadする。完了前にDrive一覧を期待集合と比較し、全artifactを再downloadして
sha256を突合する。queue内の実体化可能なsymlinkは内容を取り込み、danglingな旧repoリンクはリンク情報を保持する。

実測初回: backup id `shogun-20260829T083134Z`、artifact 5件+manifest 1件、env 19件、
Drive一覧6件、sha256一致5/5。

## 隔離復元

```bash
work="$(mktemp -d /tmp/shogun-restore.XXXXXX)"
git clone <github-repository> "$work/repo"
bash "$work/repo/first_setup.sh" --dry-run
python3 "$work/repo/scripts/shogun_backup.py" \
  --restore shogun-20260829T083134Z \
  --root /home/simokitafresh/multi-agent-shogun \
  --dm-root /mnt/c/Python_app/DM-signal \
  --key-file /home/simokitafresh/.config/shogun/backup.key \
  --drive-folder shogun-offsite-backups \
  --destination "$work/repo" \
  --dm-destination "$work/repo/dm-signal" \
  --temp-dir "$work"
```

実走結果: clone HEAD `422988ba134a052bae09be9586febe78ec82bb1a`、
first_setup dry-run match 2、Drive再取得sha256 5/5、復元DB `integrity_check=ok`、
projects 104→104、queue 145,556件、DM-signal env復元。

## cron

```bash
python3 scripts/shogun_backup.py --install-cron \
  --root /home/simokitafresh/multi-agent-shogun \
  --dm-root /mnt/c/Python_app/DM-signal \
  --key-file /home/simokitafresh/.config/shogun/backup.key \
  --drive-folder shogun-offsite-backups
```

登録結果: `0 3 * * *`、`/usr/bin/flock -n /tmp/shogun-drive-backup.lock`付き、marker
`# shogun-drive-backup`。既存cron 2行を保持し、marker再登録時は重複しない。

## 確認済みtest

`bash scripts/run_tests.sh file tests/unit/test_first_setup.bats`
は2/2 PASS、FAIL 0、SKIP 0（receipt `logs/test_receipts/run_tests_20260829T084802_476732.json`）。

