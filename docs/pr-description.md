# Settlement Reconciliation — camada analítica (DuckDB · dbt · Docker)

## Resumo

Camada analítica para o Settlement Reconciliation Service: pipeline idempotente
(Python + dbt + DuckDB) que **recalcula a reconciliação a partir das fontes cruas** —
com os resultados históricos do serviço mantidos como cross-check de auditoria — e
publica um mart dedicado por persona: `mart_operations`, `mart_cfo` e
`mart_compliance`.

A documentação completa está no
[README](https://github.com/cadusds2/data-engineer-challenge/blob/feat/settlement-analytics/README.md)
(como rodar, premissas, modelagem, critérios de qualidade, extensibilidade, limites,
uso de IA) e em
[docs/architecture.md](https://github.com/cadusds2/data-engineer-challenge/blob/feat/settlement-analytics/docs/architecture.md)
(Parte 3: produção AWS/GCP, troubleshooting, escalabilidade). O enunciado original foi
preservado em `docs/challenge-statement.md`.

## Como rodar

```bash
docker compose up -d --build
make run    # pipeline completo (modelos + 32 testes dbt)
make test   # 12 testes pytest (inclui idempotência e2e)
make docs   # documentação navegável do dbt em :8080
docker compose --profile bi up -d   # dashboard Evidence em :3000 (opcional)
```

## Destaques

- **Decisão central documentada**: recalcular vs. espelhar `reconciliation_results` —
  trade-off analisado no README, com o custo assumido explícito.
- **Anomalias reais tratadas**: CDC com updates/deletes, schema drift entre batches,
  valores `R$ 1.234,56` no CSV, runs reprocessadas, transação duplicada na fonte (pega
  por teste de grão), estorno órfão, liquidações fora da janela, `merchant_id` nulo.
- **Idempotência provada**: marts `delete+insert` por `reference_date`; teste e2e
  executa o pipeline 2× e compara contagens — também no CI.
- **Testes em três camadas**: contratos dbt por camada, unit tests do motor (um caso
  controlado por regra de negócio) e pytest e2e.
- **Escala validada**: 1M de linhas em ~8s; análise de onde o desenho quebra a 5M/dia
  na Parte 3.
- **CI**: lint + build + pipeline (2×) + suíte de testes — verde no fork.

## Escopo consciente (não incluído, com justificativa no README/Parte 3)

- SCD2 na dimensão de merchant; ingestão incremental com watermark (escada de evolução
  documentada); Terraform aplicado (esqueleto ilustrativo apenas); multi-moeda.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
