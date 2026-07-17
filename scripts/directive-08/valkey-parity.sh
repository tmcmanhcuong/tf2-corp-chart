#!/usr/bin/env sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <source-uri> <target-uri>" >&2
  exit 2
fi

inventory() {
  uri="$1"
  label="$2"
  echo "[$label] dbsize=$(redis-cli -u "$uri" --no-auth-warning DBSIZE)"
  redis-cli -u "$uri" --no-auth-warning --scan | LC_ALL=C sort | while IFS= read -r key; do
    type=$(redis-cli -u "$uri" --no-auth-warning TYPE "$key")
    ttl_ms=$(redis-cli -u "$uri" --no-auth-warning PTTL "$key")
    if [ "$ttl_ms" -lt 0 ]; then ttl=persistent; else ttl=expiring; fi
    dump=$(redis-cli -u "$uri" --no-auth-warning --raw DUMP "$key" | sha256sum | awk '{print $1}')
    printf '%s\t%s\t%s\t%s\n' "$key" "$type" "$ttl" "$dump"
  done
}

inventory "$1" source > valkey-source-parity.txt
inventory "$2" target > valkey-target-parity.txt
diff -u valkey-source-parity.txt valkey-target-parity.txt
