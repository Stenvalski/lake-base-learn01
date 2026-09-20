-- V10's GRANT ON ALL TABLES swept in flyway_schema_history. The app has no
-- business reading or rewriting its own migration history.
REVOKE ALL ON public.flyway_schema_history
    FROM "30b6f312-afd6-4fe2-8f99-7323014dd570";
