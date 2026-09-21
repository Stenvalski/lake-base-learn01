# Lakebase DDL deployment — learn01

A learning project: schema-as-code for a Databricks Lakebase (Postgres 17)
database using Flyway, plus a Dash + AG Grid app, deployed on Databricks Apps,
for viewing and editing residency requirements. The sample data is
fabricated -- not real immigration requirements.

- [INSTALL.md](INSTALL.md) -- building the whole stack from scratch, including
  every error hit along the way and its fix.
- [docs/gxp-validation-strategy.md](docs/gxp-validation-strategy.md) -- what it
  would take to validate the app for regulated (GxP) use.

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
      V9__country_version_no_overlap.sql         EXCLUDE constraint on version intervals
      V10__grant_app_service_principal.sql       table grants for the Databricks App
      V11__revoke_app_access_to_schema_history.sql keeps the app out of flyway's history
      V12__audit_trail.sql                       audit_log + trigger, with end-user attribution
      B12__baseline.sql                          everything above in one file, for NEW databases

## Auth

The Postgres password is a Databricks OAuth token that **expires after 1 hour**.
`./fw` mints one automatically via the Databricks CLI (profile `learn01`), and
falls back to the clipboard -- Lakebase Postgres -> learn01 -> Connect ->
"Copy OAuth token" -- if no profile is configured:

    ./fw info
    ./fw migrate

Never put the token in flyway.conf.

`run-local.sh` still uses the clipboard; the app itself mints its own token
when deployed.

## State

At V12 as of 2026-09-21. `./fw info` is the source of truth.

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

V9 makes overlapping version intervals impossible: an EXCLUDE constraint over
`(country_id =, tsrange(active_from, active_to) &&)`, using half-open ranges so
a clean handover (one row's active_to equal to the next's active_from) is
allowed while any real overlap is rejected. An open-ended row is treated as
running to 'infinity'.

## Build a new database

Run Flyway against an empty database. It runs `B12__baseline.sql` only, skips
V1-V12, then runs anything from V13 on:

    flyway -url=jdbc:postgresql://<host>/<db> -user=<user> -password=<token> \
           -locations=filesystem:migrations -placeholders.app_role=<app role> migrate

`app_role` is the Postgres role of the app that will use this database -- the
bare service principal client id on Databricks Apps. For learn01 it is set in
`flyway.conf`.

Why a baseline: replaying V1-V12 on an empty database fails. V5 needs country
rows that were typed in by hand before Flyway was used, and V10-V12 name
learn01's app role, which exists nowhere else. On learn01, Flyway lists the
baseline as `Ignored`, because that database already has its history.

Verified 2026-09-21: an empty Postgres 17 database built from the baseline has
a schema identical to learn01 (compared with `pg_dump --schema-only`), the same
row counts, an empty audit log, and a working audit trigger.

## Audit trail

Every INSERT, UPDATE and DELETE on `residency_requirement` writes one
`audit_log` row per changed column, recording old value, new value, timestamp
and who made the change. The trigger cannot be bypassed: a direct `psql`
update is logged too, attributed to `session_user`.

Attribution comes from the `app.user` session setting, which `db.py` sets per
connection from the identity Databricks Apps forwards. Locally, set
`APP_ACTOR`; if neither is present the change records as `unknown` rather than
being silently attributed to the service principal.

`log_audit()` is SECURITY DEFINER, so the app writes audit rows through the
trigger while holding no privileges on `audit_log` itself.

Not yet covered: `country` and `country_version` have no audit trigger
(migrations are the only writer today), there is no reason-for-change captured
from the UI, and the table owner can still modify `audit_log` directly.

## Adding a change

Drop a new file in migrations/ named V13__<description>.sql, then:

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
- Refer to the app's role as `"${app_role}"` in new migrations, never by its
  literal name. V10-V12 hard-code learn01's role, which is why they cannot run
  anywhere else.
- `GRANT ... ON ALL TABLES` also catches `flyway_schema_history`. Revoke it
  afterwards (V11) or grant table by table.
- Query current names through `country_version` with `WHERE current`; the
  identity table carries no name.
- A partial unique index cannot be a foreign key target in Postgres
  ("no unique constraint matching given keys"). This is why alpha2 had to move
  to its own table rather than gaining a `WHERE current` index.
- Renaming a table in a migration does not rename its identity sequence or its
  constraints; V6 renames both explicitly to avoid colliding with the new
  `country`.
- Closing out a version and opening the next must set active_to equal to the
  new row's active_from. Anything else is rejected by V9's EXCLUDE constraint.
- V9 enables the btree_gist extension, needed to mix `=` on an integer with
  `&&` on a range in one EXCLUDE constraint.

## The app

`app/` is a Dash app using AG Grid (Community edition) to view and edit
`residency_requirement`. Edits save on cell change; rows can be added and
deleted. Deployed on Databricks Apps it authenticates as the app's service
principal; locally it uses a clipboard token, like Flyway.

### Run it locally

One-time setup -- Dash does not work on Python 3.14 (`pkgutil.find_loader` was
removed), so pin 3.12:

    uv venv -p 3.12 .venv
    VIRTUAL_ENV=.venv uv pip install -r app/requirements.txt

Then, each session:

1. Workspace -> Lakebase Postgres -> learn01 -> Connect -> "Copy OAuth token".
2. `./run-local.sh`
3. Open http://localhost:8050

`run-local.sh` reads connection settings from `.env.local` and takes the
password from the clipboard, so no token is written to disk. The token lasts
an hour; when it expires the app reports a connection error and you re-copy.

`.env.local` and `.venv/` are gitignored.

### Deploying to Databricks Apps

`app/app.yaml` declares the Lakebase endpoint as a resource. On deploy,
Databricks creates a service principal for the app, grants it a Postgres role,
and injects PGHOST/PGPORT/PGDATABASE/PGSSLMODE. `app/db.py` then mints a fresh
OAuth token per connection via the SDK
(`WorkspaceClient().database.generate_database_credential`), cached for 50
minutes, so nothing on the clipboard is involved.

Free Edition allows up to 3 apps, and an app stops automatically 24 hours
after being started or redeployed; restart it from the workspace.
