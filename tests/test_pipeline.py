"""End-to-end tests for the pipeline orchestrator.

The engine's business rules are proven by dbt unit tests
(dbt_project/models/intermediate/schema.yml); here we test what dbt
cannot express: running the whole pipeline twice must not duplicate
rows, and bad inputs must fail loudly with the right exit code.
"""

import os
import subprocess
import sys
from pathlib import Path

import duckdb
import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
PIPELINE = REPO_ROOT / "pipeline" / "pipeline.py"
SAMPLE_DATA = REPO_ROOT / "docs" / "sample-data"
MARTS = ["mart_operations", "mart_cfo", "mart_compliance"]


def run_pipeline(data_path: Path, warehouse: Path) -> subprocess.CompletedProcess:
    env = os.environ | {
        "DATA_PATH": str(data_path),
        "WAREHOUSE_PATH": str(warehouse),
    }
    return subprocess.run(
        [sys.executable, str(PIPELINE), "--reference-date", "2025-03-16"],
        env=env,
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
        check=False,
    )


def mart_counts(warehouse: Path) -> dict[str, int]:
    con = duckdb.connect(str(warehouse), read_only=True)
    try:
        return {m: con.sql(f"select count(*) from {m}").fetchone()[0] for m in MARTS}
    finally:
        con.close()


@pytest.fixture(scope="module")
def warehouse(tmp_path_factory) -> Path:
    return tmp_path_factory.mktemp("warehouse") / "settlement.duckdb"


def test_pipeline_succeeds_on_sample_data(warehouse):
    result = run_pipeline(SAMPLE_DATA, warehouse)
    assert result.returncode == 0, result.stdout + result.stderr
    counts = mart_counts(warehouse)
    assert all(c > 0 for c in counts.values()), counts


def test_rerun_same_date_is_idempotent(warehouse):
    before = mart_counts(warehouse)
    result = run_pipeline(SAMPLE_DATA, warehouse)
    assert result.returncode == 0, result.stdout + result.stderr
    assert mart_counts(warehouse) == before


def test_missing_input_files_fail_with_exit_2(tmp_path):
    empty = tmp_path / "empty"
    empty.mkdir()
    result = run_pipeline(empty, tmp_path / "wh.duckdb")
    assert result.returncode == 2
    assert "missing input files" in result.stderr + result.stdout
