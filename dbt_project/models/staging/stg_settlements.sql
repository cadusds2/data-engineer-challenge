-- PaySettler daily file: normalize amounts that arrive either as plain
-- numbers (2616.01) or Brazilian-formatted strings (R$ 18.319,17).
with raw as (
    select
        transaction_id,
        merchant_id,
        amount as raw_amount,
        upper(currency) as currency,
        settled_at,
        processor_reference,
        status
    from {{ source('paysettler', 'settlement_file') }}
)

select
    transaction_id,
    merchant_id,
    case
        when raw_amount like 'R$%' then cast(
            replace(replace(replace(raw_amount, 'R$', ''), '.', ''), ',', '.')
            as decimal(15, 2)
        )
        else cast(raw_amount as decimal(15, 2))
    end as amount,
    currency,
    cast(settled_at as timestamp) as settled_at,
    cast(settled_at as date) as reference_date,
    processor_reference,
    status
from raw
