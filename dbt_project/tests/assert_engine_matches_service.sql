-- Cross-check (warn only): our recalculated category vs what the
-- operational service recorded. Divergence is EXPECTED on the sample
-- fixture (the CSV is synthetic and does not correspond to the stored
-- historical results); in production this becomes a bug detector for
-- either side.
{{ config(severity='warn') }}

select transaction_id, engine_category, service_category
from {{ ref('mart_compliance') }}
where categories_diverge
