# Compliance — trilha de auditoria

```divergences
select
  engine_category,
  coalesce(service_category, '(sem registro do serviço)') as service_category,
  count(*) as transacoes
from settlement.compliance_detail
group by 1, 2 order by 3 desc
```

<DataTable data={divergences} title="Recálculo (engine) vs registro do serviço" />

## Anomalias abertas

```anomalies
select
  reference_date,
  transaction_id,
  legal_name,
  engine_category,
  internal_amount,
  processor_amount,
  difference,
  case
    when internal_status_anomaly then 'liquidada com status interno ' || internal_status
    when currency_mismatch then 'divergência de moeda'
    when is_out_of_window then 'liquidação fora da janela de 7 dias'
  end as anomalia
from settlement.compliance_detail
where internal_status_anomaly or currency_mismatch or is_out_of_window
order by abs(coalesce(difference, processor_amount, internal_amount)) desc
limit 50
```

<DataTable data={anomalies} search=true />
