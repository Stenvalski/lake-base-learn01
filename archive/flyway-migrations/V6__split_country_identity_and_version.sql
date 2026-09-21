-- Split country into a stable identity and its versioned attributes.
-- The existing table becomes the version table; a new identity table is
-- created above it, keyed on country_alpha2.

ALTER TABLE public.country RENAME TO country_version;
ALTER TABLE public.country_version RENAME CONSTRAINT country_pkey TO country_version_pkey;
-- the identity sequence keeps its old name and would collide with the new table
ALTER SEQUENCE public.country_id_seq RENAME TO country_version_id_seq;

CREATE TABLE public.country (
    id             integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    country_alpha2 character(2) NOT NULL UNIQUE
);

INSERT INTO public.country (country_alpha2)
SELECT DISTINCT country_alpha2 FROM public.country_version;

ALTER TABLE public.country_version
    ADD COLUMN country_id integer REFERENCES public.country (id);

UPDATE public.country_version cv
SET country_id = c.id
FROM public.country c
WHERE c.country_alpha2 = cv.country_alpha2;

ALTER TABLE public.country_version ALTER COLUMN country_id SET NOT NULL;

CREATE INDEX country_version_country_idx
    ON public.country_version (country_id);
