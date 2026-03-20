---
description: Orchestrate multiple agents for complex tasks with cross-model review
---

# Orchestrate Command

Orchestrate multiple specialized agents for this complex task: $ARGUMENTS

## Step 1: Parse Arguments

Parse the arguments to determine:
- **Workflow type**: `feature`, `bugfix`, `refactor`, `security`, or `custom`
- **Additional agents** (optional): `--with agent1,agent2` to append domain-specific reviewers
- **Task description**: The remaining text

If no workflow type is specified, default to `feature`.

## Step 2: Select Agent Pipeline

Based on the workflow type, select the agent pipeline:

```
feature:  planner → tdd-guide → code-reviewer → security-reviewer → codex-review
bugfix:   planner → tdd-guide → code-reviewer → codex-review
refactor: planner → architect → code-reviewer → tdd-guide → codex-review
security: planner → security-reviewer → code-reviewer → codex-review
custom:   [user-specified agents] → codex-review
```

If `--with` agents are specified, insert them before `codex-review`.
Example: `/orchestrate feature --with python-reviewer "Build a REST API"` becomes:
`planner → tdd-guide → code-reviewer → security-reviewer → python-reviewer → codex-review`

## Step 3: Steering Integration

Before invoking the first agent:

1. Load the **steering** skill using the Skill tool
2. Follow steering's Mode 1 (document creation) to create the steering directory and documents
3. The planner agent will generate/update `requirements.md`, `design.md`, and `tasklist.md` in the steering directory

## Step 4: Execute Agent Pipeline

For each agent in the pipeline (except codex-review):

### 4a. Invoke the agent
Use the Agent tool to spawn the agent with:
- The original task description
- The handoff document from the previous agent (if any)
- Context about the steering documents location

### 4b. Collect handoff
After the agent completes, create a handoff document:

```markdown
## HANDOFF: [previous-agent] → [next-agent]

### Context
[Summary of what was done]

### Findings
[Key discoveries or decisions]

### Files Modified
[List of files touched]

### Open Questions
[Unresolved items for next agent]

### Recommendations
[Suggested next steps]
```

### 4c. Pass to next agent
Include the handoff document in the next agent's prompt.

## Step 5: Codex Cross-Model Review

After all Claude agents complete, run the Codex review:

```bash
codex exec -s read-only "<review-prompt>"
```

Construct the review prompt with:

```markdown
## Codex Cross-Model Review Request

### Task
[The original task description]

### Git Diff
[Output of git diff --staged and git diff]

### Claude Agent Findings

#### [agent-name] (model)
[Severity-tagged findings from that agent]

#### [agent-name] (model)
[Same format]

### Review Instructions
Review the above Claude agent findings and diff comprehensively:
1. Are there issues Claude missed?
2. Are there contradictions or duplicates in the findings?
3. Overall implementation quality assessment: SHIP / NEEDS WORK / BLOCKED
```

**Failure handling**: If `codex` is not installed, not authenticated, or times out:
- Do NOT fail the orchestration
- Record `codex-review: SKIPPED (reason)` in the final report
- Continue to Step 6

## Step 6: Final Orchestration Report

Generate the final report:

```markdown
# Orchestration Report

## Overview
- **Workflow**: [type]
- **Task**: [description]
- **Pipeline**: [agent → agent → ... → codex-review]

## Agent Results

### [Agent Name] (Phase N)
**Status**: Complete
**Key Findings**:
- [Finding 1]
- [Finding 2]

**Files Changed**:
- [file list]

### Codex Cross-Model Review
**Status**: Complete / SKIPPED (reason)
**Assessment**: SHIP / NEEDS WORK / BLOCKED
**Additional Findings**:
- [Issues Claude missed, if any]

## Summary

| Agent | Status | Issues Found |
|-------|--------|-------------|
| planner | ✓ | — |
| tdd-guide | ✓ | 2 |
| code-reviewer | ✓ | 3 HIGH, 1 MEDIUM |
| security-reviewer | ✓ | 0 CRITICAL |
| codex-review | ✓ | 1 additional |

## Recommendation
**SHIP** / **NEEDS WORK** / **BLOCKED**

[Rationale for recommendation based on aggregate findings]
```

## Coordination Rules

1. **Plan before execute** — Always run planner first (except custom)
2. **Minimize handoffs** — Keep handoff documents concise and actionable
3. **Parallelize when possible** — If agents are independent, run them in parallel using multiple Agent tool calls
4. **Clear boundaries** — Each agent has specific scope; don't duplicate work
5. **Single source of truth** — Steering documents are the canonical project state
6. **Graceful degradation** — If codex-review fails, report and continue

---

**NOTE**: Complex tasks benefit from multi-agent orchestration. Simple tasks (single-file edits, typo fixes) should use agents directly without orchestration overhead.
