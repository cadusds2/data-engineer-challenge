-- Queries de exemplo por persona.
-- Executar após `make run`, copiando a query desejada para qualquer cliente
-- DuckDB apontado para /app/warehouse/settlement.duckdb (modo read-only).

-- =========================================================================
-- OPERAÇÕES
-- =========================================================================

-- 1. Saúde da reconciliação de um dia: taxa de match e composição por categoria
select
    reference_date,
    sum(total_transactions) as transacoes,
    round(sum(matched_count)::decimal / nullif(sum(total_transactions), 0), 4) as taxa_match,
    sum(mismatched_count) as mismatched,
    sum(unreconciled_processor_count) as so_no_processador,
    sum(unreconciled_internal_count) as so_interno,
    sum(out_of_window_count) as fora_da_janela,
    sum(orphan_reversal_count) as estornos_orfaos
from mart_operations
where reference_date = date '2025-03-16'
group by 1;

-- 2. Merchants que exigem ação hoje, priorizados por valor em divergência
select
    trade_name,
    mismatched_count,
    total_mismatch_amount,
    out_of_window_count,
    orphan_reversal_count
from mart_operations
where reference_date = date '2025-03-16'
  and (mismatched_count > 0 or orphan_reversal_count > 0)
order by total_mismatch_amount desc
limit 10;

-- =========================================================================
-- CFO
-- =========================================================================

-- 3. Volume financeiro consolidado do período (liquidado, estornado, líquido)
select
    date_trunc('month', reference_date) as mes,
    sum(settled_amount) as liquidado,
    sum(reversed_amount) as estornado,
    sum(net_settled_amount) as liquido,
    sum(at_risk_amount) as em_risco_mismatch,
    sum(pending_settlement_amount) as pendente_liquidacao
from mart_cfo
group by 1
order by 1;

-- 4. Concentração por setor (CNAE) — top 10 por volume líquido
select
    primary_cnae,
    count(distinct merchant_id) as merchants,
    sum(net_settled_amount) as volume_liquido
from mart_cfo
group by 1
order by 3 desc
limit 10;

-- =========================================================================
-- COMPLIANCE
-- =========================================================================

-- 5. Trilha de auditoria de uma transação específica
select
    reference_date,
    transaction_id,
    legal_name,
    internal_amount,
    processor_amount,
    difference,
    engine_category,
    service_category,
    categories_diverge,
    processor_reference
from mart_compliance
where transaction_id = 'fecc4954-1305-4a4d-ab4f-6fac1793ac8d';

-- 6. Divergências entre nosso recálculo e o registro do serviço (matriz)
select
    engine_category,
    coalesce(service_category, '(sem registro do serviço)') as service_category,
    count(*) as transacoes,
    sum(coalesce(abs(difference), 0)) as valor_divergente
from mart_compliance
group by 1, 2
order by 3 desc;

-- 7. Anomalias abertas que exigem justificativa em auditoria
select
    reference_date,
    transaction_id,
    legal_name,
    case
        when internal_status_anomaly then 'liquidada com status interno ' || internal_status
        when currency_mismatch then 'divergencia de moeda'
        when is_out_of_window then 'liquidacao fora da janela de 7 dias'
    end as anomalia,
    coalesce(processor_amount, internal_amount) as valor
from mart_compliance
where internal_status_anomaly or currency_mismatch or is_out_of_window
order by valor desc
limit 20;
