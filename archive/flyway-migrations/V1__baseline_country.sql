-- Baseline: public.country
-- Source: pg_dump --schema-only against learn01/production, 2026-09-20.

CREATE TABLE public.country (
    id             integer NOT NULL,
    country_name   text NOT NULL,
    country_alpha2 character(2) NOT NULL,
    active_from    timestamp without time zone NOT NULL,
    active_to      timestamp without time zone,
    current        boolean NOT NULL
);

ALTER TABLE public.country ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.country_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

ALTER TABLE ONLY public.country
    ADD CONSTRAINT country_pkey PRIMARY KEY (id);
