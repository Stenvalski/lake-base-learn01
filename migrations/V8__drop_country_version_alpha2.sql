-- alpha2 now lives on the identity table; keeping a copy per version row
-- would let the two disagree.
ALTER TABLE public.country_version DROP COLUMN country_alpha2;
