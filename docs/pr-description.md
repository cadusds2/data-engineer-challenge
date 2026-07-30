# Settlement Reconciliation — camada analítica (DuckDB · dbt · Docker)

Pipeline idempotente (Python + dbt + DuckDB) que **recalcula a reconciliação a partir
das fontes cruas** — com os resultados históricos do serviço mantidos como cross-check
de auditoria — e publica um mart dedicado por persona: `mart_operations`, `mart_cfo` e
`mart_compliance`. Documentação completa no
[README](https://github.com/cadusds2/data-engineer-challenge/blob/feat/settlement-analytics/README.md)
e em
[docs/architecture.md](https://github.com/cadusds2/data-engineer-challenge/blob/feat/settlement-analytics/docs/architecture.md)
(Parte 3). O enunciado original foi preservado em `docs/challenge-statement.md`.

### Como rodar

```bash
docker compose up -d --build
make run    # pipeline completo (REFERENCE_DATE=2025-03-16 por padrão; modelos + 32 testes dbt)
make test   # 12 testes pytest (inclui idempotência e2e)
make docs   # documentação navegável do dbt (lineage + catálogo) em :8080
docker compose --profile bi up -d   # dashboard Evidence por persona em :3000 (opcional)
```

Queries de exemplo validadas por persona:
[docs/example-queries.sql](https://github.com/cadusds2/data-engineer-challenge/blob/feat/settlement-analytics/docs/example-queries.sql).
Teste de escala: `make generate-large` + pipeline com `DATA_PATH=/tmp/generated-large`
(1M linhas em ~8s).

### Premissas e decisões

- **Decisão central — recalcular vs. espelhar**: o banco já traz
  `reconciliation_results` pronto; optei por **recalcular o match** a partir das fontes
  cruas (janela de 7 dias, tolerância de R$ 0,01, match por `transaction_id`), porque os
  dados plantam anomalias que só aparecem refazendo o match (estorno REVERSED órfão,
  liquidações fora da janela, `merchant_id` nulo) e porque uma camada que *verifica* o
  operacional tem valor de auditoria. Os resultados do serviço viraram **cross-check**
  (teste `warn` + lado a lado no `mart_compliance`). Custo assumido: duas implementações
  da regra — mitigado pelo cross-check contínuo e por unit tests do motor.
- **CSV do fixture é sintético** e não corresponde 1:1 ao histórico (~0 MATCHED no
  recálculo da amostra é esperado); a correção do motor é provada com unit tests de
  inputs controlados (9 casos, um por regra de negócio).
- **Runs reprocessadas**: 9 datas têm mais de uma run; a última COMPLETED é a
  autoritativa (`is_latest_run`) para Ops/CFO; Compliance enxerga todas.
- **Bordas do match**: REVERSED tratado à parte (`int_reversals`, LINKED/ORPHAN);
  moeda divergente força MISMATCHED com flag; PENDING/FAILED sem liquidação saem do
  universo; liquidada com status ≠ COMPLETED vira flag de anomalia.
- **CSV lido com `all_varchar`**: a inferência de tipos não pode variar com o conteúdo
  (amounts chegam como `2616.01` e como `R$ 18.319,17`) — bug real encontrado no teste
  de escala; tipagem explícita no staging.
- **Merchant nulo** agrega no membro `UNKNOWN` da dimensão (padrão Kimball) em vez de
  sumir das somas.

### Visão geral da arquitetura

```
fontes (parquet CDC + CSV)
  └─ staging (5 views): colapso de CDC, tipos, normalização de valores
       └─ int_reconciliation (motor de match) + int_reversals (estornos)
            └─ dim_merchant + mart_operations / mart_cfo / mart_compliance
```

`pipeline/pipeline.py` orquestra (valida entradas, resolve a data, logs estruturados,
exit codes distintos) e o `dbt build` executa transformações + testes. Marts
incrementais com `delete+insert` por `reference_date` (idempotência provada por teste
e2e que roda o pipeline 2× — também no CI). Diagrama completo, desenho de produção
(AWS e GCP), runbook de troubleshooting e análise de escala em
[docs/architecture.md](https://github.com/cadusds2/data-engineer-challenge/blob/feat/settlement-analytics/docs/architecture.md).

### Extensibilidade

Para plugar um segundo processador de liquidação (schema parecido, não idêntico):

- **Arquivos novos (2)**: `stg_settlements_<processador>.sql` (~40 linhas — tradução do
  schema dele para o contrato canônico: `transaction_id`, `merchant_id`, `amount`,
  `currency`, `settled_at`, `status`, `processor`) e sua entrada de source em
  `sources.yml` (~15 linhas, com descrições).
- **Arquivos alterados (3)**: `stg_settlements.sql` vira union dos stagings por
  processador (~10 linhas); `schema.yml` do staging ganha os testes de contrato do novo
  modelo (~15 linhas); `pipeline.py` adiciona o arquivo à validação de entrada (1 linha
  em `REQUIRED_FILES`).
- **O que NÃO muda**: motor (`int_reconciliation`), marts e dimensão — o match não sabe
  de qual processador veio a linha; os marts ganhariam `processor` como coluna de
  quebra (~5 linhas opcionais).
- **Testes que rodam de novo**: toda a suíte, automaticamente — os contratos do staging
  cobrem o novo modelo, o unit test do motor não muda (a regra é a mesma), e o e2e de
  idempotência valida o pipeline com a fonte nova via `make test`/CI.

Total estimado: **~85 linhas em 5 arquivos**, nenhuma no motor. Quando a ingestão
deixar de ser arquivos locais (API/SFTP com estado incremental), um framework como dlt
passa a se justificar — documentado no README.

### Limites do desenho

1. **Merchant muda de razão social no meio do mês**: o relatório mensal do CFO mostra
   toda a série com o nome novo (dimensão SCD tipo 1). Suporte exigiria SCD2 com
   vigências — a fonte CDC já guarda as versões.
2. **Arquivo do processador re-enviado com correções para data antiga**: o
   reprocessamento sobrescreve o dia (idempotência), mas não há versionamento do
   *arquivo* — não respondemos "o que o arquivo do dia 10 dizia antes da correção?".
   Exigiria camada raw imutável com versionamento.
3. **Liquidação parcial/parcelada**: o match é 1:1 por `transaction_id`; N liquidações
   parciais virariam duplicata/mismatch. Exigiria match por agregação.

### O que faria diferente em produção

- **Warehouse**: DuckDB local → BigQuery/Redshift/lakehouse (DuckDB é single-writer);
  modelos dbt portáveis — a migração é de engine, não de lógica.
- **Orquestração**: disparo por evento de chegada do arquivo (EventBridge + Step
  Functions na AWS; Eventarc + Cloud Run Jobs no GCP) — orquestrador genérico basta
  porque o DAG pertence ao dbt; ponto de virada para Airflow/Dagster documentado.
- **Ingestão**: CDC gerenciado (DMS/Datastream) + raw imutável em objeto, particionada
  por data; evolução para incremental com watermark + MERGE (escada documentada na
  Parte 3, com a justificativa de por que não fiz agora).
- **Alerting**: frescor do warehouse, "nenhuma execução até 9h" e o cross-check como
  alarme de divergência.
- **Segurança/LGPD**: segredos, IAM e mascaramento de CNPJ na camada de BI.

### Ferramentas de IA utilizadas

**Claude Code** (Anthropic), como par de programação com transparência total. Modelo de
trabalho: decisões minhas, execução assistida — as escolhas estruturais (recalcular vs.
espelhar, dbt, orquestração sem Airflow, marts por persona, cortar `dim_date`, Evidence
sim / dlt não / Terraform ilustrativo, escopo do incremental) foram discutidas e
definidas por mim, várias contrariando a primeira sugestão da ferramenta. A IA executou
exploração de dados, escrita de SQL/Python/testes, depuração e redação de documentação
— revisadas por mim antes de cada commit. Relato completo, decisão por decisão, na
seção "Ferramentas de IA" do
[README](https://github.com/cadusds2/data-engineer-challenge/blob/feat/settlement-analytics/README.md#ferramentas-de-ia).
O histórico de commits reflete a evolução real do trabalho.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
