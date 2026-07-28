-- Grain protection without extra packages: any duplicated key in the
-- persona marts fails the build.
select 'mart_operations' as mart, reference_date::varchar as k1, merchant_id as k2
from {{ ref('mart_operations') }}
group by 1, 2, 3 having count(*) > 1

union all

select 'mart_cfo', reference_date::varchar, merchant_id
from {{ ref('mart_cfo') }}
group by 1, 2, 3 having count(*) > 1

union all

select 'mart_compliance', reference_date::varchar, transaction_id
from {{ ref('mart_compliance') }}
group by 1, 2, 3 having count(*) > 1
