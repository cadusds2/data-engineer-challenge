-- CFO: consolidated financial volumes per day and merchant, enriched with
-- registry attributes for sector (CNAE) roll-ups.
-- Grain: reference_date x merchant_id. Idempotent per reference_date.
{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='reference_date'
) }}

{% set ref_date = "cast('" ~ var('reference_date') ~ "' as date)" %}

with settled as (
    select
        reference_date,
        coalesce(merchant_id, 'UNKNOWN') as merchant_id,
        count(*) filter (status = 'SETTLED') as settled_count,
        coalesce(sum(amount) filter (status = 'SETTLED'), 0) as settled_amount,
        count(*) filter (status = 'REVERSED') as reversed_count,
        coalesce(sum(amount) filter (status = 'REVERSED'), 0) as reversed_amount
    from {{ ref('stg_settlements') }}
    where reference_date = {{ ref_date }}
    group by 1, 2
),

reconciled as (
    select
        reference_date,
        coalesce(merchant_id, 'UNKNOWN') as merchant_id,
        coalesce(sum(processor_amount) filter (category = 'MATCHED'), 0) as matched_amount,
        coalesce(sum(abs(difference)) filter (category = 'MISMATCHED'), 0) as at_risk_amount,
        coalesce(sum(processor_amount) filter (category = 'UNRECONCILED_PROCESSOR'), 0)
            as unrecognized_settled_amount,
        coalesce(sum(internal_amount) filter (category = 'UNRECONCILED_INTERNAL'), 0)
            as pending_settlement_amount
    from {{ ref('int_reconciliation') }}
    group by 1, 2
)

select
    coalesce(s.reference_date, r.reference_date) as reference_date,
    coalesce(s.merchant_id, r.merchant_id) as merchant_id,
    m.legal_name,
    m.trade_name,
    m.primary_cnae,
    coalesce(s.settled_count, 0) as settled_count,
    coalesce(s.settled_amount, 0) as settled_amount,
    coalesce(s.reversed_count, 0) as reversed_count,
    coalesce(s.reversed_amount, 0) as reversed_amount,
    coalesce(s.settled_amount, 0) - coalesce(s.reversed_amount, 0) as net_settled_amount,
    coalesce(r.matched_amount, 0) as matched_amount,
    coalesce(r.at_risk_amount, 0) as at_risk_amount,
    coalesce(r.unrecognized_settled_amount, 0) as unrecognized_settled_amount,
    coalesce(r.pending_settlement_amount, 0) as pending_settlement_amount
from settled s
full outer join reconciled r using (reference_date, merchant_id)
left join {{ ref('dim_merchant') }} m using (merchant_id)
