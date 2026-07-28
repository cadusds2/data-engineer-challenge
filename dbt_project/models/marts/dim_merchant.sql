-- Current view of each merchant (SCD type 1 — see README for the trade-off).
select
    merchant_id,
    legal_name,
    trade_name,
    document,
    primary_cnae,
    created_at,
    updated_at
from {{ ref('stg_merchants') }}
