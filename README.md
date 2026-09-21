# Lakebase DDL deployment — learn01

A learning project: schema-as-code for a Databricks Lakebase (Postgres 17)
database using yoyo-migrations, plus a Dash + AG Grid app, deployed on
Databricks Apps, for viewing and editing residency requirements. The sample
data is fabricated -- not real immigration requirements.

- [INSTALL.md](INSTALL.md) -- building the whole stack from scratch, including
  every error hit along the way and its fix.
- [docs/gxp-validation-strategy.md](docs/gxp-validation-strategy.md) -- what it
  would take to validate the app for regulated (GxP) use.

Project `learn01` / branch `production` / database `databricks_postgres`
(AWS us-east-2, Postgres 17, 1 CU, scale-to-zero).

## Layout

    yoyo.ini               connection + migration folder (no password)
    migrate                wrapper: mints a token, sets APP_ROLE, runs yoyo
    requirements-dev.txt   yoyo-migrations + psycopg, for the wrapper
    migrations/
      0001_baseline.sql    schema + reference data, the starting point for every database
      0002_app_grants.py   the app's table grants; role comes from APP_ROLE
    archive/flyway-migrations/
      V1..V12, B12         the Flyway history this project started with

## Auth

The Postgres password is a Databricks OAuth token that **expires after 1 hour**.
`./migrate` mints one through the Databricks CLI (profile `learn01`) and hands
it to psycopg through `PGPASSWORD`, so it never appears in `yoyo.ini`, in the
database URL, or on disk:

    ./migrate list
    ./migrate apply

`run-local.sh` still uses the clipboard; the deployed app mints its own token.

## State

Both migrations applied on learn01 as of 2026-09-21. `./migrate list` is the
source of truth.

On learn01, `0001_baseline` is **marked** applied rather than run, because the
database already had that schema from Flyway. `0002_app_grants` ran for real:
its grants were already in place, and it also removed the default privileges
Flyway's V10 had set, which handed the app every new table automatically.
Grants are now explicit, per table, on every database.

Net schema:

    country          id PK, country_alpha2 UNIQUE       -- stable identity
    country_version  id PK, country_id FK, country_name,
                     active_from, active_to, current    -- SCD-2 history
    residency_requirement
                     id PK, country_id FK -> country(id), document_name,
                     description, mandatory
    audit_log        one row per changed column, written by a trigger

A rename is a new `country_version` row; `residency_requirement` is untouched
by it because it points at the identity. An EXCLUDE constraint makes
overlapping version intervals impossible, using half-open ranges so a clean
handover (one row's active_to equal to the next's active_from) is allowed.

## Build a new database

Point yoyo at an empty database and set the app's role:

    APP_ROLE=<app role> PGPASSWORD=<token> .venv/bin/yoyo apply --batch \
        --no-config-file --database "postgresql+psycopg://<user>@<host>/<db>" migrations

`APP_ROLE` is the Postgres role of the app that will use the database -- the
bare service principal client id on Databricks Apps.

Verified 2026-09-21 on an empty Postgres 17 database: schema identical to
learn01 (compared with `pg_dump --schema-only`), the same row counts, an empty
audit log, a working audit trigger, and the app role holding rights on the
three data tables only.

## Adding a change

Create the next migration in `migrations/` -- `0003_<description>.sql`, or
`.py` when it needs the app role or other logic -- then:

    ./migrate list     # confirm it shows U (unapplied)
    ./migrate apply

yoyo orders migrations by `__depends__` (Python) or `-- depends:` (SQL), then
by file name. Give each new migration a dependency on the previous one.

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

## History

The project began on Flyway. Its twelve migrations are kept in
`archive/flyway-migrations/`, and `flyway_schema_history` remains in learn01 as
the record of what ran. The notable decisions in that history:

- **V2/V3.** V2 added a unique index on `country_alpha2` for current rows. That
  was wrong -- an alpha2 code may legitimately appear on more than one current
  row -- so V3 removed it, rolling forward rather than editing V2.
- **V6-V8.** The original `country` table did two jobs: identifying a country
  and storing the history of its attributes. That made it impossible to say
  what a requirement attached to, so it was split into `country` and
  `country_version`.
- **B12.** Replaying V1-V12 on an empty database failed: V5 needed country rows
  typed in by hand before Flyway was used, and V10-V12 named learn01's app
  role, which exists nowhere else. The B12 baseline fixed that and became
  `0001_baseline.sql`.

## Gotchas

- **yoyo does not detect edits to applied migrations.** It identifies a
  migration by its file name, not its contents, so changing an applied file
  goes unnoticed. Never edit one; add a new migration that reverses it.
- Percent-encode the `@` in the username as `%40` in database URLs, and as
  `%%40` in `yoyo.ini`, which reads `%` as a configparser escape.
- pg_dump must be 17+; the Homebrew default `pg_dump` is 15 and will refuse.
  Use /opt/homebrew/opt/postgresql@17/bin/pg_dump.
- `country.current` has no default, so every INSERT must set it explicitly.
- `country.id` is GENERATED ALWAYS AS IDENTITY -- INSERTs must omit it, and
  gaps in the sequence are normal.
- Grant table by table, never `ON ALL TABLES`: that also catches `audit_log`
  and the migration bookkeeping tables.
- Query current names through `country_version` with `WHERE current`; the
  identity table carries no name.
- A partial unique index cannot be a foreign key target in Postgres
  ("no unique constraint matching given keys"). This is why alpha2 had to move
  to its own table rather than gaining a `WHERE current` index.
- Closing out a version and opening the next must set active_to equal to the
  new row's active_from. Anything else is rejected by the EXCLUDE constraint,
  which needs the btree_gist extension.

## The app

`app/` is a Dash app using AG Grid (Community edition) to view and edit
`residency_requirement`. Edits save on cell change; rows can be added and
deleted. Deployed on Databricks Apps it authenticates as the app's service
principal; locally it uses a clipboard token.

### Run it locally

One-time setup -- Dash does not work on Python 3.14 (`pkgutil.find_loader` was
removed), so pin 3.12:

    uv venv -p 3.12 .venv
    VIRTUAL_ENV=.venv uv pip install -r app/requirements.txt -r requirements-dev.txt

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
(`WorkspaceClient().postgres.generate_database_credential`), cached for 50
minutes, so nothing on the clipboard is involved.

Free Edition allows up to 3 apps, and stops an app automatically 24 hours
after it was started or redeployed. The stop also clears the deployment, so
bring it back with both commands:

    databricks apps start residency-requirements -p learn01
    databricks apps deploy residency-requirements \
      --source-code-path /Workspace/Users/<you>/residency-requirements -p learn01
