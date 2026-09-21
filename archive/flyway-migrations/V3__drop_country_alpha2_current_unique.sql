-- Reverses V2. An alpha2 code may legitimately appear on more than one
-- current row, so uniqueness is not enforced at the schema level.
DROP INDEX IF EXISTS public.country_alpha2_current_uq;
