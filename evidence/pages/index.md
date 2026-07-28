# Settlement Reconciliation

Camada analítica do Settlement Reconciliation Service. Cada página atende uma persona:

- [Operações](/operations) — saúde diária da reconciliação
- [CFO](/cfo) — volumes financeiros consolidados
- [Compliance](/compliance) — trilha de auditoria por transação

```summary
select
  count(distinct reference_date) as dias_processados,
  sum(total_transactions) as transacoes_analisadas,
  sum(mismatched_count) as mismatches,
  sum(orphan_reversal_count) as estornos_orfaos
from settlement.ops_daily
```

<BigValue data={summary} value=dias_processados title="Dias processados" />
<BigValue data={summary} value=transacoes_analisadas title="Transações analisadas" />
<BigValue data={summary} value=mismatches title="Mismatches" />
<BigValue data={summary} value=estornos_orfaos title="Estornos órfãos" />
