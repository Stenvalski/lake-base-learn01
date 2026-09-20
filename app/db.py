"""Connection handling for Lakebase.

Deployed on Databricks Apps the password is an OAuth token minted for the
app's service principal; it expires hourly, so it is fetched per connection
and cached just under that. Locally, PGPASSWORD is used as-is.
"""
import os
import time
from contextlib import contextmanager

import psycopg
from psycopg.rows import dict_row

_TOKEN_TTL = 50 * 60  # refresh well before the 1 hour expiry
_cached: tuple[str, float] | None = None


def _password() -> str:
    """Local dev uses PGPASSWORD; on Apps, mint a token for the service principal."""
    local = os.environ.get("PGPASSWORD")
    if local:
        return local

    global _cached
    if _cached and time.monotonic() < _cached[1]:
        return _cached[0]

    from databricks.sdk import WorkspaceClient

    # LAKEBASE_ENDPOINT is injected by the postgres app resource, in the form
    # projects/{project}/branches/{branch}/endpoints/{endpoint}.
    endpoint = os.environ["LAKEBASE_ENDPOINT"]
    cred = WorkspaceClient().postgres.generate_database_credential(endpoint)
    _cached = (cred.token, time.monotonic() + _TOKEN_TTL)
    return cred.token


def _actor() -> str:
    """The signed-in end user.

    Databricks Apps forwards the caller's identity in request headers. Falling
    back to the service principal would make every change look identical, so
    an unknown caller is recorded as such rather than silently attributed.
    """
    try:
        from flask import has_request_context, request

        if has_request_context():
            for header in ("X-Forwarded-Email",
                           "X-Forwarded-Preferred-Username",
                           "X-Forwarded-User"):
                value = request.headers.get(header)
                if value:
                    return value
    except Exception:
        pass
    return os.environ.get("APP_ACTOR") or "unknown"


@contextmanager
def connect():
    with psycopg.connect(
        host=os.environ["PGHOST"],
        port=os.environ.get("PGPORT", "5432"),
        dbname=os.environ["PGDATABASE"],
        user=os.environ["PGUSER"],
        password=_password(),
        sslmode=os.environ.get("PGSSLMODE", "require"),
        row_factory=dict_row,
    ) as conn:
        # Read by the audit trigger; see migrations/V12__audit_trail.sql.
        conn.execute("SELECT set_config('app.user', %s, false)", (_actor(),))
        yield conn


def countries() -> list[dict]:
    with connect() as conn:
        return conn.execute("""
            SELECT c.id, c.country_alpha2, cv.country_name
            FROM country c
            JOIN country_version cv ON cv.country_id = c.id AND cv.current
            ORDER BY cv.country_name
        """).fetchall()


def requirements(country_id: int | None) -> list[dict]:
    sql = """
        SELECT r.id, cv.country_name, r.document_name, r.description, r.mandatory
        FROM residency_requirement r
        JOIN country c ON c.id = r.country_id
        JOIN country_version cv ON cv.country_id = c.id AND cv.current
        {where}
        ORDER BY cv.country_name, r.mandatory DESC, r.id
    """
    where = "WHERE r.country_id = %s" if country_id else ""
    with connect() as conn:
        return conn.execute(sql.format(where=where),
                            (country_id,) if country_id else ()).fetchall()


EDITABLE = {"document_name", "description", "mandatory"}


def update_field(row_id: int, field: str, value) -> None:
    if field not in EDITABLE:
        raise ValueError(f"column {field!r} is not editable")
    with connect() as conn:
        conn.execute(
            f"UPDATE residency_requirement SET {field} = %s WHERE id = %s",
            (value, row_id),
        )


def add(country_id: int) -> None:
    with connect() as conn:
        conn.execute(
            """INSERT INTO residency_requirement
               (country_id, document_name, description, mandatory)
               VALUES (%s, 'New document', '', false)""",
            (country_id,),
        )


def delete(row_ids: list[int]) -> None:
    if not row_ids:
        return
    with connect() as conn:
        conn.execute("DELETE FROM residency_requirement WHERE id = ANY(%s)", (row_ids,))
