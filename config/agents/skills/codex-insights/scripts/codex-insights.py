#!/usr/bin/env python3
"""Generate private monthly Codex workflow reports from local session JSONL."""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import html
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 4
WARNING_SAMPLE_LIMIT = 100
TOP_LIMIT = 12
LONG_TAIL_TOOL_CALL_THRESHOLD = 10
PROCESS_EXIT_RE = re.compile(r"Process exited with code (-?\d+)")

TOKEN_MAP = {
    "input_tokens": "input",
    "cached_input_tokens": "cached_input",
    "output_tokens": "output",
    "reasoning_output_tokens": "reasoning_output",
    "total_tokens": "total",
}

SECRET_PATTERNS = [
    re.compile(r"\bsk-[A-Za-z0-9_-]{20,}\b"),
    re.compile(r"\b(?:ghp|gho|ghu|ghs|github_pat)_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\b[A-Za-z0-9+/]{32,}={0,2}\b"),
    re.compile(
        r"(?i)\b(api[_-]?key|token|secret|password|authorization)"
        r"(\s*[:=]\s*[\"']?)[^\"'\s]{8,}"
    ),
]

SENSITIVE_PATH_PARTS = {
    ".env",
    "daily",
    "key",
    "keys",
    "pem",
    "secret",
    "secrets",
    "token",
    "tokens",
    "work",
}

WORK_AREA_RULES = [
    ("code edit", [r"\bapply_patch\b", r"\bfix\b", r"\bimplement\b", r"\brefactor\b", r"実装", r"修正"]),
    ("review", [r"\breview\b", r"\bdiff\b", r"レビュー", r"確認して"]),
    ("github", [r"\bgithub\b", r"\bgh\b", r"\bPR\b", r"pull request", r"issue", r"GitHub"]),
    ("slack", [r"\bslack\b", r"Slack"]),
    ("calendar", [r"\bcalendar\b", r"予定", r"会議", r"空き時間"]),
    ("steering", [r"\bsteering\b", r"ステアリング", r"tasklist"]),
    ("research", [r"\bresearch\b", r"\bsearch\b", r"調査", r"検索"]),
    ("data investigation", [r"\bsql\b", r"\bdbt\b", r"\bdatabricks\b", r"\bbigquery\b", r"\bsnowflake\b", r"データ"]),
    ("nix/dotfiles", [r"\bnix\b", r"\bhome manager\b", r"\bdotfiles\b", r"\bflake\b"]),
    ("docs", [r"\bdoc\b", r"\breadme\b", r"\bAGENTS\.md\b", r"ドキュメント", r"文書"]),
]

FRICTION_RULES = [
    ("date/timezone", [r"\btimezone\b", r"\btime zone\b", r"\bcurrent date\b", r"\btoday\b", r"\byesterday\b", r"\btomorrow\b", r"日付", r"タイムゾーン"]),
    ("wrong repo/worktree", [r"\bwrong repo\b", r"\bwrong repository\b", r"\bworktree\b", r"リポジトリ.*違", r"別リポジトリ"]),
    ("sandbox/approval/auth", [r"\bsandbox\b", r"\bapproval\b", r"\brequire_escalated\b", r"\bpermission denied\b", r"\bauth\b", r"\bauthentication\b", r"権限", r"認証", r"承認"]),
    ("user correction", [r"\bactually\b", r"\bnot that\b", r"\bcorrection\b", r"違います", r"違う", r"修正して", r"訂正"]),
    ("skill-selection miss", [r"\bskill-selection\b", r"\bskill miss\b", r"\btrigger.*skill\b", r"スキル.*発動しな", r"スキル.*選択"]),
]

TOOL_ERROR_RULES = [
    ("sandbox/permission", [r"\bpermission denied\b", r"\bsandbox\b", r"\brequire_escalated\b", r"operation not permitted", r"権限", r"承認"]),
    ("auth", [r"\bauth\b", r"\bauthentication\b", r"\bunauthorized\b", r"\bforbidden\b", r"\b403\b", r"認証"]),
    ("missing-command", [r"command not found", r"not found:"]),
    ("network", [r"\bnetwork\b", r"\bdns\b", r"\bconnection\b", r"\btimeout\b"]),
    ("syntax/runtime", [r"\btraceback\b", r"\bsyntaxerror\b", r"\btypeerror\b", r"\bvalueerror\b", r"\berror:\b"]),
    ("nonzero-exit", [r"process exited with code [1-9]", r"exit code [1-9]"]),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a private monthly Codex insights report from local session JSONL.",
    )
    parser.add_argument(
        "--month",
        help="Target calendar month in YYYY-MM. Defaults to the previous complete month.",
    )
    parser.add_argument(
        "--codex-home",
        default=os.environ.get("CODEX_HOME") or str(Path.home() / ".codex"),
        help="Codex home directory. Defaults to $CODEX_HOME or ~/.codex.",
    )
    parser.add_argument(
        "--output-dir",
        default=str(Path.home() / ".local" / "state" / "codex-insights"),
        help="Output directory. Defaults to ~/.local/state/codex-insights.",
    )
    parser.add_argument(
        "--format",
        choices=("markdown", "json", "html"),
        default="markdown",
        help="Stdout format. Files always include Markdown, HTML, and JSON snapshot outputs.",
    )
    parser.add_argument(
        "--qualitative",
        action="store_true",
        help="Add opt-in qualitative guidance generated from aggregate redacted evidence only.",
    )
    return parser.parse_args()


def previous_complete_month(now: dt.datetime | None = None) -> str:
    current = now or dt.datetime.now().astimezone()
    first_this_month = current.date().replace(day=1)
    previous = first_this_month - dt.timedelta(days=1)
    return f"{previous.year:04d}-{previous.month:02d}"


def validate_month(raw: str) -> str:
    if not re.fullmatch(r"\d{4}-\d{2}", raw):
        raise ValueError("--month must be YYYY-MM")
    year, month = raw.split("-")
    month_int = int(month)
    if not 1 <= month_int <= 12:
        raise ValueError("--month month must be between 01 and 12")
    return f"{int(year):04d}-{month_int:02d}"


def month_parts(month: str) -> tuple[int, int]:
    year, mon = month.split("-")
    return int(year), int(mon)


def redact_text(value: str) -> str:
    redacted = value
    redacted = re.sub(r"https?://([^/?#\s]+)[^\s]*", r"https://\1/[redacted-url]", redacted)
    for pattern in SECRET_PATTERNS:
        if pattern.groups >= 2:
            redacted = pattern.sub(r"\1\2[redacted-secret]", redacted)
        else:
            redacted = pattern.sub("[redacted-secret]", redacted)
    return redacted


def shorten_path(path: str | Path) -> str:
    text = str(path)
    home = str(Path.home())
    if text.startswith(home):
        text = "~" + text[len(home) :]
    parts = [part for part in text.split("/") if part]
    lowered = [part.lower() for part in parts]
    for index, part in enumerate(lowered):
        if part in SENSITIVE_PATH_PARTS or any(token in part for token in ("secret", "token", ".env")):
            prefix = "/" if text.startswith("/") else ""
            kept = parts[:index]
            if text.startswith("~"):
                prefix = ""
            return prefix + "/".join(kept + ["[redacted-path]"])
    return redact_text(text)


def normalize_repo_url(raw: str) -> str:
    value = raw.strip()
    value = re.sub(r"[?#].*$", "", value)
    value = re.sub(r"^(https?://)[^/@\s]+@", r"\1", value)
    value = value.removesuffix(".git")
    match = re.match(r"git@[^:]+:([^/]+/[^/]+)$", value)
    if match:
        return match.group(1)
    match = re.match(r"https?://[^/]+/([^/]+/[^/]+)$", value)
    if match:
        return match.group(1)
    return redact_text(value)


def parse_timestamp(value: Any, local_tz: dt.tzinfo) -> dt.datetime | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return dt.datetime.fromtimestamp(value, tz=dt.timezone.utc)
    if not isinstance(value, str):
        return None
    raw = value.strip()
    if not raw:
        return None
    if raw.endswith("Z"):
        raw = raw[:-1] + "+00:00"
    try:
        parsed = dt.datetime.fromisoformat(raw)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=local_tz)
    return parsed


def event_timestamp(event: dict[str, Any], path: Path, local_tz: dt.tzinfo) -> tuple[dt.datetime, bool]:
    payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}
    for value in (event.get("timestamp"), payload.get("timestamp")):
        parsed = parse_timestamp(value, local_tz)
        if parsed is not None:
            return parsed, False
    stat = path.stat()
    return dt.datetime.fromtimestamp(stat.st_mtime, tz=local_tz), True


def is_in_month(timestamp: dt.datetime, target_month: str, local_tz: dt.tzinfo) -> bool:
    year, month = month_parts(target_month)
    local = timestamp.astimezone(local_tz)
    return local.year == year and local.month == month


def iter_session_files(codex_home: Path) -> list[Path]:
    sessions_dir = codex_home / "sessions"
    if not sessions_dir.exists():
        return []
    return sorted(sessions_dir.rglob("*.jsonl"))


def discover_known_skills() -> set[str]:
    candidates = [
        Path.cwd() / "config" / "agents" / "skills",
        Path.home() / ".agents" / "skills",
        Path.home() / ".codex" / "skills",
        Path.home() / ".claude" / "skills",
    ]
    script_path = Path(__file__)
    candidates.append(script_path.parent.parent.parent)
    try:
        candidates.append(script_path.resolve().parent.parent.parent)
    except OSError:
        pass

    names: set[str] = set()
    for root in candidates:
        if not root.is_dir():
            continue
        try:
            children = list(root.iterdir())
        except OSError:
            continue
        for child in children:
            if not child.is_dir():
                continue
            name = child.name
            if not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,63}", name):
                continue
            if (child / "SKILL.md").exists():
                names.add(name)
    return names


def payload_of(event: dict[str, Any]) -> dict[str, Any]:
    payload = event.get("payload")
    if isinstance(payload, dict):
        return payload
    for key in ("msg", "message", "event", "item"):
        value = event.get(key)
        if isinstance(value, dict):
            return value
    return event


def extract_content_text(payload: dict[str, Any]) -> list[str]:
    texts: list[str] = []
    content = payload.get("content")
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and isinstance(item.get("text"), str):
                texts.append(item["text"])
    for key in ("message", "text", "output", "arguments"):
        value = payload.get(key)
        if isinstance(value, str):
            texts.append(value)
    return texts


def extract_usage(payload: dict[str, Any]) -> dict[str, int] | None:
    candidates: list[Any] = []
    info = payload.get("info")
    if isinstance(info, dict):
        candidates.append(info.get("last_token_usage"))
    candidates.append(payload.get("usage"))
    for candidate in candidates:
        if not isinstance(candidate, dict):
            continue
        out: dict[str, int] = {}
        for raw_key, normalized in TOKEN_MAP.items():
            value = candidate.get(raw_key)
            if isinstance(value, int):
                out[normalized] = value
        if out:
            return out
    return None


def add_counter(counter: collections.Counter[str], label: str | None, amount: int = 1) -> None:
    if not label:
        return
    clean = redact_text(str(label).strip())
    if clean:
        counter[clean] += amount


def strip_fenced_code_blocks(text: str) -> str:
    text = re.sub(r"```.*?```", "", text, flags=re.DOTALL)
    text = re.sub(r"~~~.*?~~~", "", text, flags=re.DOTALL)
    return text


def skill_mentions_from_user_text(text: str, known_skills: set[str]) -> list[str]:
    searchable = strip_fenced_code_blocks(text)
    mentions = []
    for match in re.finditer(r"\$([A-Za-z0-9][A-Za-z0-9_-]{1,63})", searchable):
        name = match.group(1).lower().replace("_", "-")
        if name in known_skills:
            mentions.append(name)
    return mentions


def skill_declarations_from_assistant_text(text: str, known_skills: set[str]) -> list[str]:
    lowered = text.lower()
    if "skill" not in lowered and "スキル" not in text:
        return []
    if not any(marker in lowered for marker in ("use", "using")) and "使" not in text:
        return []
    mentions: set[str] = set()
    for match in re.finditer(r"`?([a-z0-9][a-z0-9-]{1,63})`?\s*(?:skill|スキル)", lowered):
        name = match.group(1)
        if name in known_skills:
            mentions.add(name)
    for match in re.finditer(r"(?:using|use)\s+(?:the\s+)?`?([a-z0-9][a-z0-9-]{1,63})`?", lowered):
        name = match.group(1)
        if name in known_skills:
            mentions.add(name)
    return sorted(mentions)


def classify_tool_error(text: str) -> list[str]:
    return classify_by_rules(text, TOOL_ERROR_RULES)


def call_key(session_label: str, call_id: Any) -> str | None:
    if not isinstance(call_id, str) or not call_id:
        return None
    return f"{session_label}:{call_id}"


def classify_by_rules(text: str, rules: list[tuple[str, list[str]]]) -> list[str]:
    labels = []
    for label, patterns in rules:
        for pattern in patterns:
            if re.search(pattern, text, re.IGNORECASE):
                labels.append(label)
                break
    return labels


def top_dict(counter: collections.Counter[str], limit: int = TOP_LIMIT) -> dict[str, int]:
    return {key: value for key, value in counter.most_common(limit)}


def add_warning(
    warnings: list[dict[str, Any]],
    warning_counts: collections.Counter[str],
    kind: str,
    path: Path,
    line_number: int | None,
    detail: str,
) -> None:
    warning_counts[kind] += 1
    if len(warnings) >= WARNING_SAMPLE_LIMIT:
        return
    warnings.append(
        {
            "kind": kind,
            "path": shorten_path(path),
            "line": line_number,
            "detail": redact_text(detail),
        }
    )


def new_task_record(
    session_label: str,
    turn_id: str,
    timestamp: dt.datetime,
    cwd: str | None,
    repo: str | None,
    explicit_start: bool,
) -> dict[str, Any]:
    return {
        "session_label": session_label,
        "turn_id": turn_id,
        "started_at": timestamp,
        "ended_at": None,
        "status": "in_progress",
        "explicit_start": explicit_start,
        "cwd": cwd,
        "repo": repo,
        "tool_calls": 0,
        "exec_calls": 0,
        "exec_successes": 0,
        "exec_failures": 0,
        "exec_recovered_failures": 0,
        "pending_exec_failures": 0,
        "patch_attempts": 0,
        "patch_successes": 0,
        "patch_failures": 0,
        "patch_recovered_failures": 0,
        "pending_patch_failures": 0,
        "update_plan_calls": 0,
        "reasoning_events": 0,
        "context_compactions": 0,
    }


def task_key(session_label: str, turn_id: Any) -> str | None:
    if not isinstance(turn_id, str) or not turn_id:
        return None
    return f"{session_label}:{turn_id}"


def get_or_create_task(
    tasks: dict[str, dict[str, Any]],
    session_label: str,
    turn_id: Any,
    timestamp: dt.datetime,
    cwd: str | None,
    repo: str | None,
    explicit_start: bool = False,
) -> dict[str, Any] | None:
    key = task_key(session_label, turn_id)
    if key is None:
        return None
    if key not in tasks:
        tasks[key] = new_task_record(session_label, str(turn_id), timestamp, cwd, repo, explicit_start)
    elif explicit_start:
        tasks[key]["explicit_start"] = True
        if tasks[key].get("started_at") is None or timestamp < tasks[key]["started_at"]:
            tasks[key]["started_at"] = timestamp
    if cwd and not tasks[key].get("cwd"):
        tasks[key]["cwd"] = cwd
    if repo and not tasks[key].get("repo"):
        tasks[key]["repo"] = repo
    return tasks[key]


def finish_task(task: dict[str, Any] | None, status: str, timestamp: dt.datetime) -> None:
    if task is None:
        return
    if task.get("status") != "in_progress":
        return
    task["status"] = status
    task["ended_at"] = timestamp


def record_task_tool_call(task: dict[str, Any] | None, tool_name: str) -> None:
    if task is None:
        return
    task["tool_calls"] += 1
    if tool_name == "update_plan" or tool_name.endswith(".update_plan"):
        task["update_plan_calls"] += 1


def record_exec_outcome(task: dict[str, Any] | None, exit_code: int) -> None:
    if task is None:
        return
    task["exec_calls"] += 1
    if exit_code == 0:
        task["exec_successes"] += 1
        if task["pending_exec_failures"]:
            task["exec_recovered_failures"] += task["pending_exec_failures"]
            task["pending_exec_failures"] = 0
        return
    task["exec_failures"] += 1
    task["pending_exec_failures"] += 1


def record_patch_outcome(task: dict[str, Any] | None, success: bool) -> None:
    if task is None:
        return
    task["patch_attempts"] += 1
    if success:
        task["patch_successes"] += 1
        if task["pending_patch_failures"]:
            task["patch_recovered_failures"] += task["pending_patch_failures"]
            task["pending_patch_failures"] = 0
        return
    task["patch_failures"] += 1
    task["pending_patch_failures"] += 1


def median(values: list[int | float]) -> int | float:
    if not values:
        return 0
    ordered = sorted(values)
    midpoint = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[midpoint]
    return round((ordered[midpoint - 1] + ordered[midpoint]) / 2, 2)


def duration_seconds(task: dict[str, Any]) -> int:
    started_at = task.get("started_at")
    ended_at = task.get("ended_at")
    if not isinstance(started_at, dt.datetime) or not isinstance(ended_at, dt.datetime):
        return 0
    return max(0, int((ended_at - started_at).total_seconds()))


def short_turn_id(turn_id: Any) -> str:
    if not isinstance(turn_id, str):
        return ""
    return turn_id[:8]


def task_example(task: dict[str, Any]) -> dict[str, Any]:
    return {
        "turn_id": short_turn_id(task.get("turn_id")),
        "status": task.get("status", "unknown"),
        "duration_seconds": duration_seconds(task),
        "tool_calls": task.get("tool_calls", 0),
        "exec_failures": task.get("exec_failures", 0),
        "patch_failures": task.get("patch_failures", 0),
        "cwd": task.get("cwd") or "(unknown)",
        "repo": task.get("repo") or "(unknown)",
    }


def summarize_tasks(tasks: dict[str, dict[str, Any]]) -> tuple[dict[str, Any], dict[str, Any], list[str]]:
    records = list(tasks.values())
    for task in records:
        if task.get("status") == "in_progress":
            task["status"] = "incomplete"

    total = len(records)
    completed = sum(1 for task in records if task.get("status") == "completed")
    aborted = sum(1 for task in records if task.get("status") == "aborted")
    incomplete = sum(1 for task in records if task.get("status") == "incomplete")
    durations = [duration_seconds(task) for task in records if duration_seconds(task) > 0]
    tool_counts = [int(task.get("tool_calls", 0)) for task in records]
    long_tail = [
        task
        for task in records
        if int(task.get("tool_calls", 0)) >= LONG_TAIL_TOOL_CALL_THRESHOLD
        or duration_seconds(task) >= 30 * 60
    ]

    aborted_by_cwd: collections.Counter[str] = collections.Counter()
    long_tail_by_cwd: collections.Counter[str] = collections.Counter()
    aborted_by_repo: collections.Counter[str] = collections.Counter()
    long_tail_by_repo: collections.Counter[str] = collections.Counter()
    for task in records:
        cwd = str(task.get("cwd") or "(unknown)")
        repo = str(task.get("repo") or "(unknown)")
        if task.get("status") == "aborted":
            aborted_by_cwd[cwd] += 1
            aborted_by_repo[repo] += 1
        if task in long_tail:
            long_tail_by_cwd[cwd] += 1
            long_tail_by_repo[repo] += 1

    exec_calls = sum(int(task.get("exec_calls", 0)) for task in records)
    exec_successes = sum(int(task.get("exec_successes", 0)) for task in records)
    exec_failures = sum(int(task.get("exec_failures", 0)) for task in records)
    exec_recovered = sum(int(task.get("exec_recovered_failures", 0)) for task in records)
    exec_unrecovered = sum(int(task.get("pending_exec_failures", 0)) for task in records)

    patch_attempts = sum(int(task.get("patch_attempts", 0)) for task in records)
    patch_successes = sum(int(task.get("patch_successes", 0)) for task in records)
    patch_failures = sum(int(task.get("patch_failures", 0)) for task in records)
    patch_recovered = sum(int(task.get("patch_recovered_failures", 0)) for task in records)
    patch_unrecovered = sum(int(task.get("pending_patch_failures", 0)) for task in records)
    context_compactions = sum(int(task.get("context_compactions", 0)) for task in records)

    task_summary = {
        "total": total,
        "completed": completed,
        "aborted": aborted,
        "incomplete": incomplete,
        "completion_rate": safe_pct(completed, total),
        "median_duration_seconds": median(durations),
        "median_tool_calls": median(tool_counts),
        "long_tail_threshold_tool_calls": LONG_TAIL_TOOL_CALL_THRESHOLD,
        "long_tail_tasks": len(long_tail),
        "long_tail_examples": [task_example(task) for task in sorted(long_tail, key=lambda item: (int(item.get("tool_calls", 0)), duration_seconds(item)), reverse=True)[:10]],
        "aborted_examples": [task_example(task) for task in records if task.get("status") == "aborted"][:10],
        "aborted_by_cwd": top_dict(aborted_by_cwd),
        "aborted_by_repo": top_dict(aborted_by_repo),
        "long_tail_by_cwd": top_dict(long_tail_by_cwd),
        "long_tail_by_repo": top_dict(long_tail_by_repo),
    }
    outcome_summary = {
        "exec": {
            "calls": exec_calls,
            "successes": exec_successes,
            "failures": exec_failures,
            "recovered_failures": exec_recovered,
            "unrecovered_failures": exec_unrecovered,
            "failure_rate": safe_pct(exec_failures, exec_calls),
            "recovery_rate": safe_pct(exec_recovered, exec_failures),
        },
        "patch": {
            "attempts": patch_attempts,
            "successes": patch_successes,
            "failures": patch_failures,
            "recovered_failures": patch_recovered,
            "unrecovered_failures": patch_unrecovered,
            "failure_rate": safe_pct(patch_failures, patch_attempts),
            "recovery_rate": safe_pct(patch_recovered, patch_failures),
        },
        "friction_events": {
            "task_aborted": aborted,
            "task_incomplete": incomplete,
            "exec_unrecovered_failure": exec_unrecovered,
            "patch_unrecovered_failure": patch_unrecovered,
            "context_compacted": context_compactions,
        },
    }
    recommendations = build_outcome_recommendations(task_summary, outcome_summary)
    return task_summary, outcome_summary, recommendations


def build_outcome_recommendations(tasks: dict[str, Any], outcomes: dict[str, Any]) -> list[str]:
    recommendations: list[str] = []
    if tasks.get("aborted", 0):
        recommendations.append(
            f"Candidate: inspect aborted tasks first; {tasks['aborted']} of {tasks['total']} tasks ended with turn_aborted."
        )
    if tasks.get("long_tail_tasks", 0):
        recommendations.append(
            f"Candidate: add task preflight/checklists for long-tail work; {tasks['long_tail_tasks']} tasks crossed {tasks['long_tail_threshold_tool_calls']} tool calls or 30 minutes."
        )
    exec_outcome = outcomes.get("exec", {})
    if exec_outcome.get("unrecovered_failures", 0):
        recommendations.append(
            f"Candidate: focus on unrecovered command failures; {exec_outcome['unrecovered_failures']} nonzero exec outcomes had no later successful exec in the same task."
        )
    patch_outcome = outcomes.get("patch", {})
    if patch_outcome.get("failures", 0):
        recommendations.append(
            f"Candidate: review patch application workflow; {patch_outcome['failures']} patch_apply_end failures were detected from structured status."
        )
    if not recommendations:
        recommendations.append("No high-confidence task outcome recommendations were detected from structured events.")
    return recommendations


def build_snapshot(target_month: str, codex_home: Path) -> dict[str, Any]:
    local_tz = dt.datetime.now().astimezone().tzinfo or dt.timezone.utc
    files = iter_session_files(codex_home)
    known_skills = discover_known_skills()
    warnings: list[dict[str, Any]] = []
    warning_counts: collections.Counter[str] = collections.Counter()

    events_seen = 0
    events_in_month = 0
    sessions_in_month: set[str] = set()
    active_days: set[str] = set()
    first_event_at: dt.datetime | None = None
    last_event_at: dt.datetime | None = None
    turn_ids: set[str] = set()
    turn_context_count = 0
    task_started_count = 0
    user_prompts = 0
    fallback_user_prompts = 0
    assistant_messages = 0
    assistant_final_messages = 0
    agent_messages = 0

    tokens = {name: 0 for name in ("input", "cached_input", "output", "reasoning_output", "total")}
    token_events = 0

    cwd_turn_counter: collections.Counter[str] = collections.Counter()
    cwd_session_counter: collections.Counter[str] = collections.Counter()
    repo_counter: collections.Counter[str] = collections.Counter()
    tool_counter: collections.Counter[str] = collections.Counter()
    tool_error_counter: collections.Counter[str] = collections.Counter()
    tool_error_type_counter: collections.Counter[str] = collections.Counter()
    call_tool_names: dict[str, str] = {}
    call_task_keys: dict[str, str] = {}
    outcome_call_ids: set[str] = set()
    active_task_keys: dict[str, str] = {}
    current_cwd_by_session: dict[str, str] = {}
    current_repo_by_session: dict[str, str] = {}
    task_records: dict[str, dict[str, Any]] = {}
    skill_user_counter: collections.Counter[str] = collections.Counter()
    skill_assistant_counter: collections.Counter[str] = collections.Counter()
    work_area_counter: collections.Counter[str] = collections.Counter()
    friction_counter: collections.Counter[str] = collections.Counter()
    user_prompt_hour_counter: collections.Counter[str] = collections.Counter()

    for path in files:
        session_label = str(path)
        try:
            handle = path.open("r", encoding="utf-8", errors="replace")
        except OSError as exc:
            add_warning(warnings, warning_counts, "file-open-error", path, None, str(exc))
            continue

        with handle:
            for line_number, line in enumerate(handle, 1):
                if not line.strip():
                    continue
                events_seen += 1
                try:
                    event = json.loads(line)
                except json.JSONDecodeError as exc:
                    add_warning(warnings, warning_counts, "json-decode-error", path, line_number, exc.msg)
                    continue
                if not isinstance(event, dict):
                    add_warning(warnings, warning_counts, "non-object-event", path, line_number, "event is not a JSON object")
                    continue

                timestamp, used_fallback_timestamp = event_timestamp(event, path, local_tz)
                if not is_in_month(timestamp, target_month, local_tz):
                    continue
                if used_fallback_timestamp:
                    add_warning(warnings, warning_counts, "timestamp-fallback", path, line_number, "used file mtime")

                events_in_month += 1
                sessions_in_month.add(session_label)
                local_timestamp = timestamp.astimezone(local_tz)
                active_days.add(local_timestamp.date().isoformat())
                if first_event_at is None or timestamp < first_event_at:
                    first_event_at = timestamp
                if last_event_at is None or timestamp > last_event_at:
                    last_event_at = timestamp
                payload = payload_of(event)
                payload_type = str(payload.get("type") or event.get("type") or "")
                role = str(payload.get("role") or "")
                current_cwd = current_cwd_by_session.get(session_label)
                current_repo = current_repo_by_session.get(session_label)

                turn_id = payload.get("turn_id")
                if isinstance(turn_id, str) and turn_id:
                    turn_ids.add(f"{session_label}:{turn_id}")
                if event.get("type") == "turn_context":
                    turn_context_count += 1
                if payload_type == "task_started":
                    task_started_count += 1
                    task = get_or_create_task(
                        task_records,
                        session_label,
                        turn_id,
                        timestamp,
                        current_cwd,
                        current_repo,
                        explicit_start=True,
                    )
                    key = task_key(session_label, turn_id)
                    if task is not None and key is not None:
                        active_task_keys[session_label] = key

                cwd = payload.get("cwd")
                if isinstance(cwd, str):
                    shortened_cwd = shorten_path(cwd)
                    current_cwd_by_session[session_label] = shortened_cwd
                    current_cwd = shortened_cwd
                    if event.get("type") == "turn_context":
                        add_counter(cwd_turn_counter, shortened_cwd)
                    elif event.get("type") == "session_meta":
                        add_counter(cwd_session_counter, shortened_cwd)

                git = payload.get("git")
                if isinstance(git, dict) and isinstance(git.get("repository_url"), str):
                    current_repo = normalize_repo_url(git["repository_url"])
                    current_repo_by_session[session_label] = current_repo
                    add_counter(repo_counter, current_repo)

                event_task: dict[str, Any] | None = None
                if isinstance(turn_id, str) and turn_id:
                    event_task = get_or_create_task(task_records, session_label, turn_id, timestamp, current_cwd, current_repo)
                else:
                    active_key = active_task_keys.get(session_label)
                    if active_key:
                        event_task = task_records.get(active_key)

                if payload_type in {"function_call", "custom_tool_call"}:
                    tool_name = payload.get("name")
                    normalized_tool_name = str(tool_name) if tool_name else payload_type
                    add_counter(tool_counter, normalized_tool_name)
                    record_task_tool_call(event_task, normalized_tool_name)
                    key = call_key(session_label, payload.get("call_id"))
                    if key:
                        call_tool_names[key] = normalized_tool_name
                        task_record_key = task_key(session_label, turn_id)
                        if task_record_key is None:
                            task_record_key = active_task_keys.get(session_label)
                        if task_record_key:
                            call_task_keys[key] = task_record_key
                elif payload_type == "web_search_call":
                    action = payload.get("action")
                    action_type = action.get("type") if isinstance(action, dict) else None
                    add_counter(tool_counter, f"web.{action_type}" if action_type else "web_search_call")
                    record_task_tool_call(event_task, "web_search_call")
                elif payload_type == "exec_command_end":
                    key = call_key(session_label, payload.get("call_id"))
                    exit_code = payload.get("exit_code")
                    task_for_call = event_task
                    if task_for_call is None and key:
                        task_for_call = task_records.get(call_task_keys.get(key, ""))
                    if key and isinstance(exit_code, int) and key not in outcome_call_ids:
                        outcome_call_ids.add(key)
                        record_exec_outcome(task_for_call, exit_code)
                        if exit_code != 0:
                            tool_name = call_tool_names.get(key, "exec_command")
                            add_counter(tool_error_counter, tool_name)
                            tool_error_type_counter["nonzero-exit"] += 1
                elif payload_type == "patch_apply_end":
                    key = call_key(session_label, payload.get("call_id"))
                    task_for_call = event_task
                    if task_for_call is None and key:
                        task_for_call = task_records.get(call_task_keys.get(key, ""))
                    success = payload.get("success")
                    if isinstance(success, bool):
                        record_patch_outcome(task_for_call, success)
                        if key:
                            outcome_call_ids.add(key)
                        if not success:
                            status = str(payload.get("status") or "failed")
                            add_counter(tool_error_counter, "apply_patch")
                            tool_error_type_counter[f"patch-apply-{status}"] += 1
                elif payload_type == "task_complete":
                    finish_task(event_task, "completed", timestamp)
                    if isinstance(turn_id, str) and active_task_keys.get(session_label) == task_key(session_label, turn_id):
                        active_task_keys.pop(session_label, None)
                elif payload_type == "turn_aborted":
                    finish_task(event_task, "aborted", timestamp)
                    if isinstance(turn_id, str) and active_task_keys.get(session_label) == task_key(session_label, turn_id):
                        active_task_keys.pop(session_label, None)
                    elif turn_id is None:
                        active_task_keys.pop(session_label, None)
                elif payload_type in {"reasoning", "agent_reasoning"}:
                    if event_task is not None:
                        event_task["reasoning_events"] += 1
                elif payload_type in {"context_compacted", "compacted"}:
                    if event_task is not None:
                        event_task["context_compactions"] += 1

                usage = extract_usage(payload)
                if usage is not None:
                    token_events += 1
                    for key, value in usage.items():
                        tokens[key] += value

                texts = extract_content_text(payload)
                if payload_type == "message" and role == "user":
                    user_prompts += 1
                    user_prompt_hour_counter[f"{local_timestamp.hour:02d}"] += 1
                    joined_text = "\n".join(texts)
                    classification_text = strip_fenced_code_blocks(joined_text)
                    for skill in set(skill_mentions_from_user_text(joined_text, known_skills)):
                        add_counter(skill_user_counter, skill)
                    areas = classify_by_rules(classification_text, WORK_AREA_RULES)
                    if areas:
                        for area in areas:
                            work_area_counter[area] += 1
                    else:
                        work_area_counter["general"] += 1
                    for friction in classify_by_rules(classification_text, FRICTION_RULES):
                        friction_counter[friction] += 1
                elif payload_type == "user_message":
                    fallback_user_prompts += 1
                    if user_prompts == 0:
                        user_prompt_hour_counter[f"{local_timestamp.hour:02d}"] += 1
                        joined_text = "\n".join(texts)
                        classification_text = strip_fenced_code_blocks(joined_text)
                        for skill in set(skill_mentions_from_user_text(joined_text, known_skills)):
                            add_counter(skill_user_counter, skill)
                        for friction in classify_by_rules(classification_text, FRICTION_RULES):
                            friction_counter[friction] += 1
                elif payload_type == "message" and role == "assistant":
                    assistant_messages += 1
                    assistant_final_messages += 1
                    joined_text = "\n".join(texts)
                    for skill in set(skill_declarations_from_assistant_text(joined_text, known_skills)):
                        add_counter(skill_assistant_counter, skill)
                    for friction in classify_by_rules(joined_text, FRICTION_RULES):
                        friction_counter[friction] += 1
                elif payload_type == "agent_message":
                    assistant_messages += 1
                    agent_messages += 1
                    joined_text = "\n".join(texts)
                    for skill in set(skill_declarations_from_assistant_text(joined_text, known_skills)):
                        add_counter(skill_assistant_counter, skill)
                    for friction in classify_by_rules(joined_text, FRICTION_RULES):
                        friction_counter[friction] += 1
                elif payload_type in {"function_call_output", "custom_tool_call_output"}:
                    output_text = "\n".join(texts)
                    key = call_key(session_label, payload.get("call_id"))
                    exit_match = PROCESS_EXIT_RE.search(output_text)
                    if key and exit_match and key not in outcome_call_ids:
                        outcome_call_ids.add(key)
                        task_for_call = task_records.get(call_task_keys.get(key, ""))
                        exit_code = int(exit_match.group(1))
                        record_exec_outcome(task_for_call, exit_code)
                        if exit_code != 0:
                            tool_name = call_tool_names.get(key, payload_type)
                            add_counter(tool_error_counter, tool_name)
                            tool_error_type_counter["nonzero-exit"] += 1
                    for text in texts:
                        for friction in classify_by_rules(text, FRICTION_RULES):
                            friction_counter[friction] += 1

    effective_user_prompts = user_prompts or fallback_user_prompts
    turns = max(len(turn_ids), turn_context_count, task_started_count, effective_user_prompts)
    cwd_counter = cwd_turn_counter if cwd_turn_counter else cwd_session_counter
    combined_skills = skill_user_counter + skill_assistant_counter

    task_summary, outcome_summary, outcome_recommendations = summarize_tasks(task_records)
    recommendations = outcome_recommendations + build_recommendations(friction_counter, combined_skills)
    generated_at = dt.datetime.now().astimezone().isoformat(timespec="seconds")

    return {
        "schema_version": SCHEMA_VERSION,
        "generated_at": generated_at,
        "target_month": target_month,
        "codex_home": shorten_path(codex_home),
        "source": {
            "session_files_seen": len(files),
            "session_files_in_month": len(sessions_in_month),
            "events_seen": events_seen,
            "events_in_month": events_in_month,
            "active_days": len(active_days),
            "date_range": {
                "first_event_at": first_event_at.astimezone(local_tz).isoformat(timespec="seconds") if first_event_at else None,
                "last_event_at": last_event_at.astimezone(local_tz).isoformat(timespec="seconds") if last_event_at else None,
            },
            "warning_counts": dict(warning_counts),
            "warnings": warnings,
        },
        "usage": {
            "sessions": len(sessions_in_month),
            "turns": turns,
            "turns_estimated": len(turn_ids) == 0,
            "user_prompts": effective_user_prompts,
            "assistant_messages": assistant_messages,
            "assistant_final_messages": assistant_final_messages,
            "agent_messages": agent_messages,
            "tokens": {
                "input": tokens["input"],
                "cached_input": tokens["cached_input"],
                "output": tokens["output"],
                "reasoning_output": tokens["reasoning_output"],
                "total": tokens["total"],
                "unknown": token_events == 0,
                "token_events": token_events,
            },
        },
        "distributions": {
            "cwd": top_dict(cwd_counter),
            "repos": top_dict(repo_counter),
            "tools": top_dict(tool_counter),
            "tool_errors": top_dict(tool_error_counter),
            "tool_error_types": top_dict(tool_error_type_counter),
            "skills": top_dict(combined_skills),
            "skills_from_user_prompts": top_dict(skill_user_counter),
            "skills_from_assistant_declarations": top_dict(skill_assistant_counter),
            "work_areas": top_dict(work_area_counter),
            "friction": top_dict(friction_counter),
            "user_prompts_by_hour": {f"{hour:02d}": user_prompt_hour_counter.get(f"{hour:02d}", 0) for hour in range(24)},
        },
        "tasks": task_summary,
        "outcomes": outcome_summary,
        "recommendations": recommendations,
    }


def build_recommendations(
    friction: collections.Counter[str],
    skills: collections.Counter[str],
) -> list[str]:
    recommendations: list[str] = []
    if friction.get("sandbox/approval/auth", 0) >= 3:
        recommendations.append(
            "Candidate: review AGENTS.md or Codex permission rules for repeated sandbox, approval, or auth blockers."
        )
    if friction.get("date/timezone", 0) >= 2:
        recommendations.append(
            "Candidate: keep date and timezone requirements explicit in repository guidance and date-sensitive skills."
        )
    if friction.get("wrong repo/worktree", 0) >= 1:
        recommendations.append(
            "Candidate: add a repo/worktree confirmation step to skills that run commands across repositories."
        )
    if friction.get("skill-selection miss", 0) >= 1:
        recommendations.append(
            "Candidate: tighten the affected skill description or AGENTS.md skill-selection rule."
        )
    if not skills:
        recommendations.append(
            "Candidate: skill usage was not detected; prefer explicit $skill-name invocation for monthly comparability."
        )
    if not recommendations:
        recommendations.append("No high-confidence AGENTS.md or skill-description changes were detected this month.")
    return recommendations


def top_item(counter: dict[str, int]) -> tuple[str, int]:
    for key, value in counter.items():
        if isinstance(value, int):
            return key, value
    return "none", 0


def confidence_for_signal(count: int, total: int = 0) -> str:
    share = (count / total) if total > 0 else 0.0
    if count >= 10 and (total <= 0 or share >= 0.1):
        return "high"
    if count >= 3:
        return "medium"
    if count > 0:
        return "low"
    return "low"


def evidence_ref(source: str, label: str, count: int, total: int = 0) -> str:
    safe_label = redact_text(label)
    if total > 0:
        return f"{source}.{safe_label}={count} ({safe_pct(count, total)}%)"
    return f"{source}.{safe_label}={count}"


def qualitative_item(text: str, evidence: list[str], confidence: str) -> dict[str, Any]:
    return {
        "text": redact_text(text),
        "confidence": confidence,
        "evidence": [redact_text(item) for item in evidence],
    }


def qualitative_prompt(
    title: str,
    prompt: str,
    evidence: list[str],
    confidence: str,
) -> dict[str, Any]:
    return {
        "title": redact_text(title),
        "prompt": redact_text(prompt),
        "confidence": confidence,
        "evidence": [redact_text(item) for item in evidence],
    }


def build_outcome_qualitative(
    snapshot: dict[str, Any],
    task_summary: dict[str, Any],
    outcome_summary: dict[str, Any],
) -> dict[str, Any]:
    total_tasks = int(task_summary.get("total") or 0)
    completed = int(task_summary.get("completed") or 0)
    aborted = int(task_summary.get("aborted") or 0)
    long_tail = int(task_summary.get("long_tail_tasks") or 0)
    completion_rate = task_summary.get("completion_rate", 0)
    exec_outcome = outcome_summary.get("exec", {})
    patch_outcome = outcome_summary.get("patch", {})
    exec_unrecovered = int(exec_outcome.get("unrecovered_failures") or 0)
    exec_failures = int(exec_outcome.get("failures") or 0)
    exec_recovery_rate = exec_outcome.get("recovery_rate", 0)
    patch_failures = int(patch_outcome.get("failures") or 0)
    patch_recovery_rate = patch_outcome.get("recovery_rate", 0)

    task_evidence = f"tasks.total={total_tasks}; tasks.completed={completed}; tasks.aborted={aborted}; tasks.completion_rate={completion_rate}%"
    long_tail_evidence = f"tasks.long_tail_tasks={long_tail}; threshold_tool_calls={task_summary.get('long_tail_threshold_tool_calls')}; threshold_duration=1800s"
    exec_evidence = f"outcomes.exec.failures={exec_failures}; outcomes.exec.unrecovered_failures={exec_unrecovered}; outcomes.exec.recovery_rate={exec_recovery_rate}%"
    patch_evidence = f"outcomes.patch.failures={patch_failures}; outcomes.patch.recovery_rate={patch_recovery_rate}%"

    confidence = "low"
    if total_tasks >= 50:
        confidence = "high"
    elif total_tasks >= 10:
        confidence = "medium"

    at_a_glance = [
        qualitative_item(
            f"{snapshot['target_month']} has {total_tasks} structured tasks with a {completion_rate}% completion rate.",
            [task_evidence],
            confidence,
        ),
        qualitative_item(
            f"{aborted} tasks ended with turn_aborted and {long_tail} tasks became long-tail.",
            [task_evidence, long_tail_evidence],
            confidence_for_signal(max(aborted, long_tail), total_tasks),
        ),
        qualitative_item(
            f"Structured tool outcomes show {exec_unrecovered} unrecovered exec failures and {patch_failures} patch failures.",
            [exec_evidence, patch_evidence],
            confidence_for_signal(max(exec_unrecovered, patch_failures), total_tasks),
        ),
    ]

    wins = [
        qualitative_item(
            "Task completion is now measured from task_complete / turn_aborted boundaries rather than keyword counts.",
            [task_evidence],
            confidence,
        ),
        qualitative_item(
            "Command failure recovery is now separated from unrecovered failures, so noisy stderr text no longer drives the main error signal.",
            [exec_evidence],
            confidence_for_signal(exec_failures, int(exec_outcome.get("calls") or 0)),
        ),
    ]
    if int(patch_outcome.get("attempts") or 0):
        wins.append(
            qualitative_item(
                "Patch outcomes are now measured from patch_apply_end.success, giving an edit success signal independent of output text.",
                [patch_evidence],
                confidence_for_signal(int(patch_outcome.get("attempts") or 0)),
            )
        )

    friction = [
        qualitative_item(
            f"Long-tail tasks are the first place to inspect because they crossed the configured tool-call or duration threshold {long_tail} times.",
            [long_tail_evidence],
            confidence_for_signal(long_tail, total_tasks),
        ),
        qualitative_item(
            f"Unrecovered exec failures are the clearest deterministic tool friction signal: {exec_unrecovered}.",
            [exec_evidence],
            confidence_for_signal(exec_unrecovered, total_tasks),
        ),
    ]
    if aborted:
        friction.append(
            qualitative_item(
                f"Aborted tasks are a direct outcome signal and should be reviewed before keyword-based friction.",
                [task_evidence],
                confidence_for_signal(aborted, total_tasks),
            )
        )

    copyable_prompts = [
        qualitative_prompt(
            "Long-tail task review",
            "Inspect the longest or highest-tool-call tasks first. For each one, identify the first blocker, the recovery attempt, and the point where a checklist or steering note would have shortened the loop.",
            [long_tail_evidence],
            confidence_for_signal(long_tail, total_tasks),
        ),
        qualitative_prompt(
            "Unrecovered command failure review",
            "Review tasks with unrecovered nonzero exec outcomes. Separate environment/auth/sandbox failures from real implementation failures before changing agent instructions.",
            [exec_evidence],
            confidence_for_signal(exec_unrecovered, total_tasks),
        ),
        qualitative_prompt(
            "Patch outcome review",
            "Review patch_apply_end failures and declined patches. If failures cluster around the same edit pattern, add a precise preflight or smaller-patch rule to the relevant skill.",
            [patch_evidence],
            confidence_for_signal(patch_failures, int(patch_outcome.get("attempts") or 0)),
        ),
    ]

    evidence = [
        {
            "signal": "task_completion",
            "source": "tasks",
            "value": task_evidence,
            "confidence": confidence,
        },
        {
            "signal": "long_tail_tasks",
            "source": "tasks.long_tail_tasks",
            "value": long_tail,
            "count": long_tail,
            "confidence": confidence_for_signal(long_tail, total_tasks),
        },
        {
            "signal": "exec_unrecovered_failures",
            "source": "outcomes.exec",
            "value": exec_unrecovered,
            "count": exec_unrecovered,
            "confidence": confidence_for_signal(exec_unrecovered, total_tasks),
        },
        {
            "signal": "patch_failures",
            "source": "outcomes.patch",
            "value": patch_failures,
            "count": patch_failures,
            "confidence": confidence_for_signal(patch_failures, int(patch_outcome.get("attempts") or 0)),
        },
    ]

    return {
        "enabled": True,
        "mode": "task-outcome-deterministic",
        "confidence": confidence,
        "note": "Generated from structured task/outcome counters and sanitized labels only. No raw transcript excerpts are included.",
        "evidence": evidence,
        "at_a_glance": at_a_glance,
        "wins": wins,
        "friction": friction,
        "copyable_prompts": copyable_prompts,
    }


def build_qualitative(snapshot: dict[str, Any]) -> dict[str, Any]:
    usage = snapshot["usage"]
    source = snapshot["source"]
    distributions = snapshot["distributions"]
    prompts = int(usage.get("user_prompts") or 0)
    sessions = int(usage.get("sessions") or 0)
    turns = int(usage.get("turns") or 0)
    active_days = int(source.get("active_days") or 0)
    warnings_total = sum(source.get("warning_counts", {}).values())
    task_summary = snapshot.get("tasks")
    outcome_summary = snapshot.get("outcomes")
    if isinstance(task_summary, dict) and isinstance(outcome_summary, dict) and task_summary.get("total"):
        return build_outcome_qualitative(snapshot, task_summary, outcome_summary)

    work_label, work_count = top_item(distributions.get("work_areas", {}))
    tool_label, tool_count = top_item(distributions.get("tools", {}))
    skill_label, skill_count = top_item(distributions.get("skills", {}))
    friction_label, friction_count = top_item(distributions.get("friction", {}))
    error_label, error_count = top_item(distributions.get("tool_error_types", {}))

    work_evidence = evidence_ref("distributions.work_areas", work_label, work_count, prompts)
    tool_evidence = evidence_ref("distributions.tools", tool_label, tool_count)
    skill_evidence = evidence_ref("distributions.skills", skill_label, skill_count)
    friction_evidence = evidence_ref("distributions.friction", friction_label, friction_count)
    error_evidence = evidence_ref("distributions.tool_error_types", error_label, error_count)
    usage_evidence = f"usage.prompts={prompts}; usage.sessions={sessions}; usage.turns={turns}; source.active_days={active_days}"
    warning_evidence = f"source.warning_counts.total={warnings_total}"

    at_a_glance = [
        qualitative_item(
            f"{snapshot['target_month']} has {prompts} user prompts across {sessions} sessions and {active_days} active days.",
            [usage_evidence],
            confidence_for_signal(prompts),
        ),
        qualitative_item(
            f"The strongest work signal is `{work_label}`.",
            [work_evidence],
            confidence_for_signal(work_count, prompts),
        ),
        qualitative_item(
            f"The strongest friction signal is `{friction_label}`, with `{error_label}` as the top tool-error type.",
            [friction_evidence, error_evidence],
            confidence_for_signal(max(friction_count, error_count)),
        ),
    ]

    wins = [
        qualitative_item(
            f"Codex appears most useful for `{work_label}` work this month.",
            [work_evidence],
            confidence_for_signal(work_count, prompts),
        ),
        qualitative_item(
            f"`{tool_label}` is the dominant execution surface, which makes tool-specific preflight checks worth optimizing.",
            [tool_evidence],
            confidence_for_signal(tool_count),
        ),
    ]
    if skill_count:
        wins.append(
            qualitative_item(
                f"`{skill_label}` is the most visible skill signal, so its instructions are a good first place to tune repeated workflow behavior.",
                [skill_evidence],
                confidence_for_signal(skill_count),
            )
        )

    friction = [
        qualitative_item(
            f"`{friction_label}` is the clearest recurring friction category.",
            [friction_evidence],
            confidence_for_signal(friction_count),
        ),
        qualitative_item(
            f"`{error_label}` is the clearest tool-error category.",
            [error_evidence],
            confidence_for_signal(error_count),
        ),
    ]
    if warnings_total:
        friction.append(
            qualitative_item(
                "The parser observed warnings while reading session JSONL; inspect the snapshot warning counts before relying on exact totals.",
                [warning_evidence],
                confidence_for_signal(warnings_total),
            )
        )

    copyable_prompts = [
        qualitative_prompt(
            "Evidence-first investigation",
            "Before making a recommendation, gather evidence from code search, relevant logs or query history, and the current repo state. Separate confirmed facts from hypotheses.",
            [work_evidence],
            confidence_for_signal(work_count, prompts),
        ),
        qualitative_prompt(
            "Repo and worktree preflight",
            "Before editing files, confirm the target repo, branch, worktree, writable path, and expected output files. Stop if any value conflicts with the user's request.",
            [friction_evidence],
            confidence_for_signal(friction_count),
        ),
        qualitative_prompt(
            "Permission and auth preflight",
            "Before starting a workflow that depends on external services or writes outside the workspace, run the smallest permission or auth check and report the blocker explicitly.",
            [error_evidence],
            confidence_for_signal(error_count),
        ),
    ]
    if skill_count:
        copyable_prompts.append(
            qualitative_prompt(
                "Skill tuning check",
                "When a workflow repeats, check whether an existing skill should capture the procedure. Tighten the skill description only if the trigger should become durable.",
                [skill_evidence],
                confidence_for_signal(skill_count),
            )
        )

    evidence = [
        {
            "signal": "usage",
            "source": "usage/source",
            "value": usage_evidence,
            "confidence": confidence_for_signal(prompts),
        },
        {
            "signal": "top_work_area",
            "source": "distributions.work_areas",
            "value": redact_text(work_label),
            "count": work_count,
            "confidence": confidence_for_signal(work_count, prompts),
        },
        {
            "signal": "top_tool",
            "source": "distributions.tools",
            "value": redact_text(tool_label),
            "count": tool_count,
            "confidence": confidence_for_signal(tool_count),
        },
        {
            "signal": "top_skill",
            "source": "distributions.skills",
            "value": redact_text(skill_label),
            "count": skill_count,
            "confidence": confidence_for_signal(skill_count),
        },
        {
            "signal": "top_friction",
            "source": "distributions.friction",
            "value": redact_text(friction_label),
            "count": friction_count,
            "confidence": confidence_for_signal(friction_count),
        },
        {
            "signal": "top_tool_error_type",
            "source": "distributions.tool_error_types",
            "value": redact_text(error_label),
            "count": error_count,
            "confidence": confidence_for_signal(error_count),
        },
    ]

    overall_confidence = "low"
    if prompts >= 50 and active_days >= 5:
        overall_confidence = "high"
    elif prompts >= 10 or active_days >= 2:
        overall_confidence = "medium"

    return {
        "enabled": True,
        "mode": "aggregate-redacted-deterministic",
        "confidence": overall_confidence,
        "note": "Generated only from aggregate counters and sanitized labels. No raw transcript excerpts are included.",
        "evidence": evidence,
        "at_a_glance": at_a_glance,
        "wins": wins,
        "friction": friction,
        "copyable_prompts": copyable_prompts,
    }


def format_counter(counter: dict[str, int], empty: str = "No data detected.") -> list[str]:
    if not counter:
        return [empty]
    return [f"- `{key}`: {value}" for key, value in counter.items()]


def format_examples(examples: list[dict[str, Any]], empty: str = "No examples detected.") -> list[str]:
    if not examples:
        return [empty]
    lines = []
    for item in examples:
        lines.append(
            "- "
            f"turn={item.get('turn_id', '')}, "
            f"status={item.get('status', 'unknown')}, "
            f"duration={item.get('duration_seconds', 0)}s, "
            f"tools={item.get('tool_calls', 0)}, "
            f"exec_failures={item.get('exec_failures', 0)}, "
            f"patch_failures={item.get('patch_failures', 0)}, "
            f"cwd=`{item.get('cwd', '(unknown)')}`"
        )
    return lines


def format_int(value: Any) -> str:
    if not isinstance(value, int):
        return str(value)
    return f"{value:,}"


def safe_pct(numerator: int, denominator: int) -> float:
    if denominator <= 0:
        return 0.0
    return round((numerator / denominator) * 100.0, 1)


def max_counter_value(counter: dict[str, int]) -> int:
    values = [value for value in counter.values() if isinstance(value, int)]
    return max(values) if values else 0


def html_text(value: Any) -> str:
    return html.escape(str(value), quote=True)


def render_bar_rows(counter: dict[str, int], max_rows: int = TOP_LIMIT) -> str:
    if not counter:
        return '<p class="empty">No data detected.</p>'
    maximum = max_counter_value(counter) or 1
    rows = []
    for key, value in list(counter.items())[:max_rows]:
        width = max(4.0, (value / maximum) * 100.0) if value else 0.0
        rows.append(
            '<div class="bar-row">'
            f'<div class="bar-label" title="{html_text(key)}">{html_text(key)}</div>'
            '<div class="bar-track">'
            f'<div class="bar-fill" style="width:{width:.1f}%"></div>'
            '</div>'
            f'<div class="bar-value">{format_int(value)}</div>'
            "</div>"
        )
    return "\n".join(rows)


def render_examples_html(examples: list[dict[str, Any]]) -> str:
    if not examples:
        return '<p class="empty">No examples detected.</p>'
    rows = []
    for item in examples[:10]:
        rows.append(
            '<div class="example-row">'
            f'<code>{html_text(item.get("turn_id", ""))}</code>'
            f'<span>{html_text(item.get("status", "unknown"))}</span>'
            f'<span>{format_int(item.get("duration_seconds", 0))}s</span>'
            f'<span>{format_int(item.get("tool_calls", 0))} tools</span>'
            f'<span>{format_int(item.get("exec_failures", 0))} exec failures</span>'
            "</div>"
        )
    return "\n".join(rows)


def strongest(counter: dict[str, int], default: str = "none") -> str:
    return next(iter(counter), default)


def render_qualitative_markdown(qualitative: Any) -> list[str]:
    if not isinstance(qualitative, dict):
        return []

    lines = [
        "## Qualitative Opt-in",
        "",
        f"- Mode: `{qualitative.get('mode', 'unknown')}`",
        f"- Confidence: `{qualitative.get('confidence', 'low')}`",
        f"- Privacy note: {qualitative.get('note', 'No raw transcript excerpts are included.')}",
        "",
        "### At a Glance",
        "",
    ]

    for item in qualitative.get("at_a_glance", []):
        lines.extend(format_qualitative_markdown_item(item))
    lines.extend(["", "### Wins", ""])
    for item in qualitative.get("wins", []):
        lines.extend(format_qualitative_markdown_item(item))
    lines.extend(["", "### Friction", ""])
    for item in qualitative.get("friction", []):
        lines.extend(format_qualitative_markdown_item(item))
    lines.extend(["", "### Copyable Prompts", ""])
    for item in qualitative.get("copyable_prompts", []):
        title = item.get("title", "Prompt")
        prompt = item.get("prompt", "")
        confidence = item.get("confidence", "low")
        evidence = "; ".join(item.get("evidence", [])) or "none"
        lines.extend(
            [
                f"#### {title}",
                "",
                "```text",
                str(prompt),
                "```",
                f"- Confidence: `{confidence}`",
                f"- Evidence: {evidence}",
                "",
            ]
        )
    lines.extend(["### Evidence Bundle", ""])
    for item in qualitative.get("evidence", []):
        value = item.get("value", "")
        count = item.get("count")
        count_text = f", count={count}" if isinstance(count, int) else ""
        lines.append(
            f"- `{item.get('signal', 'signal')}` from `{item.get('source', 'unknown')}`: `{value}`{count_text}, confidence=`{item.get('confidence', 'low')}`"
        )
    lines.append("")
    return lines


def format_qualitative_markdown_item(item: dict[str, Any]) -> list[str]:
    evidence = "; ".join(item.get("evidence", [])) or "none"
    return [
        f"- {item.get('text', '')}",
        f"  - Confidence: `{item.get('confidence', 'low')}`",
        f"  - Evidence: {evidence}",
    ]


def render_html_insights(items: list[dict[str, Any]]) -> str:
    if not items:
        return '<p class="empty">No qualitative signal detected.</p>'
    rendered = []
    for item in items:
        evidence = "; ".join(item.get("evidence", [])) or "none"
        rendered.append(
            "<li>"
            f"{html_text(item.get('text', ''))}"
            f'<div class="evidence">confidence: {html_text(item.get("confidence", "low"))} · {html_text(evidence)}</div>'
            "</li>"
        )
    return "<ul>" + "\n".join(rendered) + "</ul>"


def render_html_prompt_cards(items: list[dict[str, Any]]) -> str:
    if not items:
        return '<p class="empty">No copyable prompts generated.</p>'
    cards = []
    for item in items:
        evidence = "; ".join(item.get("evidence", [])) or "none"
        cards.append(
            '<div class="pattern-card">'
            f'<div class="card-title">{html_text(item.get("title", "Prompt"))}</div>'
            f'<pre>{html_text(item.get("prompt", ""))}</pre>'
            f'<p class="evidence">confidence: {html_text(item.get("confidence", "low"))} · {html_text(evidence)}</p>'
            "</div>"
        )
    return "\n".join(cards)


def render_qualitative_html(qualitative: Any) -> str:
    if not isinstance(qualitative, dict):
        return ""
    evidence = qualitative.get("evidence", [])
    evidence_rows = []
    for item in evidence:
        count = item.get("count")
        count_text = f" · count {format_int(count)}" if isinstance(count, int) else ""
        evidence_rows.append(
            "<li>"
            f'<code>{html_text(item.get("signal", "signal"))}</code> from '
            f'<code>{html_text(item.get("source", "unknown"))}</code>: '
            f'{html_text(item.get("value", ""))}{count_text}'
            f'<div class="evidence">confidence: {html_text(item.get("confidence", "low"))}</div>'
            "</li>"
        )
    evidence_html = "<ul>" + "\n".join(evidence_rows) + "</ul>" if evidence_rows else '<p class="empty">No evidence bundle generated.</p>'

    return f"""
    <h2 id="qualitative">Qualitative Opt-in</h2>
    <div class="card good">
      <p><strong>Mode:</strong> <code>{html_text(qualitative.get("mode", "unknown"))}</code></p>
      <p><strong>Confidence:</strong> <code>{html_text(qualitative.get("confidence", "low"))}</code></p>
      <p class="muted">{html_text(qualitative.get("note", "No raw transcript excerpts are included."))}</p>
    </div>
    <div class="grid qualitative-grid">
      <div class="card"><h3>At a Glance</h3>{render_html_insights(qualitative.get("at_a_glance", []))}</div>
      <div class="card"><h3>Wins</h3>{render_html_insights(qualitative.get("wins", []))}</div>
      <div class="card warn"><h3>Friction</h3>{render_html_insights(qualitative.get("friction", []))}</div>
      <div class="card"><h3>Evidence Bundle</h3>{evidence_html}</div>
    </div>
    <h2 id="copyable-prompts">Copyable Prompts</h2>
    <div class="grid">{render_html_prompt_cards(qualitative.get("copyable_prompts", []))}</div>
"""


def render_html(snapshot: dict[str, Any]) -> str:
    target_month = snapshot["target_month"]
    source = snapshot["source"]
    usage = snapshot["usage"]
    distributions = snapshot["distributions"]
    task_summary = snapshot.get("tasks", {})
    outcomes = snapshot.get("outcomes", {})
    exec_outcome = outcomes.get("exec", {}) if isinstance(outcomes, dict) else {}
    patch_outcome = outcomes.get("patch", {}) if isinstance(outcomes, dict) else {}
    friction_events = outcomes.get("friction_events", {}) if isinstance(outcomes, dict) else {}
    tokens = usage["tokens"]
    outputs = snapshot.get("outputs", {})
    date_range = source.get("date_range", {})
    prompts = int(usage.get("user_prompts") or 0)
    sessions = int(usage.get("sessions") or 0)
    turns = int(usage.get("turns") or 0)
    active_days = int(source.get("active_days") or 0)
    tool_errors = distributions.get("tool_errors", {})
    tool_error_types = distributions.get("tool_error_types", {})
    work_areas = distributions.get("work_areas", {})
    repos = distributions.get("repos", {})
    tools = distributions.get("tools", {})
    skills = distributions.get("skills", {})
    friction = distributions.get("friction", {})
    hours = distributions.get("user_prompts_by_hour", {})
    top_work = strongest(work_areas)
    top_tool = strongest(tools)
    top_friction = strongest(friction_events if friction_events else friction)
    top_skill = strongest(skills)
    turns_per_session = round(turns / sessions, 1) if sessions else 0
    cached_ratio = safe_pct(int(tokens.get("cached_input", 0)), int(tokens.get("input", 0)))
    tool_error_total = sum(value for value in tool_errors.values() if isinstance(value, int))
    report_path = outputs.get("report", "")
    html_path = outputs.get("html", "")
    snapshot_path = outputs.get("snapshot", "")
    qualitative = snapshot.get("qualitative")
    qualitative_nav = ""
    if isinstance(qualitative, dict):
        qualitative_nav = '<a href="#qualitative">Qualitative Opt-in</a><a href="#copyable-prompts">Copyable Prompts</a>'
    qualitative_section = render_qualitative_html(qualitative)

    suggestions = "\n".join(
        f"<li>{html_text(item)}</li>" for item in snapshot.get("recommendations", [])
    ) or "<li>No high-confidence suggestions detected.</li>"

    pattern_cards = [
        (
            "Evidence-first investigations",
            f"`{html_text(distributions.get('work_areas', {}).get('data investigation', 0))}` data-investigation signals suggest a recurring need to verify claims before acting.",
            "Before reporting that a table, column, or workflow is unused, gather evidence from code search, query history, and lineage, then reconcile contradictions.",
        ),
        (
            "Repository context gate",
            f"`{html_text(friction.get('wrong repo/worktree', 0))}` wrong repo/worktree signals were detected.",
            "For write actions, start with the target repo, branch, worktree, and intended output before editing or opening issues.",
        ),
        (
            "Permission/auth preflight",
            f"`{html_text(tool_error_types.get('auth', 0))}` auth and `{html_text(tool_error_types.get('sandbox/permission', 0))}` sandbox/permission tool-error signals were detected.",
            "Run lightweight auth and permission checks before long workflows that depend on external services or escalated writes.",
        ),
    ]
    patterns_html = "\n".join(
        '<div class="pattern-card">'
        f'<div class="card-title">{title}</div>'
        f'<p>{summary}</p>'
        f'<pre>{html_text(prompt)}</pre>'
        "</div>"
        for title, summary, prompt in pattern_cards
    )

    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Codex Insights - {html_text(target_month)}</title>
  <style>
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; background: #f7f8fb; color: #243042; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; line-height: 1.55; }}
    .container {{ max-width: 980px; margin: 0 auto; padding: 44px 24px 64px; }}
    h1 {{ margin: 0 0 6px; color: #111827; font-size: 32px; line-height: 1.15; }}
    h2 {{ margin: 42px 0 14px; color: #111827; font-size: 20px; }}
    h3 {{ margin: 0 0 10px; color: #334155; font-size: 13px; text-transform: uppercase; letter-spacing: .04em; }}
    p {{ margin: 0 0 12px; }}
    .subtitle {{ color: #64748b; font-size: 14px; margin-bottom: 24px; }}
    .nav {{ display: flex; flex-wrap: wrap; gap: 8px; margin: 22px 0 30px; padding: 14px; border: 1px solid #e2e8f0; border-radius: 8px; background: white; }}
    .nav a {{ color: #475569; text-decoration: none; background: #f1f5f9; border-radius: 6px; padding: 6px 10px; font-size: 12px; }}
    .stats-row {{ display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 12px; margin: 20px 0 30px; }}
    .stat {{ background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 14px; }}
    .stat-value {{ font-size: 24px; font-weight: 700; color: #111827; }}
    .stat-label {{ font-size: 11px; text-transform: uppercase; color: #64748b; }}
    .glance {{ background: #fff7ed; border: 1px solid #fdba74; border-radius: 10px; padding: 18px 20px; margin-bottom: 26px; }}
    .glance strong {{ color: #9a3412; }}
    .grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 18px; }}
    .card, .pattern-card {{ background: white; border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px; }}
    .card-title {{ font-weight: 650; color: #111827; margin-bottom: 6px; }}
    .muted {{ color: #64748b; font-size: 13px; }}
    .evidence {{ margin-top: 5px; color: #64748b; font-size: 11px; }}
    .bar-row {{ display: flex; align-items: center; gap: 8px; margin: 7px 0; }}
    .bar-label {{ width: 150px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: #475569; font-size: 12px; }}
    .bar-track {{ flex: 1; height: 8px; background: #edf2f7; border-radius: 999px; overflow: hidden; }}
    .bar-fill {{ height: 100%; background: #2563eb; border-radius: 999px; }}
    .bar-value {{ width: 54px; text-align: right; color: #64748b; font-size: 12px; font-variant-numeric: tabular-nums; }}
    .example-row {{ display: grid; grid-template-columns: 70px 1fr 70px 70px 100px; gap: 6px; align-items: center; padding: 5px 0; border-top: 1px solid #edf2f7; color: #475569; font-size: 11px; }}
    .good {{ background: #f0fdf4; border-color: #bbf7d0; }}
    .warn {{ background: #fff7ed; border-color: #fed7aa; }}
    .bad {{ background: #fef2f2; border-color: #fecaca; }}
    .empty {{ color: #94a3b8; font-size: 13px; }}
    pre {{ margin: 10px 0 0; white-space: pre-wrap; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 10px; color: #334155; font-size: 12px; }}
    ul {{ margin: 8px 0 0 18px; padding: 0; }}
    li {{ margin-bottom: 6px; }}
    @media (max-width: 760px) {{ .grid, .stats-row {{ grid-template-columns: 1fr; }} .bar-label {{ width: 120px; }} .example-row {{ grid-template-columns: 1fr 1fr; }} }}
  </style>
</head>
<body>
  <main class="container">
    <h1>Codex Insights</h1>
    <p class="subtitle">{html_text(target_month)} · {format_int(prompts)} user prompts across {format_int(sessions)} sessions · {format_int(active_days)} active days</p>

    <section class="glance">
      <p><strong>What's working:</strong> Codex completed {format_int(task_summary.get("completed", 0))} of {format_int(task_summary.get("total", 0))} structured tasks ({task_summary.get("completion_rate", 0)}%).</p>
      <p><strong>What's hindering you:</strong> The strongest structured friction signal is `{html_text(top_friction)}`. Structured tool outcomes show {format_int(exec_outcome.get("unrecovered_failures", 0))} unrecovered exec failures and {format_int(patch_outcome.get("failures", 0))} patch failures.</p>
      <p><strong>Quick wins:</strong> review long-tail tasks and unrecovered tool outcomes before changing broad keyword or skill-trigger rules.</p>
    </section>

    <nav class="nav">
      <a href="#work">What You Work On</a>
      <a href="#tasks">Task Outcomes</a>
      <a href="#usage">How You Use Codex</a>
      <a href="#friction">Where Things Go Wrong</a>
      <a href="#suggestions">Suggested AGENTS.md Additions</a>
      <a href="#patterns">New Usage Patterns</a>
      {qualitative_nav}
      <a href="#snapshot">Snapshot</a>
    </nav>

    <section class="stats-row">
      <div class="stat"><div class="stat-value">{format_int(sessions)}</div><div class="stat-label">Sessions</div></div>
      <div class="stat"><div class="stat-value">{format_int(turns)}</div><div class="stat-label">Turns</div></div>
      <div class="stat"><div class="stat-value">{format_int(prompts)}</div><div class="stat-label">Prompts</div></div>
      <div class="stat"><div class="stat-value">{format_int(active_days)}</div><div class="stat-label">Active Days</div></div>
      <div class="stat"><div class="stat-value">{turns_per_session}</div><div class="stat-label">Turns / Session</div></div>
    </section>

    <h2 id="work">What You Work On</h2>
    <div class="grid">
      <div class="card"><h3>Work Areas</h3>{render_bar_rows(work_areas)}</div>
      <div class="card"><h3>Repositories</h3>{render_bar_rows(repos)}</div>
    </div>

    <h2 id="tasks">Task Outcomes</h2>
    <div class="grid">
      <div class="card good"><h3>Completion</h3>
        <p>Completed: {format_int(task_summary.get("completed", 0))} / {format_int(task_summary.get("total", 0))} ({task_summary.get("completion_rate", 0)}%)</p>
        <p>Aborted: {format_int(task_summary.get("aborted", 0))}</p>
        <p>Incomplete: {format_int(task_summary.get("incomplete", 0))}</p>
        <p>Median duration: {format_int(task_summary.get("median_duration_seconds", 0))}s</p>
        <p>Median tool calls: {format_int(task_summary.get("median_tool_calls", 0))}</p>
      </div>
      <div class="card warn"><h3>Long-tail Tasks</h3>
        <p>{format_int(task_summary.get("long_tail_tasks", 0))} tasks crossed {format_int(task_summary.get("long_tail_threshold_tool_calls", 0))} tool calls or 30 minutes.</p>
        {render_examples_html(task_summary.get("long_tail_examples", []))}
      </div>
      <div class="card"><h3>Exec Outcomes</h3>
        <p>Calls: {format_int(exec_outcome.get("calls", 0))}</p>
        <p>Failures: {format_int(exec_outcome.get("failures", 0))} ({exec_outcome.get("failure_rate", 0)}%)</p>
        <p>Recovered failures: {format_int(exec_outcome.get("recovered_failures", 0))}</p>
        <p>Unrecovered failures: {format_int(exec_outcome.get("unrecovered_failures", 0))}</p>
      </div>
      <div class="card"><h3>Patch Outcomes</h3>
        <p>Attempts: {format_int(patch_outcome.get("attempts", 0))}</p>
        <p>Failures: {format_int(patch_outcome.get("failures", 0))} ({patch_outcome.get("failure_rate", 0)}%)</p>
        <p>Recovered failures: {format_int(patch_outcome.get("recovered_failures", 0))}</p>
        <p>Unrecovered failures: {format_int(patch_outcome.get("unrecovered_failures", 0))}</p>
      </div>
    </div>

    <h2 id="usage">How You Use Codex</h2>
    <div class="grid">
      <div class="card"><h3>Tools</h3>{render_bar_rows(tools)}</div>
      <div class="card"><h3>Skills</h3>{render_bar_rows(skills)}</div>
      <div class="card"><h3>User Prompts by Hour</h3>{render_bar_rows(hours, max_rows=24)}</div>
      <div class="card"><h3>Token Snapshot</h3>
        <p>Input: {format_int(tokens.get("input", 0))}</p>
        <p>Cached input: {format_int(tokens.get("cached_input", 0))} ({cached_ratio}%)</p>
        <p>Output: {format_int(tokens.get("output", 0))}</p>
        <p>Reasoning output: {format_int(tokens.get("reasoning_output", 0))}</p>
      </div>
    </div>

    <h2 id="friction">Where Things Go Wrong</h2>
    <div class="grid">
      <div class="card bad"><h3>Structured Friction Events</h3>{render_bar_rows(friction_events)}</div>
      <div class="card warn"><h3>Tool Error Types</h3>{render_bar_rows(tool_error_types)}</div>
      <div class="card warn"><h3>Tools With Error-Like Outputs</h3>{render_bar_rows(tool_errors)}</div>
      <div class="card"><h3>Date Range</h3>
        <p>{html_text(date_range.get("first_event_at") or "(unknown)")}</p>
        <p class="muted">to</p>
        <p>{html_text(date_range.get("last_event_at") or "(unknown)")}</p>
      </div>
    </div>

    <h2 id="suggestions">Suggested AGENTS.md / Skill Improvements</h2>
    <div class="card good"><ul>{suggestions}</ul></div>

    <h2 id="patterns">New Usage Patterns</h2>
    <div class="grid">{patterns_html}</div>

    {qualitative_section}

    <h2 id="snapshot">Snapshot</h2>
    <div class="card">
      <p>Markdown report: <code>{html_text(report_path)}</code></p>
      <p>HTML report: <code>{html_text(html_path)}</code></p>
      <p>JSON snapshot: <code>{html_text(snapshot_path)}</code></p>
      <p class="muted">This HTML is deterministic and generated from aggregate snapshot data only. It does not include raw transcript excerpts.</p>
    </div>
  </main>
</body>
</html>
"""


def render_markdown(snapshot: dict[str, Any]) -> str:
    target_month = snapshot["target_month"]
    source = snapshot["source"]
    usage = snapshot["usage"]
    distributions = snapshot["distributions"]
    task_summary = snapshot.get("tasks", {})
    outcomes = snapshot.get("outcomes", {})
    exec_outcome = outcomes.get("exec", {}) if isinstance(outcomes, dict) else {}
    patch_outcome = outcomes.get("patch", {}) if isinstance(outcomes, dict) else {}
    friction_events = outcomes.get("friction_events", {}) if isinstance(outcomes, dict) else {}
    token_info = usage["tokens"]
    warnings_total = sum(source["warning_counts"].values())

    top_work = next(iter(distributions["work_areas"]), "none")
    top_tool = next(iter(distributions["tools"]), "none")
    top_friction = next(iter(friction_events or distributions["friction"]), "none")
    html_path = snapshot.get("outputs", {}).get("html", "(unknown)")
    snapshot_path = snapshot.get("outputs", {}).get("snapshot", "(unknown)")
    date_range = source.get("date_range", {})
    qualitative_lines = render_qualitative_markdown(snapshot.get("qualitative"))

    lines = [
        f"# Codex Insights - {target_month}",
        "",
        f"Generated: {snapshot['generated_at']}",
        f"Source: `{snapshot['codex_home']}/sessions`",
        "",
        "## Executive Summary",
        "",
        f"- Analyzed {usage['sessions']} sessions and {source['events_in_month']} in-month events.",
        f"- Counted {usage['turns']} turns, {usage['user_prompts']} user prompts, and {usage['assistant_messages']} assistant messages.",
        f"- Top work area: `{top_work}`. Top tool: `{top_tool}`. Top friction signal: `{top_friction}`.",
        f"- Snapshot warnings: {warnings_total}.",
        "",
        "## Usage Snapshot",
        "",
        f"- Sessions: {usage['sessions']}",
        f"- Turns: {usage['turns']}" + (" (estimated)" if usage["turns_estimated"] else ""),
        f"- User prompts: {usage['user_prompts']}",
        f"- Assistant final messages: {usage['assistant_final_messages']}",
        f"- Token events: {token_info['token_events']}",
        f"- Tokens: input={token_info['input']}, cached_input={token_info['cached_input']}, output={token_info['output']}, reasoning_output={token_info['reasoning_output']}",
        f"- Token totals unknown: {str(token_info['unknown']).lower()}",
        f"- Active days: {source.get('active_days', 0)}",
        f"- Date range: {date_range.get('first_event_at') or '(unknown)'} to {date_range.get('last_event_at') or '(unknown)'}",
        "",
        "## Task Outcomes",
        "",
        f"- Structured tasks: {task_summary.get('total', 0)}",
        f"- Completed: {task_summary.get('completed', 0)} ({task_summary.get('completion_rate', 0)}%)",
        f"- Aborted: {task_summary.get('aborted', 0)}",
        f"- Incomplete: {task_summary.get('incomplete', 0)}",
        f"- Median duration seconds: {task_summary.get('median_duration_seconds', 0)}",
        f"- Median tool calls: {task_summary.get('median_tool_calls', 0)}",
        f"- Long-tail tasks: {task_summary.get('long_tail_tasks', 0)} (threshold: {task_summary.get('long_tail_threshold_tool_calls', 0)} tool calls or 30 minutes)",
        "",
        "### Long-tail Task Examples",
        "",
        *format_examples(task_summary.get("long_tail_examples", [])),
        "",
        "### Aborted Task Examples",
        "",
        *format_examples(task_summary.get("aborted_examples", [])),
        "",
        "## Structured Tool Outcomes",
        "",
        "### Exec Outcomes",
        "",
        f"- Calls: {exec_outcome.get('calls', 0)}",
        f"- Successes: {exec_outcome.get('successes', 0)}",
        f"- Failures: {exec_outcome.get('failures', 0)} ({exec_outcome.get('failure_rate', 0)}%)",
        f"- Recovered failures: {exec_outcome.get('recovered_failures', 0)}",
        f"- Unrecovered failures: {exec_outcome.get('unrecovered_failures', 0)}",
        f"- Recovery rate: {exec_outcome.get('recovery_rate', 0)}%",
        "",
        "### Patch Outcomes",
        "",
        f"- Attempts: {patch_outcome.get('attempts', 0)}",
        f"- Successes: {patch_outcome.get('successes', 0)}",
        f"- Failures: {patch_outcome.get('failures', 0)} ({patch_outcome.get('failure_rate', 0)}%)",
        f"- Recovered failures: {patch_outcome.get('recovered_failures', 0)}",
        f"- Unrecovered failures: {patch_outcome.get('unrecovered_failures', 0)}",
        f"- Recovery rate: {patch_outcome.get('recovery_rate', 0)}%",
        "",
        "### Structured Friction Events",
        "",
        *format_counter(friction_events),
        "",
        "### CWD Distribution",
        "",
        *format_counter(distributions["cwd"]),
        "",
        "### Repository Distribution",
        "",
        *format_counter(distributions["repos"]),
        "",
        "## Work Areas",
        "",
        *format_counter(distributions["work_areas"]),
        "",
        "## Tools and Skills",
        "",
        "### Tools",
        "",
        *format_counter(distributions["tools"]),
        "",
        "### Tool Errors",
        "",
        *format_counter(distributions.get("tool_errors", {})),
        "",
        "### Tool Error Types",
        "",
        *format_counter(distributions.get("tool_error_types", {})),
        "",
        "### Skills",
        "",
        *format_counter(distributions["skills"]),
        "",
        "## Legacy Keyword Friction and Corrections",
        "",
        *format_counter(distributions["friction"]),
        "",
        "## User Prompt Time of Day",
        "",
        *format_counter(distributions.get("user_prompts_by_hour", {})),
        "",
        *qualitative_lines,
        "## AGENTS.md / Skill Improvement Candidates",
        "",
        *[f"- {item}" for item in snapshot["recommendations"]],
        "",
        "## Next Month Experiments",
        "",
        "- Compare this report with the next month before changing broad skill-trigger rules.",
        "- Add a lightweight hook only if transcript-derived signals remain too coarse.",
        "- Keep qualitative transcript summarization opt-in only.",
        "",
        "## Generated Files",
        "",
        f"- HTML report: `{html_path}`",
        f"- JSON snapshot: `{snapshot_path}`",
        "",
        "## Raw Snapshot Path",
        "",
        f"`{snapshot_path}`",
        "",
    ]
    return "\n".join(lines)


def ensure_private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        path.chmod(0o700)
    except OSError:
        pass


def write_private_text(path: Path, content: str) -> None:
    ensure_private_dir(path.parent)
    tmp_path = path.with_name(f".{path.name}.tmp")
    with tmp_path.open("w", encoding="utf-8") as handle:
        handle.write(content)
    tmp_path.chmod(0o600)
    os.replace(tmp_path, path)
    try:
        path.chmod(0o600)
    except OSError:
        pass


def write_outputs(snapshot: dict[str, Any], output_dir: Path) -> dict[str, str]:
    reports_dir = output_dir / "reports"
    snapshots_dir = output_dir / "snapshots"
    ensure_private_dir(output_dir)
    ensure_private_dir(reports_dir)
    ensure_private_dir(snapshots_dir)

    target_month = snapshot["target_month"]
    report_path = reports_dir / f"{target_month}.md"
    html_path = reports_dir / f"{target_month}.html"
    snapshot_path = snapshots_dir / f"{target_month}.json"
    latest_path = output_dir / "latest.md"
    latest_html_path = output_dir / "latest.html"

    snapshot_with_paths = dict(snapshot)
    snapshot_with_paths["outputs"] = {
        "report": shorten_path(report_path),
        "html": shorten_path(html_path),
        "snapshot": shorten_path(snapshot_path),
        "latest": shorten_path(latest_path),
        "latest_html": shorten_path(latest_html_path),
    }
    snapshot_text = json.dumps(snapshot_with_paths, ensure_ascii=False, indent=2) + "\n"
    report_text = render_markdown(snapshot_with_paths)
    html_text_content = render_html(snapshot_with_paths)

    write_private_text(snapshot_path, snapshot_text)
    write_private_text(report_path, report_text)
    write_private_text(html_path, html_text_content)
    write_private_text(latest_path, report_text)
    write_private_text(latest_html_path, html_text_content)
    return {
        "report": str(report_path),
        "html": str(html_path),
        "snapshot": str(snapshot_path),
        "latest": str(latest_path),
        "latest_html": str(latest_html_path),
    }


def stdout_summary(snapshot: dict[str, Any], paths: dict[str, str], stdout_format: str) -> None:
    task_summary = snapshot.get("tasks", {})
    outcomes = snapshot.get("outcomes", {})
    summary = {
        "target_month": snapshot["target_month"],
        "report": paths["report"],
        "html": paths["html"],
        "snapshot": paths["snapshot"],
        "latest": paths["latest"],
        "latest_html": paths["latest_html"],
        "sessions": snapshot["usage"]["sessions"],
        "turns": snapshot["usage"]["turns"],
        "user_prompts": snapshot["usage"]["user_prompts"],
        "assistant_messages": snapshot["usage"]["assistant_messages"],
        "warnings": sum(snapshot["source"]["warning_counts"].values()),
        "top_work_areas": snapshot["distributions"]["work_areas"],
        "top_tools": snapshot["distributions"]["tools"],
        "top_tool_errors": snapshot["distributions"].get("tool_errors", {}),
        "top_friction": snapshot["distributions"]["friction"],
        "tasks": task_summary,
        "outcomes": outcomes,
        "qualitative": bool(snapshot.get("qualitative")),
        "qualitative_confidence": snapshot.get("qualitative", {}).get("confidence") if isinstance(snapshot.get("qualitative"), dict) else None,
    }
    if stdout_format == "json":
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return
    if stdout_format == "html":
        print(f"Codex Insights HTML - {summary['target_month']}")
        print(f"HTML: {summary['html']}")
        print(f"Latest HTML: {summary['latest_html']}")
        print(f"Report: {summary['report']}")
        print(f"Snapshot: {summary['snapshot']}")
        if summary["qualitative"]:
            print(f"Qualitative: enabled ({summary['qualitative_confidence']})")
        return
    print(f"Codex Insights - {summary['target_month']}")
    print(f"Report: {summary['report']}")
    print(f"HTML: {summary['html']}")
    print(f"Snapshot: {summary['snapshot']}")
    print(f"Latest: {summary['latest']}")
    print(f"Latest HTML: {summary['latest_html']}")
    if summary["qualitative"]:
        print(f"Qualitative: enabled ({summary['qualitative_confidence']})")
    print(
        "Summary: "
        f"sessions={summary['sessions']}, "
        f"turns={summary['turns']}, "
        f"user_prompts={summary['user_prompts']}, "
        f"assistant_messages={summary['assistant_messages']}, "
        f"warnings={summary['warnings']}, "
        f"tasks={task_summary.get('total', 0)}, "
        f"completion_rate={task_summary.get('completion_rate', 0)}%, "
        f"exec_unrecovered={outcomes.get('exec', {}).get('unrecovered_failures', 0) if isinstance(outcomes, dict) else 0}"
    )


def main() -> int:
    os.umask(0o077)
    args = parse_args()
    try:
        target_month = validate_month(args.month or previous_complete_month())
    except ValueError as exc:
        print(f"codex-insights.py: {exc}", file=sys.stderr)
        return 2

    codex_home = Path(args.codex_home).expanduser()
    output_dir = Path(args.output_dir).expanduser()
    snapshot = build_snapshot(target_month, codex_home)
    if args.qualitative:
        snapshot["qualitative"] = build_qualitative(snapshot)
    paths = write_outputs(snapshot, output_dir)
    stdout_summary(snapshot, paths, args.format)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
