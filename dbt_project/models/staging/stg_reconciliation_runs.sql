-- Reconciliation runs with a flag marking the authoritative (latest
-- completed) run per reference_date — several dates were reprocessed.
with runs as (
    select
        id as run_id,
        cast(reference_date as date) as reference_date,
        file_name,
        status,
        total_transactions,
        cast(started_at as timestamp) as started_at,
        cast(completed_at as timestamp) as completed_at,
        "Op" as cdc_op,
        cast(_timestamp as timestamp) as cdc_timestamp
    from {{ source('settlement_db', 'reconciliation_runs') }}
),

latest_version as (
    select *,
        row_number() over (partition by run_id order by cdc_timestamp desc) as rn
    from runs
)

select
    run_id,
    reference_date,
    file_name,
    status,
    total_transactions,
    started_at,
    completed_at,
    row_number() over (
        partition by reference_date
        order by (status = 'COMPLETED') desc, started_at desc
    ) = 1 as is_latest_run
from latest_version
where rn = 1 and cdc_op != 'D'
