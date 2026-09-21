"""Give the app's database role access to the data tables, and nothing else.

The role differs per environment -- on Databricks Apps it is the app's service
principal client id -- so it comes from the APP_ROLE environment variable.
"""
import os

from yoyo import step

__depends__ = {"0001_baseline"}

DATA_TABLES = ("country", "country_version", "residency_requirement")
SEQUENCES = ("country_id_seq", "country_version_id_seq",
             "residency_requirement_id_seq")
# The app must not be able to rewrite its own audit trail or the migration
# bookkeeping. The Flyway table only exists on databases migrated before the
# switch.
PROTECTED = ("audit_log", "_yoyo_migration", "_yoyo_log", "_yoyo_version",
             "yoyo_lock", "flyway_schema_history")


def apply(conn):
    from psycopg import sql

    role = sql.Identifier(os.environ["APP_ROLE"])
    cur = conn.cursor()
    cur.execute(sql.SQL("GRANT USAGE ON SCHEMA public TO {}").format(role))
    for table in DATA_TABLES:
        cur.execute(sql.SQL(
            "GRANT SELECT, INSERT, UPDATE, DELETE ON public.{} TO {}"
        ).format(sql.Identifier(table), role))
    for seq in SEQUENCES:
        cur.execute(sql.SQL("GRANT USAGE, SELECT ON SEQUENCE public.{} TO {}")
                    .format(sql.Identifier(seq), role))

    # Grants are explicit per table. Flyway's V10 had set default privileges
    # that handed the app every new table automatically; remove them so every
    # database behaves the same.
    cur.execute(sql.SQL(
        "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM {}"
    ).format(role))
    cur.execute(sql.SQL(
        "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM {}"
    ).format(role))

    for table in PROTECTED:
        cur.execute("SELECT to_regclass(%s)", (f"public.{table}",))
        if cur.fetchone()[0] is not None:
            cur.execute(sql.SQL("REVOKE ALL ON public.{} FROM {}")
                        .format(sql.Identifier(table), role))


steps = [step(apply)]
