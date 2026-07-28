# Operações — saúde da reconciliação

```daily_health
select
  reference_date,
  sum(matched_count) as matched,
  sum(mismatched_count) as mismatched,
  sum(unreconciled_processor_count) as unreconciled_processor,
  sum(unreconciled_internal_count) as unreconciled_internal,
  sum(matched_count) / nullif(sum(total_transactions), 0) as match_rate
from settlement.ops_daily
group by 1 order by 1
```

<BarChart
  data={daily_health}
  x=reference_date
  y={["matched", "mismatched", "unreconciled_processor", "unreconciled_internal"]}
  type=stacked
  title="Resultado da reconciliação por dia"
/>

<LineChart
  data={daily_health}
  x=reference_date
  y=match_rate
  yFmt=pct1
  title="Taxa de match diária"
/>

## Merchants com mais problemas

```worst_merchants
select
  trade_name,
  sum(mismatched_count) as mismatches,
  sum(total_mismatch_amount) as valor_em_divergencia,
  sum(out_of_window_count) as fora_da_janela,
  sum(orphan_reversal_count) as estornos_orfaos
from settlement.ops_daily
group by 1
having mismatches > 0 or estornos_orfaos > 0
order by valor_em_divergencia desc
limit 15
```

<DataTable data={worst_merchants} />
