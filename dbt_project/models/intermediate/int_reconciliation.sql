-- Reconciliation engine: recomputes the match between internal transactions
-- and the PaySettler file for the reference date, instead of mirroring the
-- operational service's stored results (kept as a cross-check only).
--
-- Rules (docs/domain-glossary.md):
--   match key       transaction_id
--   internal window created_at in [reference_date - N days, reference_date]
--   tolerance       abs(processor - internal) <= tolerance => MATCHED
--
-- Edge decisions (documented in the PR):
--   * only SETTLED processor rows enter the match; REVERSED goes to
--     int_reversals
--   * processor file deduplicated by transaction_id (latest settled_at wins)
--   * internal PENDING/FAILED are not expected to settle: they leave the
--     universe unless the processor settled them anyway, which is flagged
--     as internal_status_anomaly
--   * currency divergence forces MISMATCHED and is flagged
--   * UNRECONCILED_PROCESSOR rows are flagged is_out_of_window when the
--     transaction exists internally but outside the window

{% set ref_date = "cast('" ~ var('reference_date') ~ "' as date)" %}

with internal as (
    select transaction_id, merchant_id, amount, currency, status, created_at
    from {{ ref('stg_transactions') }}
    where cast(created_at as date)
        between {{ ref_date }} - interval ({{ var('reconciliation_window_days') }}) day
        and {{ ref_date }}
),

processor_dedup as (
    select *,
        row_number() over (
            partition by transaction_id order by settled_at desc
        ) as rn
    from {{ ref('stg_settlements') }}
    where reference_date = {{ ref_date }} and status = 'SETTLED'
),

processor as (
    select transaction_id, merchant_id, amount, currency, settled_at, processor_reference
    from processor_dedup
    where rn = 1
),

joined as (
    select
        coalesce(i.transaction_id, p.transaction_id) as transaction_id,
        coalesce(i.merchant_id, p.merchant_id) as merchant_id,
        i.amount as internal_amount,
        p.amount as processor_amount,
        p.amount - i.amount as difference,
        i.currency as internal_currency,
        p.currency as processor_currency,
        i.status as internal_status,
        i.created_at as internal_created_at,
        p.settled_at,
        p.processor_reference,
        i.transaction_id is not null as in_internal,
        p.transaction_id is not null as in_processor
    from internal i
    full outer join processor p using (transaction_id)
)

select
    {{ ref_date }} as reference_date,
    j.transaction_id,
    j.merchant_id,
    j.internal_amount,
    j.processor_amount,
    j.difference,
    j.internal_status,
    j.internal_created_at,
    j.settled_at,
    j.processor_reference,
    case
        when not j.in_internal then 'UNRECONCILED_PROCESSOR'
        when not j.in_processor then 'UNRECONCILED_INTERNAL'
        when j.internal_currency != j.processor_currency then 'MISMATCHED'
        when abs(j.difference) <= {{ var('amount_tolerance') }} then 'MATCHED'
        else 'MISMATCHED'
    end as category,
    j.in_internal and j.in_processor
        and j.internal_currency != j.processor_currency as currency_mismatch,
    j.in_internal and j.in_processor
        and j.internal_status != 'COMPLETED' as internal_status_anomaly,
    not j.in_internal and exists (
        select 1 from {{ ref('stg_transactions') }} t
        where t.transaction_id = j.transaction_id
    ) as is_out_of_window
from joined j
where
    -- PENDING/FAILED with no settlement are not expected to reconcile
    not (j.in_internal and not j.in_processor and j.internal_status != 'COMPLETED')
