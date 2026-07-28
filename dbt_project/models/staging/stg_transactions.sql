-- Current state of internal transactions: collapse CDC events keeping the
-- latest version per transaction_id, drop deletes.
with events as (
    select
        id,
        transaction_id,
        merchant_id,
        cast(amount as decimal(15, 2)) as amount,
        upper(currency) as currency,
        status,
        description,
        payment_method,
        cast(created_at as timestamp) as created_at,
        cast(updated_at as timestamp) as updated_at,
        "Op" as cdc_op,
        cast(_timestamp as timestamp) as cdc_timestamp
    from {{ source('settlement_db', 'transactions') }}
),

latest as (
    select *,
        row_number() over (
            partition by transaction_id
            order by cdc_timestamp desc
        ) as rn
    from events
)

select
    id,
    transaction_id,
    merchant_id,
    amount,
    currency,
    status,
    description,
    payment_method,
    created_at,
    updated_at
from latest
where rn = 1 and cdc_op != 'D'
