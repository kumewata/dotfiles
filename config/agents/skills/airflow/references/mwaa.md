# Amazon MWAA Reference

Use this reference when the user is working with Amazon Managed Workflows for Apache Airflow (MWAA). MWAA is managed Airflow, but deployment, dependencies, plugins, logs, and security boundaries differ from self-managed Airflow.

## First Questions

Before changing MWAA DAG code or dependencies, identify:

- MWAA environment name and region
- Airflow version and Python version
- DAG S3 bucket and `dags/` prefix
- whether requirements and plugins are managed by console, Terraform, CI/CD, or manual upload
- public/private webserver access mode
- execution role permissions and target AWS services

Do not assume that local Airflow version, provider versions, or Python version match MWAA.

## DAG Deployment

MWAA reads DAG files from an S3 bucket:

- DAG code goes under the configured `dags/` folder.
- MWAA syncs new and changed S3 objects to scheduler and worker containers periodically.
- New DAG visibility in the UI also depends on scheduler DAG parsing intervals.
- The S3 bucket must have public access blocked and versioning enabled.
- The environment execution role must be allowed to access the bucket and downstream AWS resources.

Recommended deployment flow:

1. Validate DAG syntax and imports locally.
2. Run DAG parse tests.
3. If MWAA behavior or dependencies matter, test with `aws-mwaa-docker-images`.
4. Upload DAG files through CI/CD or controlled AWS CLI commands.
5. Check MWAA scheduler logs in CloudWatch after deployment.

## Dependencies: requirements.txt

MWAA installs Python dependencies from `requirements.txt` in S3.

Rules:

- Pin package versions with `==`.
- Include the correct Airflow constraints file for the MWAA Airflow/Python version.
- Do not add packages already present in the MWAA base image unless a different version is explicitly required.
- Avoid unpinned transitive dependency drift.
- Keep dependency size small; large installs slow startup and can time out.
- Test dependency combinations locally before uploading.

MWAA update behavior:

- Uploading a new `requirements.txt` object is not enough when MWAA tracks an object version.
- The environment must be updated to reference the new S3 object version.
- Dependency installation failures appear in CloudWatch logs, including `requirements_install_ip` streams.

Common failure modes:

- Missing or wrong constraints file
- Package not compatible with MWAA Python version
- Provider version conflict
- Private package index inaccessible from the MWAA network mode
- Native/system dependency needed by a Python package

## Plugins: plugins.zip

Use `plugins.zip` for custom Airflow plugins, hooks, operators, and sensors when they must be installed as plugins rather than normal DAG-side modules.

Rules:

- Prefer simple DAG-side shared modules first when plugin mechanics are unnecessary.
- Test plugins locally with `aws-mwaa-docker-images`.
- Zip the contents correctly; avoid an extra top-level directory unless that is intentional for imports.
- Upload the zip to S3 and update the MWAA environment to the new object version.
- Check scheduler and webserver logs after plugin changes.

Use custom plugins sparingly. Many custom operators can live as normal Python modules under a shared DAG library and be ignored by scheduler discovery with `.airflowignore` where appropriate.

## Local Testing With aws-mwaa-docker-images

Use the AWS MWAA local runner when:

- validating `requirements.txt`
- validating `plugins.zip`
- reproducing MWAA import errors
- checking provider versions
- testing DAG parse behavior against an MWAA-like image

Typical local checks:

```sh
python -m py_compile dags/my_dag.py
pytest
```

Then, if the repo includes the MWAA local runner:

```sh
./mwaa-local-env test-requirements
./mwaa-local-env test-startup-script
./mwaa-local-env start
```

Command names vary by local-runner version. Inspect the repo's README or scripts before running.

## Security

Airflow is not a strict multi-tenant boundary. In MWAA, a DAG author may be able to access:

- the MWAA execution role permissions
- Airflow Connections and Variables available to the environment
- metadata database-visible data
- network destinations reachable from MWAA

Security review points:

- DAG authors should not get direct uncontrolled access to the production S3 `dags/` bucket.
- Prefer CI/CD with validation gates for DAG upload.
- Use least-privilege execution role permissions.
- Do not embed secrets in DAG code, requirements, plugins, logs, or XCom.
- Avoid logging connection URIs, STS credentials, tokens, request headers, or raw payloads with secrets.
- For team isolation, use separate MWAA environments when teams should not share execution role and Airflow metadata access.

## AWS Integration Patterns

Prefer AWS-aware Airflow providers/operators when they give clearer retries, logging, and connection handling. Use boto3 directly inside tasks when:

- the provider operator does not support the needed API
- the call is small and simple
- idempotency and retry behavior are explicit

When using boto3:

- Instantiate clients inside task functions, not at DAG parse time.
- Let MWAA use the execution role unless there is a clear reason for another credential path.
- Use deterministic idempotency tokens or object keys.
- Fail with actionable exceptions; include resource identifiers, not secrets.

## Troubleshooting Checklist

For DAG not appearing:

1. Confirm the file is under the configured S3 `dags/` prefix.
2. Confirm S3 object uploaded successfully.
3. Wait for S3 sync and scheduler parse interval.
4. Check scheduler CloudWatch logs for import errors.
5. Run local `DagBag` import test.

For import errors:

1. Check missing dependency in scheduler logs.
2. Check provider/Python/Airflow version mismatch.
3. Check top-level imports and side effects.
4. Check `plugins.zip` import path and zip structure.
5. Check `.airflowignore` is not excluding needed DAG files.

For dependency update failures:

1. Check `requirements_install_ip` CloudWatch logs.
2. Verify constraints file matches MWAA Airflow and Python versions.
3. Pin all added packages.
4. Test locally with MWAA local runner.
5. Check network access to PyPI or private package index.

For permission failures:

1. Identify the exact AWS API and resource ARN.
2. Check MWAA execution role policy.
3. Check KMS, bucket, queue, or database resource policies.
4. Check VPC endpoints/security groups if using private access.

## Official Docs To Re-check

Use official docs when exact behavior matters:

- Airflow best practices: https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html
- Airflow dynamic DAG generation: https://airflow.apache.org/docs/apache-airflow/stable/howto/dynamic-dag-generation.html
- MWAA DAG deployment: https://docs.aws.amazon.com/mwaa/latest/userguide/configuring-dag-folder.html
- MWAA dependencies: https://docs.aws.amazon.com/mwaa/latest/userguide/working-dags-dependencies.html
- MWAA plugins: https://docs.aws.amazon.com/mwaa/latest/userguide/configuring-dag-import-plugins.html
- MWAA security: https://docs.aws.amazon.com/mwaa/latest/userguide/security-best-practices.html
