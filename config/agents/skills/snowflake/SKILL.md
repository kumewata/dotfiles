---
name: snowflake
description: |
  Snowflake Expert Engineer Skill - Comprehensive guide for Snowflake SQL queries, data investigation, performance analysis, and Snowflake CLI (snow) usage
  Use when:
  - Running snow CLI commands (sql, object, connection)
  - Writing Snowflake SQL queries (functions, JOINs, CTEs, window functions)
  - Investigating data in Snowflake warehouses
  - Analyzing query performance (Query Profile, QUERY_HISTORY)
  - Using Snowflake MCP for agentic data operations
---

# Snowflake Expert Engineer Skill

This skill provides a comprehensive guide for Snowflake data investigation and development.

## 1. Snowflake CLI (snow) Basics

### 1.1. Connection Management

```sh
# List configured connections
snow connection list

# Test connection
snow connection test --connection <connection_name>

# Set default connection
snow connection set-default <connection_name>
```

Connection config is stored in `~/Library/Application\ Support/snowflake/config.toml`（macOS）または `~/.snowflake/config.toml`（Linux）:

```toml
[connections.default]
account = "<account_identifier>"
user = "<username>"
authenticator = "externalbrowser"  # SSO/browser auth
warehouse = "COMPUTE_WH"
database = "MY_DB"
schema = "PUBLIC"
role = "ANALYST"
```

### 1.2. SQL Execution

```sh
# Execute a query
snow sql -q "SELECT * FROM my_table LIMIT 10"

# Execute with specific connection/warehouse/role
snow sql -q "SELECT COUNT(*) FROM my_table" \
  --connection <conn> --warehouse <wh> --role <role>

# Execute from file
snow sql -f query.sql

# Output in CSV format
snow sql -q "SELECT * FROM my_table LIMIT 10" --format csv
```

### 1.3. Object Management

```sh
# List databases
snow object list database

# List schemas in a database
snow object list schema --database MY_DB

# List tables in a schema
snow object list table --database MY_DB --schema PUBLIC

# Describe a table
snow object describe table MY_DB.PUBLIC.MY_TABLE
```

### 1.4. Stage Operations

```sh
# List files in a stage
snow stage list-files @my_stage

# Upload file to stage
snow stage copy local_file.csv @my_stage

# Download file from stage
snow stage copy @my_stage/file.csv ./local_dir/
```

## 2. Snowflake SQL Basic Syntax

### 2.1. SELECT Statement

```sql
SELECT
  column1,
  column2,
  COUNT(*) AS count
FROM my_db.my_schema.my_table
WHERE created_at >= '2024-01-01'
GROUP BY column1, column2
HAVING COUNT(*) > 10
ORDER BY count DESC
LIMIT 100;
```

### 2.2. Common Functions

```sql
-- String functions
CONCAT(str1, str2)
LOWER(str), UPPER(str)
TRIM(str), LTRIM(str), RTRIM(str)
SUBSTR(str, start, length)
REGEXP_LIKE(str, 'pattern')
REGEXP_SUBSTR(str, 'pattern')
SPLIT_PART(str, delimiter, part_number)
PARSE_JSON(json_str)

-- Date/time functions
CURRENT_DATE(), CURRENT_TIMESTAMP()
TO_DATE(str, 'YYYY-MM-DD')
TO_TIMESTAMP(str, 'YYYY-MM-DD HH24:MI:SS')
DATEADD(DAY, 1, date)
DATEDIFF(DAY, date1, date2)
DATE_TRUNC('MONTH', date)
EXTRACT(YEAR FROM date)
LAST_DAY(date)

-- Aggregate functions
COUNT(*), COUNT(DISTINCT column)
SUM(column), AVG(column)
MIN(column), MAX(column)
ARRAY_AGG(column)
LISTAGG(column, ',')
MEDIAN(column), PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY col)

-- Window functions
ROW_NUMBER() OVER (PARTITION BY col ORDER BY col2)
RANK() OVER (ORDER BY col DESC)
DENSE_RANK() OVER (ORDER BY col DESC)
LAG(col, 1) OVER (ORDER BY date)
LEAD(col, 1) OVER (ORDER BY date)
SUM(col) OVER (PARTITION BY category ORDER BY date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
```

### 2.3. JOIN Syntax

```sql
-- INNER JOIN
SELECT a.*, b.column
FROM table_a AS a
INNER JOIN table_b AS b
  ON a.id = b.id;

-- LEFT JOIN
SELECT a.*, b.column
FROM table_a AS a
LEFT JOIN table_b AS b
  ON a.id = b.id;

-- LATERAL FLATTEN (array/JSON expansion, Snowflake-specific)
SELECT
  t.id,
  f.value::STRING AS element
FROM my_table AS t,
LATERAL FLATTEN(input => t.json_array_column) AS f;
```

### 2.4. CTE (Common Table Expressions)

```sql
WITH
  base_data AS (
    SELECT *
    FROM my_table
    WHERE date >= '2024-01-01'
  ),
  aggregated AS (
    SELECT
      category,
      COUNT(*) AS count
    FROM base_data
    GROUP BY category
  )
SELECT *
FROM aggregated
ORDER BY count DESC;
```

### 2.5. Semi-Structured Data (VARIANT)

```sql
-- Access JSON fields
SELECT
  raw_json:user:name::STRING AS user_name,
  raw_json:user:age::NUMBER AS user_age,
  raw_json:tags[0]::STRING AS first_tag
FROM events;

-- FLATTEN nested arrays
SELECT
  e.id,
  f.value:item_id::STRING AS item_id,
  f.value:quantity::NUMBER AS quantity
FROM events AS e,
LATERAL FLATTEN(input => e.raw_json:items) AS f;

-- OBJECT_KEYS / TYPEOF
SELECT OBJECT_KEYS(raw_json) FROM events LIMIT 1;
SELECT TYPEOF(raw_json:field) FROM events LIMIT 1;
```

## 3. Data Investigation Patterns

### 3.1. Table Profiling

```sql
-- Row count and basic stats
SELECT
  COUNT(*) AS row_count,
  MIN(created_at) AS earliest,
  MAX(created_at) AS latest,
  COUNT(DISTINCT user_id) AS unique_users
FROM my_table;

-- Column null rate and cardinality
SELECT
  COUNT(*) AS total,
  COUNT(column_name) AS non_null,
  COUNT(*) - COUNT(column_name) AS null_count,
  ROUND(100.0 * (COUNT(*) - COUNT(column_name)) / COUNT(*), 2) AS null_pct,
  COUNT(DISTINCT column_name) AS distinct_count
FROM my_table;

-- Value distribution (top N)
SELECT column_name, COUNT(*) AS cnt
FROM my_table
GROUP BY column_name
ORDER BY cnt DESC
LIMIT 20;
```

### 3.2. Time-Series Analysis

```sql
-- Daily trend
SELECT
  DATE_TRUNC('DAY', created_at) AS date,
  COUNT(*) AS daily_count,
  COUNT(DISTINCT user_id) AS daily_users
FROM my_table
WHERE created_at >= DATEADD(DAY, -30, CURRENT_DATE())
GROUP BY 1
ORDER BY 1;

-- Week-over-week comparison
WITH weekly AS (
  SELECT
    DATE_TRUNC('WEEK', created_at) AS week,
    COUNT(*) AS cnt
  FROM my_table
  GROUP BY 1
)
SELECT
  week,
  cnt,
  LAG(cnt) OVER (ORDER BY week) AS prev_week,
  ROUND(100.0 * (cnt - LAG(cnt) OVER (ORDER BY week)) / NULLIF(LAG(cnt) OVER (ORDER BY week), 0), 1) AS wow_pct
FROM weekly
ORDER BY week DESC;
```

### 3.3. Data Quality Checks

```sql
-- Duplicate detection
SELECT id, COUNT(*) AS dup_count
FROM my_table
GROUP BY id
HAVING COUNT(*) > 1;

-- Orphan records (referential integrity)
SELECT a.id
FROM child_table AS a
LEFT JOIN parent_table AS b ON a.parent_id = b.id
WHERE b.id IS NULL;

-- Schema change detection (compare INFORMATION_SCHEMA)
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'MY_SCHEMA'
  AND table_name = 'MY_TABLE'
ORDER BY ordinal_position;
```

## 4. Performance Analysis

### 4.1. Query History

```sql
-- Recent slow queries
SELECT
  query_id,
  query_text,
  user_name,
  warehouse_name,
  execution_status,
  total_elapsed_time / 1000 AS elapsed_sec,
  bytes_scanned / POWER(1024, 3) AS gb_scanned,
  rows_produced,
  compilation_time / 1000 AS compile_sec,
  execution_time / 1000 AS exec_sec
FROM TABLE(information_schema.query_history(
  DATEADD('HOUR', -24, CURRENT_TIMESTAMP()),
  CURRENT_TIMESTAMP()
))
WHERE execution_status = 'SUCCESS'
ORDER BY total_elapsed_time DESC
LIMIT 20;

-- Query profile operator stats (via MCP or ACCOUNT_USAGE)
SELECT *
FROM TABLE(GET_QUERY_OPERATOR_STATS('<query_id>'));
```

### 4.2. Warehouse Monitoring

```sql
-- Warehouse load history
SELECT
  warehouse_name,
  DATE_TRUNC('HOUR', start_time) AS hour,
  AVG(avg_running) AS avg_running,
  AVG(avg_queued_load) AS avg_queued
FROM TABLE(information_schema.warehouse_load_history(
  DATEADD('DAY', -7, CURRENT_TIMESTAMP()),
  CURRENT_TIMESTAMP()
))
GROUP BY 1, 2
ORDER BY 1, 2;

-- Credit usage
SELECT
  warehouse_name,
  SUM(credits_used) AS total_credits
FROM snowflake.account_usage.warehouse_metering_history
WHERE start_time >= DATEADD(MONTH, -1, CURRENT_DATE())
GROUP BY warehouse_name
ORDER BY total_credits DESC;
```

### 4.3. Optimization Tips

```sql
-- Check clustering depth (for clustered tables)
SELECT SYSTEM$CLUSTERING_INFORMATION('my_db.my_schema.my_table', '(cluster_col)');

-- Identify full table scans
SELECT
  query_id,
  query_text,
  partitions_scanned,
  partitions_total,
  ROUND(100.0 * partitions_scanned / NULLIF(partitions_total, 0), 1) AS scan_pct
FROM snowflake.account_usage.query_history
WHERE start_time >= DATEADD(DAY, -1, CURRENT_DATE())
  AND partitions_total > 0
  AND partitions_scanned = partitions_total
ORDER BY partitions_total DESC
LIMIT 20;
```

## 5. Access Control

### 5.1. Role Hierarchy

```sql
-- Show current role and available roles
SELECT CURRENT_ROLE();
SHOW ROLES;

-- Show grants on a table
SHOW GRANTS ON TABLE my_db.my_schema.my_table;

-- Show grants to a role
SHOW GRANTS TO ROLE analyst_role;
```

### 5.2. Common RBAC Patterns

```sql
-- Grant read access on schema
GRANT USAGE ON DATABASE my_db TO ROLE analyst_role;
GRANT USAGE ON SCHEMA my_db.my_schema TO ROLE analyst_role;
GRANT SELECT ON ALL TABLES IN SCHEMA my_db.my_schema TO ROLE analyst_role;
GRANT SELECT ON FUTURE TABLES IN SCHEMA my_db.my_schema TO ROLE analyst_role;
```

## 6. Claude Code / Codex との連携

snow CLI を Bash ツール経由で使用してデータ調査を行う。

### 6.1. 調査ワークフロー

```sh
# 1. 接続確認
snow connection test

# 2. テーブル一覧の確認
snow object list table --database MY_DB --schema MY_SCHEMA

# 3. テーブルのスキーマ確認
snow object describe table MY_DB.MY_SCHEMA.MY_TABLE

# 4. データ調査クエリの実行
snow sql -q "SELECT * FROM my_table LIMIT 10"

# 5. 結果をCSVで取得（後続分析用）
snow sql -q "SELECT * FROM my_table WHERE condition" --format csv
```

### 6.2. Tips

- `snow object list/describe`, `snow connection list/test` は自動許可される
- `snow sql`（クエリ実行）は都度確認が必要
- 変更系（`snow stage copy`, `snow object create/drop`）は禁止されている
- 大量データの取得は `LIMIT` を付けるか `--format csv` でファイルに出力
- 接続設定は `~/Library/Application\ Support/snowflake/config.toml`（macOS）または `~/.snowflake/config.toml`（Linux） で管理

## 7. Reference Links

- Official docs: <https://docs.snowflake.com/ja/>
- SQL reference: <https://docs.snowflake.com/ja/sql-reference>
- Snowflake CLI: <https://docs.snowflake.com/ja/developer-guide/snowflake-cli/index>
- Query Profile: <https://docs.snowflake.com/ja/user-guide/ui-query-profile>
- Snowflake MCP: <https://docs.snowflake.com/en/user-guide/snowflake-mcp>
- Pricing: <https://www.snowflake.com/pricing/>
