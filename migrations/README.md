# Lakebase DDL deployment — learn01

Project `learn01` / branch `production` / database `databricks_postgres`
(AWS us-east-2, Postgres 17, 1 CU, scale-to-zero).

## Layout

    flyway.conf                      connection + locations (no password)
    fw                               wrapper: injects clipboard token as -password
    migrations/V1__baseline_country.sql   pg_dump of public.country, applied as BASELINE

## Auth

The Postgres password is a Databricks OAuth token that **expires after 1 hour**.
Get a fresh one from the workspace: Lakebase Postgres -> learn01 -> Connect ->
"Copy OAuth token", then run commands through `./fw`, which reads the clipboard:

    ./fw info
    ./fw migrate

Never put the token in flyway.conf. For CI, replace `pbpaste` in `fw` with a
Databricks CLI token fetch.

## State

Baselined at V1 on 2026-09-20. `public.country` predates Flyway, so V1 is
recorded as Ignored (Baseline) and is never executed. V2+ will run normally.

## Adding a change

Drop a new file in migrations/ named V2__<description>.sql, then:

    ./fw info      # confirm it shows Pending
    ./fw migrate

## Gotchas

- Percent-encode the `@` in the username as `%40` inside libpq URIs.
  Flyway takes it as a plain `flyway.user`, so no encoding needed there.
- pg_dump must be 17+; the Homebrew default `pg_dump` is 15 and will refuse.
  Use /opt/homebrew/opt/postgresql@17/bin/pg_dump.
- First connect after idle may be slow; connectRetries=3 covers the cold start.
- `country.current` has no default, so every INSERT must set it explicitly.
