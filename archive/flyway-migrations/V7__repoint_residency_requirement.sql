-- residency_requirement.country_id still points at country_version rows
-- (the FK followed the rename in V6). Repoint it at the identity table so
-- requirements survive a rename.

ALTER TABLE public.residency_requirement
    DROP CONSTRAINT residency_requirement_country_id_fkey;

UPDATE public.residency_requirement r
SET country_id = c.id
FROM public.country_version cv
JOIN public.country c ON c.country_alpha2 = cv.country_alpha2
WHERE cv.id = r.country_id;

ALTER TABLE public.residency_requirement
    ADD CONSTRAINT residency_requirement_country_id_fkey
    FOREIGN KEY (country_id) REFERENCES public.country (id);
