# Settlement Reconciliation — camada analítica

Solução para o [case de Engenharia de Dados](docs/challenge-statement.md): um mini data
warehouse local (DuckDB + dbt) que **recalcula a reconciliação de liquidações a partir
das fontes cruas** e publica marts dedicados a três personas — Operações, CFO e
Compliance.

## Como rodar

Pré-requisitos: Docker + Docker Compose.

```bash
docker compose up -d --build   # constrói e sobe o container do pipeline
make run                       # roda o pipeline (REFERENCE_DATE=2025-03-16 por padrão)
make run REFERENCE_DATE=2025-03-13
make test                      # pytest dentro do container (12 testes)
```

Consultar os resultados:

```bash
docker compose exec pipeline python -c "
import duckdb
c = duckdb.connect('/app/warehouse/settlement.duckdb', read_only=True)
print(c.sql('select * from mart_operations limit 10'))"
```

Queries de exemplo por persona: [docs/example-queries.sql](docs/example-queries.sql).

Documentação navegável do dbt (lineage + catálogo de colunas):

```bash
make docs   # http://localhost:8080
```

BI opcional (Evidence — não é dependência do pipeline):

```bash
docker compose --profile bi up -d   # http://localhost:3000 (primeira subida baixa dependências)
```

Teste de escala (~1M linhas):

```bash
make generate-large
docker compose exec -e DATA_PATH=/tmp/generated-large pipeline \
  python pipeline/pipeline.py --reference-date 2025-03-16
```

## Decisão central: recalcular a reconciliação

O banco fonte já traz `reconciliation_results` pronto. Havia dois caminhos:

1. **Espelhar** os resultados do serviço (simples, mas nunca toca o CSV além de contar linhas);
2. **Recalcular** o match a partir das fontes cruas, aplicando as regras do glossário
   (janela de 7 dias, tolerância de R$ 0,01, match por `transaction_id`).

Escolhi **recalcular** (`int_reconciliation`), pelos motivos:

- Os dados plantam anomalias que só aparecem refazendo o match: estorno REVERSED órfão,
  liquidações fora da janela, `merchant_id` nulo — todas detectadas e expostas nos marts.
- Uma camada analítica que *verifica* o sistema operacional tem valor de auditoria: se o
  serviço tiver um bug, o espelho propaga; o recálculo detecta.
- Os resultados históricos do serviço **não são descartados**: viram cross-check
  (`assert_engine_matches_service`, severidade `warn`) e aparecem lado a lado no
  `mart_compliance` (`engine_category` × `service_category`).

Custo assumido: duas implementações da regra de match (a do serviço e a nossa). Mitigado
pelo cross-check contínuo e pela regra estar centralizada em um único modelo SQL coberto
por unit tests.

## Modelagem (Parte 1)

```
fontes (parquet CDC + CSV)
  └─ staging (5 views): dedup CDC, tipos, normalização de valores
       └─ int_reconciliation (motor) + int_reversals
            └─ dim_merchant + marts por persona
```

| Tabela | Grão | Persona | Perguntas que responde |
|---|---|---|---|
| `mart_operations` | dia × merchant | Operações | Taxa de match de ontem? Quais merchants concentram mismatch? Quantas liquidações fora da janela? |
| `mart_cfo` | dia × merchant | CFO | Volume liquidado/estornado/líquido por período, merchant e CNAE? Quanto está em risco (mismatch) ou pendente? |
| `mart_compliance` | transação | Compliance | O que aconteceu com a transação X? Onde nosso recálculo diverge do registro do serviço? Quais anomalias estão abertas? |

**O que o modelo NÃO responde** (limites declarados):

- Histórico de cadastro do merchant (dimensão é SCD tipo 1 — mudança de razão social
  sobrescreve; ver [Limites do desenho](#limites-do-desenho-casos-concretos-não-suportados)).
- Análise intradiária (grão mínimo é o dia).
- Reconciliação entre múltiplas moedas (divergência de moeda é flagada como anomalia,
  não convertida).

### Decisões de modelagem

- **Sem `dim_date`**: funções de data do DuckDB cobrem as necessidades atuais; a
  dimensão entraria se houvesse regra de dias úteis/feriados bancários (relevante em
  liquidação D+1).
- **Membro desconhecido** em `dim_merchant`: transações com `merchant_id` nulo
  (plantadas pelo gerador) agregam no bucket `UNKNOWN` em vez de sumirem silenciosamente.
- **Runs reprocessadas**: 9 datas do fixture têm mais de uma run; `is_latest_run` marca
  a autoritativa (última COMPLETED). Compliance enxerga todas.

## Pipeline (Parte 2)

`pipeline/pipeline.py` (orquestração: valida entradas, resolve a data, logs
estruturados, exit codes) → `dbt build` (transformações + testes).

| Critério | Como foi atendido |
|---|---|
| Correção | Motor com unit tests dbt: um caso controlado por regra de negócio (borda da tolerância, janela, moeda, status, dedup) |
| Idempotência | Marts incrementais `delete+insert` por `reference_date`; teste e2e roda o pipeline 2× e compara contagens |
| Observabilidade | Logs estruturados por etapa (arquivos validados, duração, resultado); exit codes distintos (2 = entrada faltando, 1 = falha de transformação) |
| Qualidade | 32 testes dbt: contratos de chave/nulos/valores por camada, proteção de grão, cross-check motor × serviço (warn) |
| Testabilidade | `make test`: 12 testes pytest (e2e, idempotência, entradas malformadas) + suíte original do gerador |

### Anomalias reais encontradas nos dados

1. **CDC**: 1.060 eventos → 995 transações vivas (updates/deletes colapsados por
   `_timestamp`).
2. **Schema drift**: `transactions_batch_2` adiciona `payment_method`; absorvido com
   `union_by_name`.
3. **CSV com moeda formatada**: `R$ 18.319,17` misturado com `2616.01`; leitura forçada
   como texto (`all_varchar`) para a inferência de tipos não variar com o conteúdo do
   arquivo — bug real encontrado no teste de escala.
4. **Duplicata na fonte**: o serviço gravou a mesma transação 2× na run 5 (ids 388/413);
   detectado pelo teste de proteção de grão, deduplicado no cross-check.
5. **Estorno órfão** e **liquidações fora da janela**: expostos como flags/contagens nos
   marts.
6. **CSV do fixture é sintético**: não corresponde 1:1 ao histórico (~0 MATCHED no
   recálculo da amostra é esperado). Por isso a correção é provada com fixtures
   controlados (unit tests), não com a amostra.

## Extensibilidade: segunda fonte de liquidação

O acoplamento ao PaySettler está isolado em dois pontos: a source `paysettler` e o
`stg_settlements` (normalização). Para um segundo processador:

1. Nova source + novo modelo de staging traduzindo para o contrato canônico
   (`transaction_id`, `merchant_id`, `amount`, `currency`, `settled_at`, `status`,
   `processor`);
2. Union dos stagings num `stg_settlements_unified` com coluna `processor`;
3. Motor e marts inalterados (o match não sabe de qual processador veio a linha); marts
   ganham `processor` como dimensão de quebra.

Quando a ingestão deixar de ser "arquivos locais" (API paginada, SFTP, estado
incremental), um framework como **dlt** passa a se justificar; hoje seria camada extra
sobre ~20 linhas de SQL.

## Limites do desenho (casos concretos não suportados)

1. **Merchant muda de razão social no meio do mês**: relatório mensal do CFO mostra toda
   a série com o nome novo (SCD1). Suporte exigiria SCD2 com vigências.
2. **Arquivo do processador re-enviado com correções para data antiga**: o
   reprocessamento sobrescreve o dia (idempotência), mas não há versionamento do
   *arquivo* — não sabemos responder "o que o arquivo do dia 10 dizia antes da
   correção?". Exigiria camada raw imutável com versionamento.
3. **Transação liquidada em parcelas** (settlement parcial): o match é 1:1 por
   `transaction_id`; N liquidações parciais somariam como duplicata/mismatch. Exigiria
   match por agregação.

## Diferenças vs. produção

O que foi simplificado e o que mudaria — detalhado em
[docs/architecture.md](docs/architecture.md):

- Warehouse: DuckDB local → BigQuery/Snowflake/Redshift (DuckDB não suporta escritores
  concorrentes).
- Orquestração: execução manual → disparo por chegada de arquivo (EventBridge + Step
  Functions na AWS; Eventarc + Cloud Run Jobs no GCP).
- Ingestão: arquivos locais → CDC gerenciado (DMS/Datastream) + landing em objeto
  (S3/GCS) com camada raw imutável, particionada por data, e evolução para ingestão
  incremental com watermark.
- Alertas: logs → métricas + alerting (CloudWatch/Cloud Monitoring), incluindo o
  cross-check como alarme.
- Segredos, IAM, retenção e LGPD (mascaramento de CNPJ no mart de BI).

## Ferramentas de IA

Usei **Claude Code** (Anthropic) como par de programação, com transparência total: o
processo importa tanto quanto o resultado, então detalho abaixo como a solução foi
concebida e qual foi o papel de cada parte.

**Como trabalhei.** Conduzi o desenvolvimento em sessões interativas, no modelo de
decisões minhas / execução assistida. Antes de qualquer código, usei a IA para explorar
o enunciado e os dados (schemas, contagens, anomalias) e então **cada decisão
estrutural foi discutida e definida por mim**, frequentemente contrariando a primeira
sugestão da ferramenta:

- **Recalcular a reconciliação** em vez de espelhar `reconciliation_results`: a
  proposta inicial da IA era espelhar; após analisarmos as armadilhas plantadas nos
  dados (estorno órfão, fora-da-janela), decidi pelo recálculo com cross-check — a
  decisão central do case.
- **dbt como motor de transformação**: escolha minha, a partir da minha experiência
  prévia com a ferramenta; defini também a divisão "dbt transforma, Python orquestra".
- **Orquestração de produção sem Airflow/Dagster**: questionei a recomendação padrão e
  defendi Step Functions/Cloud Workflows para um pipeline linear diário — o desenho
  documentado na Parte 3 reflete essa posição, com o ponto de virada explícito.
- **Uma tabela por persona** (marts dedicados): direcionamento meu, priorizando a
  facilidade de consumo; a IA propunha originalmente uma única agregada.
- **Cortar `dim_date`**: questionei a necessidade e removemos, documentando quando ela
  voltaria (dias úteis/feriados em liquidação D+1).
- **Evidence como BI** e **não usar dlt**: avaliei os trade-offs com a IA e decidi
  incluir o primeiro (BI-as-code, opcional) e deixar o segundo documentado como
  evolução — em vez de inflar a stack.
- **Não gerar Terraform não testado**: decidi limitar IaC a um esqueleto ilustrativo e
  investir em CI real (GitHub Actions), após discussão sobre o risco de entregar
  infraestrutura nunca aplicada.
- **Escopo do incremental**: discuti a fundo o full scan do staging e decidi
  conscientemente *não* implementar ingestão incremental com watermark neste volume,
  documentando a escada de evolução (particionamento → watermark + MERGE) na Parte 3.

**O que a IA executou sob essa direção**: exploração inicial dos dados, escrita de
SQL/Python/testes, análise dos PRs públicos concorrentes (usados como benchmark de
decisões, sem reaproveitamento de código), depuração (o bug de inferência de tipos do
CSV apareceu num teste de escala que eu pedi) e redação da documentação — **revisada e
ajustada por mim antes de cada commit** (esta seção inclusive).

**O que fica de aprendizado do processo**: a IA acelera execução e amplia a exploração,
mas as escolhas que definem a qualidade da entrega — o que construir, o que cortar, o
que assumir como premissa — continuam sendo trabalho de engenharia humano. O histórico
de commits reflete essa evolução real, incluindo os erros encontrados e corrigidos no
caminho.
