# Redis-Fly

A Redis image for [Fly.io](https://fly.io). It generates `redis.conf` from
environment variables, persists data to a mounted volume, and can enable swap.

Built on Redis 8, so the query engine and the former Redis Stack modules are
available with no `loadmodule` needed:

- RediSearch / query engine: `FT.CREATE`, `FT.SEARCH`, `FT.AGGREGATE`, `FT._LIST`
- RedisJSON: `JSON.*`
- RedisTimeSeries: `TS.*`
- Bloom: `BF.*`, `CF.*`

`start_redis.sh` loads the bundled `*.so` modules itself, because it runs
`redis-server` directly rather than through the image's entrypoint (which is
what normally auto-loads them). The modules ship for amd64/arm64 only, which is
what Fly Machines run.

## Configurable Environment Variables

- `REDIS_PASSWORD` (required): auth password. The container won't start without it.
- `REDIS_PORT` (default `6379`): listen port.
- `REDIS_DATA_DIR` (default `/data`): where RDB/AOF files go. Point this at the mounted volume.
- `REDIS_MAXMEMORY` (default `768mb`): `maxmemory` limit. Keep it under the VM's RAM to leave room for the query engine and the BGSAVE/AOF-rewrite fork.
- `REDIS_MAXMEMORY_POLICY` (default `noeviction`): keep `noeviction` while using RediSearch, since eviction can drop keys an index points at and corrupt search results.
- `EXTRA_REDIS_CONFIG`: extra `redis.conf` lines, appended verbatim.
- `SWAP`: set to `1` to enable swap (also sets `vm.overcommit_memory=1` for safe `BGSAVE`).
- `SWAP_SIZE` (default `512M`): swap size when `SWAP=1`.

## Persistence

RDB snapshots and a multi-part AOF (`appendfsync everysec`) are both written
under `REDIS_DATA_DIR`, a mounted Fly volume. Fly volumes aren't replicated and
snapshots aren't backups, so ship your own backup (e.g. `BGSAVE` copied off-box)
if the data matters.

## Networking

Redis speaks raw TCP, not HTTP, so it isn't exposed on a public IP and `fly.toml`
has no service block. Reach it privately over 6PN at `redis-ayvu.internal:6379`.
Check `fly ips list` and release any public IP with `fly ips release <ip>`.

## Deploy

```sh
fly secrets set REDIS_PASSWORD=your-strong-password
fly deploy
```

Verify the modules loaded:

```sh
redis-cli -a "$REDIS_PASSWORD" MODULE LIST   # search, ReJSON, timeseries, bf
```
