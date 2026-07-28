-- Current view of each merchant (SCD type 1 — see README for the trade-off).
-- Includes the classic "unknown member": the generator plants internal rows
-- with null merchant_id (~0.01%), and aggregations must not drop them.
select
    'UNKNOWN' as merchant_id,
    'Unknown merchant' as legal_name,
    'Unknown merchant' as trade_name,
    cast(null as varchar) as document,
    cast(null as varchar) as primary_cnae,
    cast(null as timestamp) as created_at,
    cast(null as timestamp) as updated_at

union all

select
    merchant_id,
    legal_name,
    trade_name,
    document,
    primary_cnae,
    created_at,
    updated_at
from {{ ref('stg_merchants') }}
