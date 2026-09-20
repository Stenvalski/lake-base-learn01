-- Documents required for a permanent residence application, per country.
CREATE TABLE public.residency_requirement (
    id           integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    country_id   integer NOT NULL REFERENCES public.country (id),
    document_name text NOT NULL,
    description  text,
    mandatory    boolean NOT NULL
);

CREATE INDEX residency_requirement_country_idx
    ON public.residency_requirement (country_id);
