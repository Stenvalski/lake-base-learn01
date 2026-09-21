-- Two versions of the same country must not be current at overlapping times.
-- Existing SE rows overlap by ~0.3s, so close the gap before constraining.

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Each closed interval ends exactly where the next one begins.
WITH nxt AS (
    SELECT id,
           lead(active_from) OVER (PARTITION BY country_id ORDER BY active_from) AS next_from
    FROM public.country_version
)
UPDATE public.country_version cv
SET active_to = nxt.next_from
FROM nxt
WHERE cv.id = nxt.id
  AND nxt.next_from IS NOT NULL
  AND cv.active_to IS DISTINCT FROM nxt.next_from;

-- Half-open [from, to): touching intervals do not count as overlapping.
ALTER TABLE public.country_version
    ADD CONSTRAINT country_version_no_overlap
    EXCLUDE USING gist (
        country_id WITH =,
        tsrange(active_from, coalesce(active_to, 'infinity'::timestamp), '[)') WITH &&
    );
