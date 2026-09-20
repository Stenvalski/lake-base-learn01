# Lakebase DDL deployment — learn01

Project `learn01` / branch `production` / database `databricks_postgres`
(AWS us-east-2, Postgres 17, 1 CU, scale-to-zero).

## Layout

    flyway.conf   connection + locations (no password)
    fw            wrapper: injects clipboard token as -password
    migrations/
      V1__baseline_country.sql                   pg_dump of public.country, applied as BASELINE
      V2__country_alpha2_current_unique.sql      partial unique index on alpha2 (superseded by V3)
      V3__drop_country_alpha2_current_unique.sql drops it again
      V4__residency_requirement.sql              residency_requirement table
      V5__seed_residency_requirement.sql         sample rows for DK/FI/SE (fabricated)
      V6__split_country_identity_and_version.sql country -> country + country_version
      V7__repoint_residency_requirement.sql      FK moved to the identity table
      V8__drop_country_version_alpha2.sql        alpha2 now lives only on country

## Auth

The Postgres password is a Databricks OAuth token that **expires after 1 hour**.
Get a fresh one from the workspace: Lakebase Postgres -> learn01 -> Connect ->
"Copy OAuth token", then run commands through `./fw`, which reads the clipboard:

    ./fw info
    ./fw migrate

Never put the token in flyway.conf. For CI, replace `pbpaste` in `fw` with a
Databricks CLI token fetch.

## State

At V8 as of 2026-09-20. `./fw info` is the source of truth.

`public.country` predates Flyway, so V1 is recorded as Ignored (Baseline) and
is never executed; the table it describes already exists. V2 and V3 ran for
real.

V2 added a partial unique index on `country_alpha2` for current rows. That was
wrong -- an alpha2 code may legitimately appear on more than one current row --
so V3 drops it. V2 was left in place rather than edited: Flyway checksums
applied migrations, and changing one breaks `validate` on every database that
already ran it. Retract by rolling forward.

V4 adds `residency_requirement`, keyed to `country(id)`. V5 seeds it with
16 invented rows -- placeholder data for testing joins, NOT real immigration
requirements.

V6-V8 split the original `country` table, which was doing two jobs at once:
identifying a country and storing the history of its attributes. That made it
impossible to say what a requirement attached to -- an FK to a row id pinned
it to one version, and alpha2 could not be an FK target without a uniqueness
rule that history forbids.

Net schema:

    country          id PK, country_alpha2 UNIQUE       -- stable identity
    country_version  id PK, country_id FK, country_name,
                     active_from, active_to, current    -- SCD-2 history
    residency_requirement
                     id PK, country_id FK -> country(id), document_name,
                     description, mandatory

A rename is now a new `country_version` row; `residency_requirement` is
untouched by it because it points at the identity.

## Adding a change

Drop a new file in migrations/ named V9__<description>.sql, then:

    ./fw info      # confirm it shows Pending
    ./fw migrate

## Gotchas

- Percent-encode the `@` in the username as `%40` inside libpq URIs.
  Flyway takes it as a plain `flyway.user`, so no encoding needed there.
- pg_dump must be 17+; the Homebrew default `pg_dump` is 15 and will refuse.
  Use /opt/homebrew/opt/postgresql@17/bin/pg_dump.
- First connect after idle may be slow; connectRetries=3 covers the cold start.
- `country.current` has no default, so every INSERT must set it explicitly.
- `country.id` is GENERATED ALWAYS AS IDENTITY -- INSERTs must omit it, and
  gaps in the sequence are normal.
- Never edit an applied migration; add a new version that reverses it.
- Query current names through `country_version` with `WHERE current`; the
  identity table carries no name.
- A partial unique index cannot be a foreign key target in Postgres
  ("no unique constraint matching given keys"). This is why alpha2 had to move
  to its own table rather than gaining a `WHERE current` index.
- Renaming a table in a migration does not rename its identity sequence or its
  constraints; V6 renames both explicitly to avoid colliding with the new
  `country`.
- `country_version` rows for SE overlap by ~0.3s (active_to is later than the
  next row's active_from). Not fixed. An EXCLUDE constraint would prevent the
  class of bug, but needs btree_gist and a data fix first.
