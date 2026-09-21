-- Databricks gives a Databricks App's service principal a Postgres role with
-- CONNECT and CREATE, but no rights on tables someone else owns. Without
-- these grants the app connects successfully and then fails every query with
-- "permission denied for table ...".
--
-- The Postgres role is the service principal's bare client id. Note this is
-- NOT the Lakebase role_id ('dbrx-apps-<client-id>'); use status.postgres_role
-- from:
--   databricks postgres list-roles projects/learn01/branches/production
-- This migration is therefore specific to the 'residency-requirements' app in
-- this workspace.

GRANT USAGE ON SCHEMA public
    TO "30b6f312-afd6-4fe2-8f99-7323014dd570";

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public
    TO "30b6f312-afd6-4fe2-8f99-7323014dd570";

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public
    TO "30b6f312-afd6-4fe2-8f99-7323014dd570";

-- Tables added by later migrations should be reachable too.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
    TO "30b6f312-afd6-4fe2-8f99-7323014dd570";

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES
    TO "30b6f312-afd6-4fe2-8f99-7323014dd570";
