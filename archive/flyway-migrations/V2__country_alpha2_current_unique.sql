-- Only one row per country may be the current version.
-- Partial: superseded rows (current = false) keep their alpha2 for history.
CREATE UNIQUE INDEX country_alpha2_current_uq
    ON public.country (country_alpha2)
    WHERE current;
