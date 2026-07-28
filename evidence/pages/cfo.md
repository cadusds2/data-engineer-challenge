# CFO — volumes financeiros

```daily_volume
select
  reference_date,
  sum(settled_amount) as liquidado,
  sum(reversed_amount) as estornado,
  sum(net_settled_amount) as liquido
from settlement.cfo_daily
group by 1 order by 1
```

<BarChart
  data={daily_volume}
  x=reference_date
  y={["liquidado", "estornado"]}
  title="Volume liquidado vs estornado por dia"
/>

<BigValue data={daily_volume} value=liquido fmt="R$ #,##0.00" title="Volume líquido total" />

## Por setor (CNAE)

```by_cnae
select
  primary_cnae,
  sum(net_settled_amount) as volume_liquido,
  sum(at_risk_amount) as valor_em_risco
from settlement.cfo_daily
group by 1 order by 2 desc limit 10
```

<BarChart data={by_cnae} x=primary_cnae y=volume_liquido swapXY=true title="Volume líquido por CNAE" />

## Top merchants

```top_merchants
select
  trade_name,
  sum(net_settled_amount) as volume_liquido,
  sum(pending_settlement_amount) as pendente_de_liquidacao
from settlement.cfo_daily
group by 1 order by 2 desc limit 15
```

<DataTable data={top_merchants} />
