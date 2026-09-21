-- Baseline for NEW databases: the schema and reference data as they stood
-- after V12, in one file.
--
-- Flyway runs this only on an empty database, then skips V1-V12 and continues
-- with V13. On learn01, which already ran V1-V12, Flyway ignores this file.
--
-- Built from pg_dump of learn01 on 2026-09-21, with these changes:
--   * btree_gist added -- a public-schema dump omits extensions, and the
--     country_version no-overlap constraint needs it
--   * Databricks' own event-trigger functions removed -- Lakebase installs
--     them itself, and they fail on any other database
--   * psql-only commands and session settings removed
--   * audit_log starts empty, with its id sequence at 1
--   * grants use the ${app_role} placeholder instead of one app's role
--
-- residency_requirement rows are FABRICATED sample data, carried over from V5.

CREATE EXTENSION IF NOT EXISTS btree_gist;

--
-- PostgreSQL database dump
--

-- Dumped from database version 17.11 (8a81ecb)
-- Dumped by pg_dump version 17.11 (Homebrew)

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';

--
-- Name: log_audit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_audit() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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

--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id bigint NOT NULL,
    table_name text NOT NULL,
    row_id integer NOT NULL,
    operation text NOT NULL,
    column_name text NOT NULL,
    old_value text,
    new_value text,
    changed_at timestamp with time zone DEFAULT now() NOT NULL,
    changed_by text NOT NULL,
    reason text,
    CONSTRAINT audit_log_operation_check CHECK ((operation = ANY (ARRAY['INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);

--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: country; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.country (
    id integer NOT NULL,
    country_alpha2 character(2) NOT NULL
);

--
-- Name: country_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.country ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.country_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: country_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.country_version (
    id integer NOT NULL,
    country_name text NOT NULL,
    active_from timestamp without time zone NOT NULL,
    active_to timestamp without time zone,
    current boolean NOT NULL,
    country_id integer NOT NULL
);

--
-- Name: country_version_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.country_version ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.country_version_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Name: residency_requirement; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.residency_requirement (
    id integer NOT NULL,
    country_id integer NOT NULL,
    document_name text NOT NULL,
    description text,
    mandatory boolean NOT NULL
);

--
-- Name: residency_requirement_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.residency_requirement ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.residency_requirement_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

--
-- Data for Name: country; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.country (id, country_alpha2) OVERRIDING SYSTEM VALUE VALUES (1, 'FI');
INSERT INTO public.country (id, country_alpha2) OVERRIDING SYSTEM VALUE VALUES (2, 'SE');
INSERT INTO public.country (id, country_alpha2) OVERRIDING SYSTEM VALUE VALUES (3, 'DK');

--
-- Data for Name: country_version; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.country_version (id, country_name, active_from, active_to, current, country_id) OVERRIDING SYSTEM VALUE VALUES (1, 'Denmark	', '2026-09-20 21:08:03.030014', NULL, true, 3);
INSERT INTO public.country_version (id, country_name, active_from, active_to, current, country_id) OVERRIDING SYSTEM VALUE VALUES (3, 'Finland', '2026-09-20 21:09:57.521833', NULL, true, 1);
INSERT INTO public.country_version (id, country_name, active_from, active_to, current, country_id) OVERRIDING SYSTEM VALUE VALUES (5, 'Sweden', '2026-09-20 21:10:40.276268', NULL, true, 2);
INSERT INTO public.country_version (id, country_name, active_from, active_to, current, country_id) OVERRIDING SYSTEM VALUE VALUES (2, 'Sverige', '2026-09-20 21:09:57.523604', '2026-09-20 21:10:40.276268', false, 2);

--
-- Data for Name: residency_requirement; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (1, 3, 'Valid passport', 'Machine-readable passport valid at least 6 months beyond application date.', true);
INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (2, 3, 'Residence permit history', 'Documentation of 8 years continuous lawful residence.', true);
INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (4, 3, 'Employment record', 'Full-time employment for at least 3 years 6 months of the last 4 years.', true);
INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (5, 3, 'Proof of self-support', 'Statement that no public assistance was received in the last 4 years.', true);
INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (8, 1, 'Residence permit history', 'Four years continuous residence on an A permit.', true);
INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (10, 1, 'Criminal record extract', 'Extract issued within the last 3 months.', true);
INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (12, 2, 'Valid passport', 'Passport valid for the full permit period.', true);
INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (13, 2, 'Residence permit history', 'Four years of residence permits within the last seven years.', true);
INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (14, 2, 'Proof of employment', 'Employment contract or business accounts showing self-support.', true);
INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (15, 2, 'Housing contract', 'Rental or ownership documentation for suitable accommodation.', true);
INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (16, 2, 'Criminal record check', 'Extract from Polismyndigheten.', false);
INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (3, 3, 'Danish language certificate', 'Proof of passing Prøve i Dansk 2 or higher.', true);
INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (6, 3, 'Active citizenship proof', 'Evidence of civic participation, e.g. association or volunteer work for at least 2 years.', false);
INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (11, 1, 'Language certificate', 'YKI level 3 in Finnish or Swedish. Speeds up processing.', false);
INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (7, 1, 'Valid passport', 'Passport or other accepted travel document. Must have at least 6 month validity before it expires.', true);
INSERT INTO public.residency_requirement (id, country_id, document_name, description, mandatory) OVERRIDING SYSTEM VALUE VALUES (9, 1, 'Proof of income', 'Payslips or tax records covering the qualifying period, or minimum 3 years.', true);

--
-- Name: audit_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

--
-- Name: country_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.country_id_seq', 3, true);

--
-- Name: country_version_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.country_version_id_seq', 11, true);

--
-- Name: residency_requirement_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.residency_requirement_id_seq', 17, true);

--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);

--
-- Name: country country_country_alpha2_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.country
    ADD CONSTRAINT country_country_alpha2_key UNIQUE (country_alpha2);

--
-- Name: country country_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.country
    ADD CONSTRAINT country_pkey PRIMARY KEY (id);

--
-- Name: country_version country_version_no_overlap; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.country_version
    ADD CONSTRAINT country_version_no_overlap EXCLUDE USING gist (country_id WITH =, tsrange(active_from, COALESCE(active_to, 'infinity'::timestamp without time zone), '[)'::text) WITH &&);

--
-- Name: country_version country_version_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.country_version
    ADD CONSTRAINT country_version_pkey PRIMARY KEY (id);

--
-- Name: residency_requirement residency_requirement_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.residency_requirement
    ADD CONSTRAINT residency_requirement_pkey PRIMARY KEY (id);

--
-- Name: audit_log_row_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_row_idx ON public.audit_log USING btree (table_name, row_id, changed_at);

--
-- Name: country_version_country_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX country_version_country_idx ON public.country_version USING btree (country_id);

--
-- Name: residency_requirement_country_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX residency_requirement_country_idx ON public.residency_requirement USING btree (country_id);

--
-- Name: residency_requirement residency_requirement_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER residency_requirement_audit AFTER INSERT OR DELETE OR UPDATE ON public.residency_requirement FOR EACH ROW EXECUTE FUNCTION public.log_audit();

--
-- Name: country_version country_version_country_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.country_version
    ADD CONSTRAINT country_version_country_id_fkey FOREIGN KEY (country_id) REFERENCES public.country(id);

--
-- Name: residency_requirement residency_requirement_country_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.residency_requirement
    ADD CONSTRAINT residency_requirement_country_id_fkey FOREIGN KEY (country_id) REFERENCES public.country(id);

--
-- PostgreSQL database dump complete
--

-- The app's database role differs per environment; set it with
-- flyway.placeholders.app_role. Grants are per table, so audit_log and
-- flyway_schema_history stay out of the app's reach (see V11, V12).
GRANT USAGE ON SCHEMA public TO "${app_role}";
GRANT SELECT, INSERT, UPDATE, DELETE
    ON public.country, public.country_version, public.residency_requirement
    TO "${app_role}";
GRANT USAGE, SELECT
    ON SEQUENCE public.country_id_seq, public.country_version_id_seq,
                public.residency_requirement_id_seq
    TO "${app_role}";
