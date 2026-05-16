---
name: airflow
description: |
  Airflow DAG development skill for writing, reviewing, testing, and debugging Apache Airflow workflows. Use whenever the user mentions Airflow, DAGs, tasks, operators, sensors, schedules, retries, catchup, DAG import errors, DAG parse performance, or workflow orchestration in Python. Also use for Amazon MWAA / Managed Workflows for Apache Airflow work, including MWAA DAG deployment, requirements.txt, plugins.zip, aws-mwaa-docker-images, S3 DAG folders, CloudWatch logs, and MWAA-specific dependency or IAM issues.
---

# Airflow DAG Development Skill

Use this skill when creating, changing, reviewing, or debugging Airflow DAGs. Treat DAG code as production orchestration code: small parse-time mistakes can break scheduling, retries can duplicate side effects, and dependency changes can prevent the environment from starting.

If the task is for Amazon MWAA, read [references/mwaa.md](references/mwaa.md) before making recommendations or edits.

## Work Start Checklist

1. Identify the Airflow runtime:
   - Airflow major/minor version
   - Python version
   - executor/environment: local Airflow, MWAA, Composer, Astronomer, self-managed
   - dependency source: `requirements.txt`, constraints file, plugins, Docker image, or managed environment
2. Inspect the DAG shape:
   - DAG file location and imports
   - `dag_id`, `schedule`, `start_date`, `catchup`, retries, timeout settings
   - task/operator types and external systems touched
   - dynamic DAG or dynamic task mapping usage
3. Pick the smallest safe verification:
   - Python syntax/import check
   - DAG parse test
   - unit test for DAG structure or custom operator
   - local Airflow/MWAA runner test when environment behavior matters

## DAG Authoring Rules

### Keep Top-Level Code Light

Airflow parses DAG files repeatedly. Avoid expensive work at module import time:

- Do not call databases, APIs, S3, Secrets Manager, or Airflow Variables at top level.
- Do not perform heavy computation, large file reads, or network calls while defining the DAG.
- Prefer environment variables or small config files shipped with the DAG for parse-time configuration.
- Import optional or heavy dependencies inside task callables when the dependency is not needed to parse the DAG.

Good pattern:

```python
import os
from airflow.decorators import dag, task
from pendulum import datetime

DEPLOYMENT = os.environ.get("DEPLOYMENT", "dev")


@dag(
    dag_id="example_pipeline",
    schedule="@daily",
    start_date=datetime(2026, 1, 1, tz="UTC"),
    catchup=False,
)
def example_pipeline():
    @task
    def run_step(deployment: str) -> None:
        import boto3

        # Runtime work belongs inside tasks.
        boto3.client("sts").get_caller_identity()
        print(f"deployment={deployment}")

    run_step(DEPLOYMENT)


example_pipeline()
```

Avoid:

```python
from airflow.models import Variable

CONFIG = Variable.get("pipeline_config", deserialize_json=True)  # DB hit at parse time
```

### Make Tasks Idempotent

Airflow retries tasks, so each task should be safe to re-run:

- Write outputs atomically when possible: temporary prefix/file first, then final marker or rename/copy.
- Partition outputs by logical date or data interval, not by wall-clock execution time.
- Avoid appending blindly to S3, databases, or queues.
- Use deterministic object keys and idempotency keys for external calls.
- If a task creates side effects, make the task check whether the target state already exists before writing again.

### Model Scheduling Explicitly

Check these fields on every DAG:

- `start_date`: use a fixed, timezone-aware date; do not use `datetime.now()`.
- `schedule`: confirm whether the DAG should be cron, preset, dataset/event-driven, or manual.
- `catchup`: set intentionally. For most operational DAGs, `catchup=False`; for backfill/data interval workloads, `catchup=True` may be right.
- `max_active_runs`, `max_active_tasks`, pools, and task concurrency: use them to protect downstream systems.
- retries and delays: make transient failures retry, but avoid hiding deterministic data bugs with excessive retries.

### Prefer Clear Task Boundaries

- Keep each task focused on one externally observable step.
- Pass small metadata through XCom; store large data in S3/database and pass references.
- Use Task Groups for readability, not as a substitute for a clean dependency graph.
- Prefer built-in/provider operators and sensors when they directly match the job.
- Use custom operators/hooks only when shared behavior is repeated across DAGs.

### Dynamic DAGs

When generating DAGs or tasks dynamically:

- Keep generated task/DAG order stable with `sorted()` or another deterministic ordering.
- Keep dynamic DAG structure stable between parses. If the number of tasks changes based on runtime data, consider dynamic task mapping instead.
- Do not query external systems at top level to discover DAG structure.
- Store structured config next to the DAG or generate Python metadata as part of deployment.
- For many generated DAGs in one file, consider Airflow parsing-context optimizations only after measuring parse time.

## Testing And Verification

Use the lightest verification that catches the risk.

### Syntax and Import

```sh
python -m py_compile dags/my_dag.py
```

If Airflow is installed:

```sh
python -c "import dags.my_dag"
```

### DAG Parse Test

Use `DagBag` to catch import errors and validate the DAG registry.

```python
from airflow.models import DagBag


def test_dag_imports():
    dag_bag = DagBag(dag_folder="dags", include_examples=False)
    assert dag_bag.import_errors == {}
    assert "example_pipeline" in dag_bag.dags
```

### DAG Structure Test

Assert key dependencies so refactors do not silently change orchestration.

```python
def test_dependencies():
    dag = DagBag(dag_folder="dags", include_examples=False).get_dag("example_pipeline")
    assert dag is not None
    assert dag.get_task("extract").downstream_task_ids == {"transform"}
    assert dag.get_task("transform").downstream_task_ids == {"load"}
```

### Custom Operator or Task Test

- Test business logic outside Airflow when possible.
- For custom operators, instantiate a tiny DAG in a fixture and run the task instance only when the behavior needs Airflow context.
- Mock Airflow Variables and Connections with environment variables:
  - `AIRFLOW_VAR_<KEY>`
  - `AIRFLOW_CONN_<CONN_ID>`

## Debugging DAG Import Errors

When the UI says a DAG is missing or has import errors:

1. Run a local import or `DagBag` parse test.
2. Check top-level imports for missing packages.
3. Check top-level code for network calls, Airflow Variables, or secrets lookups.
4. Check duplicate `dag_id` values.
5. Check Airflow/Python/provider version compatibility.
6. Check scheduler logs, not only task logs.

For MWAA, also read [references/mwaa.md](references/mwaa.md) and check CloudWatch scheduler logs plus `requirements_install_ip` logs for dependency installation failures.

## Review Checklist

When reviewing Airflow DAG changes, look for:

- Top-level side effects or slow imports
- Non-idempotent writes under retry
- `datetime.now()` or moving `start_date`
- accidental `catchup=True` or missing catchup decision
- unbounded fan-out or missing downstream throttling
- large XCom payloads
- secrets embedded in DAG code or logs
- missing parse/unit tests for DAG structure
- provider/dependency changes without constraints or local validation

## Source Notes

This skill is based on Apache Airflow best-practice guidance and AWS MWAA documentation. Prefer current official docs when the exact Airflow or MWAA version matters.
