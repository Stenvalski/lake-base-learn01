# Setting this up from scratch

A step-by-step record of building this project against Databricks Lakebase
(Free Edition, AWS us-east-2), including everything that went wrong and the
fix for each. Written so it can be repeated by hand.

Workspace: https://dbc-2c193fdb-ac47.cloud.databricks.com
Project: `learn01` / branch `production` / database `databricks_postgres`

---

## 1. Create the Lakebase project

Workspace -> top-right app-grid icon -> **Lakebase Postgres** -> **New project**.
Free Edition allows **one Lakebase project per account**, with scale-to-zero
compute. Postgres 17, 1 CU.

Take connection details from **Connect** on the project dashboard:

    host     ep-<generated>.database.us-east-2.cloud.databricks.com
    database databricks_postgres
    user     <your email>
    sslmode  require

The password is an **OAuth token that expires after one hour**. That single
fact shapes everything below.

### Gotcha: the username contains `@`

Inside a libpq connection URI the `@` must be percent-encoded or the parser
reads the host wrong:

    postgresql://me%40example.com@host/db?sslmode=require

Flyway takes the user as a separate config key, so no encoding there.

---

## 2. Postgres client tools

    brew install postgresql@17

### Error: pg_dump version mismatch

    pg_dump: error: server version: 17.x; pg_dump version: 15.x
    pg_dump: error: aborting because of server version mismatch

Homebrew's default `pg_dump` was 15 and refuses to dump a newer server.
`psql` 15 connects fine, so only the dump is affected. Fix: use the versioned
binary explicitly.

    /opt/homebrew/opt/postgresql@17/bin/pg_dump --version

### Keeping the token out of files

The token is on the clipboard after clicking "Copy OAuth token", so pass it
via command substitution and it never lands on disk or in shell history:

    PGPASSWORD="$(pbpaste)" psql "postgresql://..."

Failure mode to expect: if you copy something else in between,

    ERROR: Provided authentication token is not a valid JWT encoding

That means the clipboard changed, not that anything is broken. Re-copy.

---

## 3. Flyway

    brew install flyway

Config in `flyway.conf` (no password), token injected by the `fw` wrapper:

    flyway.url=jdbc:postgresql://<host>/databricks_postgres?sslmode=require
    flyway.user=<your email>
    flyway.locations=filesystem:migrations
    flyway.schemas=public
    flyway.baselineVersion=1
    flyway.connectRetries=3

`connectRetries` matters because scale-to-zero compute needs a moment to wake.

### Adopting a table that already exists

`flyway migrate` would run `V1__baseline_country.sql` and fail, because the
table is already there. Use **baseline** instead:

    ./fw baseline

V1 is then recorded as `Ignored (Baseline)` and never executed; V2 onward run
normally. Get V1's content from the live database rather than writing it by
hand -- a reconstruction from the UI missed the identity column, a default,
and the real constraint names:

    pg_dump --schema-only --no-owner --no-privileges -t public.country "<uri>"

### Never edit an applied migration

Flyway checksums each applied migration. Editing or deleting one breaks
`validate` on every database that already ran it. Retract by rolling forward:
add a new version that reverses the old one.

---

## 4. Schema lessons

### A partial unique index cannot be a foreign key target

    CREATE UNIQUE INDEX ... ON country (country_alpha2) WHERE current;
    CREATE TABLE child (alpha2 char(2) REFERENCES country (country_alpha2));
    -- ERROR: there is no unique constraint matching given keys
    --        for referenced table "country"

A foreign key needs a full unique constraint or index. This is what forced the
identity/version split: `alpha2` had to become unique somewhere it legitimately
could be.

### Splitting identity from history

The original `country` did two jobs -- identifying a country and storing the
history of its attributes. Those want different keys. Result:

    country          id PK, country_alpha2 UNIQUE      -- stable identity
    country_version  id PK, country_id FK, country_name,
                     active_from, active_to, current   -- SCD-2 history

Child tables point at `country.id`, so a rename never orphans them.

Two things that bite during the rename:

- Renaming a table does **not** rename its identity sequence or its
  constraints. `country_id_seq` still existed and collided with the new
  `country` table's own identity. Rename it explicitly.
- A foreign key follows the renamed table. After `ALTER TABLE country RENAME
  TO country_version`, the child FK pointed at `country_version`. Repointing
  it is a separate migration.

### Non-overlapping history

    CREATE EXTENSION IF NOT EXISTS btree_gist;
    ALTER TABLE country_version ADD CONSTRAINT country_version_no_overlap
      EXCLUDE USING gist (
        country_id WITH =,
        tsrange(active_from, coalesce(active_to,'infinity'::timestamp), '[)') WITH &&
      );

`btree_gist` is required to mix `=` on an integer with `&&` on a range in one
constraint. Use **half-open** ranges `[)` so a clean handover (one row's
active_to equal to the next's active_from) is legal while real overlaps are
rejected. Fix existing overlaps *before* adding the constraint or it fails.

---

## 5. The Dash + AG Grid app

    uv venv -p 3.12 .venv
    VIRTUAL_ENV=.venv uv pip install -r app/requirements.txt

### Error: Dash does not run on Python 3.14

    AttributeError: module 'pkgutil' has no attribute 'find_loader'

`pkgutil.find_loader` was removed in 3.14 and Dash's dev tools still call it.
Pin the venv to 3.12, which also matches the Databricks Apps runtime.

### AG Grid licensing

`dash-ag-grid` ships AG Grid **Community** (MIT): editing, sorting, filtering,
selection. Row grouping, pivoting, Excel export and master/detail are
Enterprise and need a paid licence.

### Testing an editable grid

A synthetic `Return` keypress does **not** commit AG Grid's cell editor under
browser automation. The cell shows the new text while the editor is still
open, `cellValueChanged` never fires, and the save silently does not happen --
it looks like an app bug and is not. Click another cell to commit. Pressing
Enter by hand in a real browser works normally.

---

## 6. Databricks CLI

    brew tap databricks/tap
    brew install databricks

### Error: untrusted tap

    Error: Refusing to load formula databricks/tap/databricks from untrusted
    tap databricks/tap.

Fix (a trust decision for whoever owns the machine):

    brew trust databricks/tap

Then:

    databricks auth login --host https://<workspace> --profile learn01

---

## 7. Two different Lakebase APIs

This is the biggest trap. There are two generations of Lakebase:

- **Database Instances** -- `databricks database ...`, identified by an
  instance name.
- **Autoscaling Projects** -- `databricks postgres ...`, identified by
  hierarchical resource paths.

`learn01` is a **project**, so `databricks database list-database-instances`
returns an empty list and `WorkspaceClient().database.generate_database_
credential(instance_names=[...])` is the wrong call. The right one is:

    WorkspaceClient().postgres.generate_database_credential(endpoint)

where endpoint is `projects/{project}/branches/{branch}/endpoints/{endpoint}`.

### Finding the real resource names

Do not guess them from the browser URL -- the URL contains internal ids
(`br-broad-surf-...`) that the API rejects:

    Error: branch id not found

List them instead:

    databricks postgres list-projects -p learn01
    databricks postgres list-branches projects/learn01 -p learn01
    databricks postgres list-endpoints projects/learn01/branches/production -p learn01
    databricks postgres list-databases projects/learn01/branches/production -p learn01

For this project the real values are:

    project   learn01
    branch    production          (not the br-... id in the URL)
    endpoint  primary
    database  databricks-postgres (hyphens!)

Verify credential minting works before deploying anything:

    databricks postgres generate-database-credential \
      projects/learn01/branches/production/endpoints/primary -p learn01

---

## 8. Creating the app

Resources can only be set via `--json`. Three errors, in order:

**Wrong resource type.** Using `"database": {"instance_name": "learn01"}`:

    Error: Failed to add resource postgres.
           Database instance learn01 does not exist.

Projects need the `postgres` resource type, not `database`. The SDK's
`AppResource` dataclass lists the valid keys (`app`, `database`, `postgres`,
`secret`, `sql_warehouse`, ...) -- worth introspecting when docs are thin.

**Short database name.**

    Error: INVALID_PARAMETER_VALUE: Field 'name' expects
           'projects/{project_id}/branches/{branch_id}/databases/{database_id}'
           format, got 'databricks_postgres'

**Underscores vs hyphens.** The fully-qualified name still failed:

    Error: Database projects/.../databases/databricks_postgres does not exist
           in postgres branch projects/learn01/branches/production

The *resource id* is `databricks-postgres` (hyphens) while the *Postgres
database* is `databricks_postgres` (underscores). `list-databases` shows both:
`database_id` vs `status.postgres_database`.

Working payload:

    {
      "name": "residency-requirements",
      "resources": [{
        "name": "postgres",
        "postgres": {
          "branch": "projects/learn01/branches/production",
          "database": "projects/learn01/branches/production/databases/databricks-postgres",
          "permission": "CAN_CONNECT_AND_CREATE"
        }
      }]
    }

    databricks apps create --json @app-create.json --no-compute -p learn01

### Harmless error from --no-compute

    Error: failed to reach ACTIVE, got STOPPED: Start the app compute to deploy

The app **was** created; the CLI just waits for ACTIVE even when you asked for
no compute. Confirm with `databricks apps get residency-requirements`.

---

## 9. Deploying

    databricks workspace import-dir app "/Users/<you>/residency-requirements" \
      --overwrite -p learn01
    databricks apps start residency-requirements -p learn01      # ~2 minutes
    databricks apps deploy residency-requirements \
      --source-code-path "/Workspace/Users/<you>/residency-requirements" -p learn01

`import-dir` uploads **everything**, including `.DS_Store` and `__pycache__`.
Delete them afterwards or keep the source directory clean.

`app.yaml` binds the resource to an environment variable:

    command: ["gunicorn", "app:server", "--bind", "0.0.0.0:8000", "--workers", "2"]
    env:
      - name: LAKEBASE_ENDPOINT
        valueFrom: postgres      # "postgres" = the resource name in apps create

Databricks injects `PGHOST`, `PGPORT`, `PGDATABASE`, `PGSSLMODE` and
`PGUSER`, creates a service principal for the app, and grants it a Postgres
role. The app mints its own token per connection -- no clipboard involved.

### First open requires consent

The first visit shows "Permission Requested -- this app is requesting
permission to act on your behalf". Click **Authorize**. Until then the app
URL only shows the consent screen.

### Free Edition limits

Up to 3 apps per account. An app stops automatically **24 hours** after being
started or redeployed; restart it from the workspace or with
`databricks apps start`.

---

## 10. Useful commands

    ./fw info                          # migration state
    ./fw migrate                       # apply pending migrations
    ./run-local.sh                     # run the app locally (token on clipboard)
    databricks apps logs residency-requirements --tail-lines 100 -p learn01
    databricks apps get residency-requirements -p learn01
