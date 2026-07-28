-- Operations: daily reconciliation health per merchant.
-- Grain: reference_date x merchant_id. Idempotent per reference_date.
{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='reference_date'
) }}

with recon as (
    select
        reference_date,
        merchant_id,
        count(*) as total_transactions,
        count(*) filter (category = 'MATCHED') as matched_count,
        count(*) filter (category = 'MISMATCHED') as mismatched_count,
        count(*) filter (category = 'UNRECONCILED_PROCESSOR') as unreconciled_processor_count,
        count(*) filter (category = 'UNRECONCILED_INTERNAL') as unreconciled_internal_count,
        count(*) filter (is_out_of_window) as out_of_window_count,
        count(*) filter (internal_status_anomaly) as status_anomaly_count,
        count(*) filter (currency_mismatch) as currency_mismatch_count,
        coalesce(sum(abs(difference)) filter (category = 'MISMATCHED'), 0) as total_mismatch_amount
    from {{ ref('int_reconciliation') }}
    group by 1, 2
),

reversals as (
    select
        reference_date,
        merchant_id,
        count(*) as reversal_count,
        count(*) filter (reversal_status = 'ORPHAN') as orphan_reversal_count,
        coalesce(sum(reversed_amount), 0) as reversed_amount
    from {{ ref('int_reversals') }}
    group by 1, 2
)

select
    coalesce(r.reference_date, v.reference_date) as reference_date,
    coalesce(r.merchant_id, v.merchant_id) as merchant_id,
    m.trade_name,
    coalesce(r.total_transactions, 0) as total_transactions,
    coalesce(r.matched_count, 0) as matched_count,
    coalesce(r.mismatched_count, 0) as mismatched_count,
    coalesce(r.unreconciled_processor_count, 0) as unreconciled_processor_count,
    coalesce(r.unreconciled_internal_count, 0) as unreconciled_internal_count,
    coalesce(r.out_of_window_count, 0) as out_of_window_count,
    coalesce(r.status_anomaly_count, 0) as status_anomaly_count,
    coalesce(r.currency_mismatch_count, 0) as currency_mismatch_count,
    coalesce(r.total_mismatch_amount, 0) as total_mismatch_amount,
    coalesce(v.reversal_count, 0) as reversal_count,
    coalesce(v.orphan_reversal_count, 0) as orphan_reversal_count,
    coalesce(v.reversed_amount, 0) as reversed_amount,
    case when coalesce(r.total_transactions, 0) > 0
        then round(r.matched_count / r.total_transactions::decimal, 4)
        else null
    end as match_rate
from recon r
full outer join reversals v using (reference_date, merchant_id)
left join {{ ref('dim_merchant') }} m using (merchant_id)
