---
name: git
description: |
  Use when the task is primarily about Git operations or Git workflow, such as writing commit messages, creating or switching branches, understanding rebase or cherry-pick flow, inspecting history, or deciding how to structure commits. Do NOT use for GitHub-specific actions like PR comments or issue updates; use the github skill for those. Trigger especially when the user mentions commit, branch, rebase, cherry-pick, stash, merge, or Conventional Commits.
---

# Git Skill

Guide for Git operations. For mandatory rules and permissions,
see `rules/git-github.md`.

## 1. Commit Message Format (Conventional Commits)

```text
<type>: <brief description> (#<Issue number>)

<detailed description>

## Summary

- Same as detailed description is OK

## Background

- Briefly explain the background and purpose

## Changes

- Specific change 1
- Specific change 2

## Technical Details

- Technical implementation details
- Reasons for design decisions
- Focus on "why" throughout

## Verification

- Describe verification if performed

## Related URLs

- <Related Issue>
- <External URL>
- Others if applicable
```

### 1.1. Type Examples

| Type     | Description                  |
| -------- | ---------------------------- |
| feat     | New feature                  |
| fix      | Bug fix                      |
| docs     | Documentation only           |
| style    | Formatting, no code change   |
| refactor | Code change without fix/feat |
| test     | Adding/updating tests        |
| chore    | Maintenance, dependencies    |

## 2. Related Resources

| Resource         | Purpose                         |
| ---------------- | ------------------------------- |
| rules/git-github | Mandatory rules and permissions |
| skills/github    | GitHub-specific operations      |
