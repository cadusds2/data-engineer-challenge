-- Historical reconciliation results as recorded by the operational service.
-- Kept as a cross-check signal for our own recalculation, not as the
-- primary source of the marts.
with results as (
    select
        id,
        run_id,
        transaction_id,
        merchant_id,
        category,
        cast(internal_amount as decimal(15, 2)) as internal_amount,
        cast(processor_amount as decimal(15, 2)) as processor_amount,
        cast(difference as decimal(15, 2)) as difference,
        cast(created_at as timestamp) as created_at,
        "Op" as cdc_op,
        cast(_timestamp as timestamp) as cdc_timestamp
    from {{ source('settlement_db', 'reconciliation_results') }}
),

latest as (
    select *,
        row_number() over (partition by id order by cdc_timestamp desc) as rn
    from results
)

select
    id,
    run_id,
    transaction_id,
    merchant_id,
    category,
    internal_amount,
    processor_amount,
    difference,
    created_at
from latest
where rn = 1 and cdc_op != 'D'
