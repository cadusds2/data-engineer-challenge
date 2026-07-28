-- REVERSED rows from the PaySettler file: refunds are not settlements, so
-- they are excluded from the main match and classified separately.
--   LINKED  -> the reversed transaction exists internally
--   ORPHAN  -> reversal of a transaction we have no record of (anomaly)

{% set ref_date = "cast('" ~ var('reference_date') ~ "' as date)" %}

select
    {{ ref_date }} as reference_date,
    s.transaction_id,
    s.merchant_id,
    s.amount as reversed_amount,
    s.settled_at,
    s.processor_reference,
    case when t.transaction_id is not null then 'LINKED' else 'ORPHAN' end
        as reversal_status,
    t.status as internal_status
from {{ ref('stg_settlements') }} s
left join {{ ref('stg_transactions') }} t using (transaction_id)
where s.reference_date = {{ ref_date }} and s.status = 'REVERSED'
