-- Column-level audit trail with end-user attribution.
--
-- The trigger, not the application, writes the audit record: a trigger cannot
-- be bypassed by psql, another client, or a future second application.
--
-- Attribution comes from the session setting 'app.user', which the application
-- sets per connection from the identity Databricks Apps forwards for the
-- signed-in user. Without it the row falls back to session_user, which on
-- Databricks Apps is the service principal -- visibly unattributed rather than
-- silently wrong.

CREATE TABLE public.audit_log (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name  text        NOT NULL,
    row_id      integer     NOT NULL,
    operation   text        NOT NULL
                CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
    column_name text        NOT NULL,
    old_value   text,
    new_value   text,
    changed_at  timestamptz NOT NULL DEFAULT now(),
    changed_by  text        NOT NULL,
    reason      text
);

CREATE INDEX audit_log_row_idx
    ON public.audit_log (table_name, row_id, changed_at);

CREATE FUNCTION public.log_audit() RETURNS trigger
    LANGUAGE plpgsql
    SECURITY DEFINER            -- so the app needs no rights on audit_log
    SET search_path = public, pg_temp
AS $$
DECLARE
    actor text := coalesce(nullif(current_setting('app.user', true), ''),
                           session_user);
    why   text := nullif(current_setting('app.reason', true), '');
    k     text;
    v_old text;
    v_new text;
    old_j jsonb;
    new_j jsonb;
BEGIN
    IF TG_OP = 'INSERT' THEN
        new_j := to_jsonb(NEW);
        FOR k, v_new IN SELECT key, value FROM jsonb_each_text(new_j) LOOP
            INSERT INTO public.audit_log (table_name, row_id, operation,
                        column_name, old_value, new_value, changed_by, reason)
            VALUES (TG_TABLE_NAME, NEW.id, 'INSERT', k, NULL, v_new, actor, why);
        END LOOP;
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        old_j := to_jsonb(OLD);
        FOR k, v_old IN SELECT key, value FROM jsonb_each_text(old_j) LOOP
            INSERT INTO public.audit_log (table_name, row_id, operation,
                        column_name, old_value, new_value, changed_by, reason)
            VALUES (TG_TABLE_NAME, OLD.id, 'DELETE', k, v_old, NULL, actor, why);
        END LOOP;
        RETURN OLD;

    ELSE
        old_j := to_jsonb(OLD);
        new_j := to_jsonb(NEW);
        FOR k IN SELECT jsonb_object_keys(new_j) LOOP
            v_old := old_j ->> k;
            v_new := new_j ->> k;
            IF v_old IS DISTINCT FROM v_new THEN
                INSERT INTO public.audit_log (table_name, row_id, operation,
                            column_name, old_value, new_value, changed_by, reason)
                VALUES (TG_TABLE_NAME, NEW.id, 'UPDATE', k, v_old, v_new, actor, why);
            END IF;
        END LOOP;
        RETURN NEW;
    END IF;
END;
$$;

CREATE TRIGGER residency_requirement_audit
    AFTER INSERT OR UPDATE OR DELETE ON public.residency_requirement
    FOR EACH ROW EXECUTE FUNCTION public.log_audit();

-- V10's ALTER DEFAULT PRIVILEGES would otherwise hand the app full rights on
-- this new table. The trigger runs as the function owner, so the app needs
-- none -- and must not be able to rewrite its own audit trail.
REVOKE ALL ON public.audit_log FROM "30b6f312-afd6-4fe2-8f99-7323014dd570";
