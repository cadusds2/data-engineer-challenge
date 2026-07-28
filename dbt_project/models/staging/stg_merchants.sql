-- Current state of the merchant registry (CDC collapsed, SCD type 1).
with events as (
    select
        merchant_id,
        legal_name,
        trade_name,
        document,
        primary_cnae,
        cast(created_at as timestamp) as created_at,
        cast(updated_at as timestamp) as updated_at,
        "Op" as cdc_op,
        cast(_timestamp as timestamp) as cdc_timestamp
    from {{ source('settlement_db', 'enterprise_company') }}
),

latest as (
    select *,
        row_number() over (
            partition by merchant_id
            order by cdc_timestamp desc
        ) as rn
    from events
)

select
    merchant_id,
    legal_name,
    trade_name,
    document,
    primary_cnae,
    created_at,
    updated_at
from latest
where rn = 1 and cdc_op != 'D'
