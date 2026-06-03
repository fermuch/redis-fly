#!/bin/sh

SWAP_SIZE=${SWAP_SIZE:-512M}

if [ "$SWAP" = "1" ]; then
  echo "Setting up swap space..."
  fallocate -l ${SWAP_SIZE} /swapfile
  chmod 0600 /swapfile
  mkswap /swapfile
  echo 10 > /proc/sys/vm/swappiness
  swapon /swapfile
  echo 1 > /proc/sys/vm/overcommit_memory
fi

if [ -z "$REDIS_PASSWORD" ]; then
  echo "ERROR: REDIS_PASSWORD is not set. Refusing to start a network-bound Redis without a password." >&2
  exit 1
fi

mkdir -p /etc/redis/

REDIS_CONF="/etc/redis/redis.conf"
REDIS_PORT=${REDIS_PORT:-6379}
REDIS_DATA_DIR=${REDIS_DATA_DIR:-/data}
REDIS_MAXMEMORY=${REDIS_MAXMEMORY:-768mb}
REDIS_MAXMEMORY_POLICY=${REDIS_MAXMEMORY_POLICY:-noeviction}

mkdir -p "$REDIS_DATA_DIR"

## NETWORK & AUTH
echo "" > $REDIS_CONF
echo "bind * -::*" >> $REDIS_CONF
echo "port $REDIS_PORT" >> $REDIS_CONF
echo "requirepass $REDIS_PASSWORD" >> $REDIS_CONF
echo "timeout 0" >> $REDIS_CONF
echo "tcp-keepalive 300" >> $REDIS_CONF

## DATA DIRECTORY (mounted Fly volume)
echo "dir $REDIS_DATA_DIR" >> $REDIS_CONF

## RDB SNAPSHOTS
# save every 15 min if ≥1 write
echo "save 900 1" >> $REDIS_CONF
# save every 5 min if ≥10 writes
echo "save 300 10" >> $REDIS_CONF
# save every 1 min if ≥10000 writes
echo "save 60 10000" >> $REDIS_CONF
echo "dbfilename dump.rdb" >> $REDIS_CONF

## APPEND ONLY FILE
echo "appendonly yes" >> $REDIS_CONF
echo "appendfilename appendonly.aof" >> $REDIS_CONF
echo "appendfsync everysec" >> $REDIS_CONF
echo "auto-aof-rewrite-percentage 100" >> $REDIS_CONF
echo "auto-aof-rewrite-min-size 64mb" >> $REDIS_CONF
echo "aof-load-truncated yes" >> $REDIS_CONF

## MEMORY LIMITS
# noeviction is required while RediSearch indexes exist: evicting a key that an
# FT index points at corrupts that index's results. Keep maxmemory below the
# VM's RAM so the query engine and the BGSAVE/AOF-rewrite fork have headroom.
echo "maxmemory $REDIS_MAXMEMORY" >> $REDIS_CONF
echo "maxmemory-policy $REDIS_MAXMEMORY_POLICY" >> $REDIS_CONF

## EXTRA CONFIG
echo "$EXTRA_REDIS_CONFIG" >> $REDIS_CONF

## MODULES (RediSearch / RedisJSON / RedisTimeSeries / Bloom)
# Redis 8 bundles these as .so files, but only the official image's
# docker-entrypoint.sh auto-loads them — and we launch redis-server directly,
# so glob the modules dir and load each one ourselves.
set --
REDIS_MODULES_DIR="/usr/local/lib/redis/modules"
if [ -d "$REDIS_MODULES_DIR" ]; then
  for module in "$REDIS_MODULES_DIR"/*.so; do
    [ -e "$module" ] || continue
    set -- "$@" --loadmodule "$module"
  done
fi

exec redis-server "$REDIS_CONF" "$@"
