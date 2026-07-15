#!/usr/bin/env sh
set -eu
umask 077

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEST="$ROOT/backups/$STAMP"
DB_SNAPSHOT="jianhu-backup-$STAMP.db"

mkdir -p "$DEST"
docker exec -e DB_SNAPSHOT="$DB_SNAPSHOT" jianhu-api node -e '
  const { DatabaseSync } = require("node:sqlite");
  const db = new DatabaseSync("/app/data/jianhu.db");
  const name = process.env.DB_SNAPSHOT;
  if (!/^jianhu-backup-[0-9TZ]+\.db$/.test(name)) process.exit(2);
  db.prepare("VACUUM INTO ?").run(`/app/data/${name}`);
  db.close();
'
mv "$ROOT/data/api/$DB_SNAPSHOT" "$DEST/jianhu.db"
chmod 600 "$DEST/jianhu.db"
tar -C "$ROOT/data/reader" -czf "$DEST/reader-storage.tar.gz" storage
find "$ROOT/backups" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf -- {} +
echo "$DEST"
