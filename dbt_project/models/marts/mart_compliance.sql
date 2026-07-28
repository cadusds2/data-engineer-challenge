-- Compliance: transaction-level audit trail of the recalculated match,
-- side by side with what the operational service recorded (cross-check).
-- Grain: reference_date x transaction_id. Idempotent per reference_date.
{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='reference_date'
) }}

with service_results as (
    -- the service occasionally records the same transaction twice within a
    -- run (seen in the fixture: ids 388/413, run 5); keep the latest row
    select transaction_id, service_category, reference_date
    from (
        select
            r.transaction_id,
            r.category as service_category,
            u.reference_date,
            row_number() over (
                partition by u.reference_date, r.transaction_id
                order by r.id desc
            ) as rn
        from {{ ref('stg_reconciliation_results') }} r
        join {{ ref('stg_reconciliation_runs') }} u on r.run_id = u.run_id
        where u.is_latest_run
    )
    where rn = 1
)

select
    e.reference_date,
    e.transaction_id,
    e.merchant_id,
    m.legal_name,
    m.document,
    e.internal_amount,
    e.processor_amount,
    e.difference,
    e.internal_status,
    e.internal_created_at,
    e.settled_at,
    e.processor_reference,
    e.category as engine_category,
    s.service_category,
    s.service_category is not null
        and s.service_category != e.category as categories_diverge,
    e.currency_mismatch,
    e.internal_status_anomaly,
    e.is_out_of_window,
    current_timestamp as processed_at
from {{ ref('int_reconciliation') }} e
left join service_results s
    on e.transaction_id = s.transaction_id
    and e.reference_date = s.reference_date
left join {{ ref('dim_merchant') }} m using (merchant_id)
