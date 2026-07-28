"""Settlement analytics pipeline orchestrator.

Thin wrapper around dbt: validates inputs, resolves the reference date,
runs the transformations and reports the outcome with structured logs.
"""

import argparse
import json
import logging
import os
import subprocess
import time
from pathlib import Path

DBT_PROJECT_DIR = Path(__file__).resolve().parent.parent / "dbt_project"
REQUIRED_FILES = [
    "transactions_batch_1.parquet",
    "reconciliation_runs.parquet",
    "reconciliation_results.parquet",
    "enterprise_company.parquet",
    "settlement_paysettler.csv",
]

log = logging.getLogger("pipeline")


def setup_logging() -> None:
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )


def validate_inputs(data_path: Path) -> None:
    missing = [f for f in REQUIRED_FILES if not (data_path / f).exists()]
    if missing:
        log.error("missing input files in %s: %s", data_path, missing)
        raise SystemExit(2)
    log.info("input validation ok: %d required files present", len(REQUIRED_FILES))


def run_dbt(reference_date: str) -> None:
    dbt_vars = json.dumps({"reference_date": reference_date})
    cmd = [
        "dbt", "build",
        "--project-dir", str(DBT_PROJECT_DIR),
        "--profiles-dir", str(DBT_PROJECT_DIR),
        "--vars", dbt_vars,
    ]
    log.info("running: %s", " ".join(cmd))
    started = time.monotonic()
    result = subprocess.run(cmd, check=False)
    elapsed = time.monotonic() - started
    if result.returncode != 0:
        log.error("dbt build failed (exit=%d, %.1fs)", result.returncode, elapsed)
        raise SystemExit(1)
    log.info("dbt build succeeded in %.1fs", elapsed)


def main() -> None:
    setup_logging()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--reference-date",
        default=os.environ.get("REFERENCE_DATE", "2025-03-16"),
        help="Reference date (YYYY-MM-DD) to process",
    )
    args = parser.parse_args()

    data_path = Path(os.environ.get("DATA_PATH", "/app/docs/sample-data"))
    warehouse = Path(os.environ.get("WAREHOUSE_PATH", "/app/warehouse/settlement.duckdb"))
    warehouse.parent.mkdir(parents=True, exist_ok=True)

    log.info("pipeline start reference_date=%s data_path=%s", args.reference_date, data_path)
    validate_inputs(data_path)
    run_dbt(args.reference_date)
    log.info("pipeline finished reference_date=%s", args.reference_date)


if __name__ == "__main__":
    main()
