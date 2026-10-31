---
name: create-implementation-plan
description: 'Create a new implementation plan file for new features, refactoring existing code or upgrading packages, design, architecture or infrastructure.'
---

Source: https://github.com/github/awesome-copilot/tree/main/skills/create-implementation-plan (MIT License, Copyright GitHub, Inc.; see `../THIRD_PARTY_LICENSES.md`). Upstream text unchanged; Cheshire-specific notes are appended at the end.

# Create Implementation Plan

## Primary Directive

Your goal is to create a new implementation plan file for `${input:PlanPurpose}`. Your output must be machine-readable, deterministic, and structured for autonomous execution by other AI systems or humans.

## Execution Context

This prompt is designed for AI-to-AI communication and automated processing. All instructions must be interpreted literally and executed systematically without human interpretation or clarification.

## Core Requirements

- Generate implementation plans that are fully executable by AI agents or humans
- Use deterministic language with zero ambiguity
- Structure all content for automated parsing and execution
- Ensure complete self-containment with no external dependencies for understanding

## Plan Structure Requirements

Plans must consist of discrete, atomic phases containing executable tasks. Each phase must be independently processable by AI agents or humans without cross-phase dependencies unless explicitly declared.

## Phase Architecture

- Each phase must have measurable completion criteria
- Tasks within phases must be executable in parallel unless dependencies are specified
- All task descriptions must include specific file paths, function names, and exact implementation details
- No task should require human interpretation or decision-making

## AI-Optimized Implementation Standards

- Use explicit, unambiguous language with zero interpretation required
- Structure all content as machine-parseable formats (tables, lists, structured data)
- Include specific file paths, line numbers, and exact code references where applicable
- Define all variables, constants, and configuration values explicitly
- Provide complete context within each task description
- Use standardized prefixes for all identifiers (REQ-, TASK-, etc.)
- Include validation criteria that can be automatically verified

## Output File Specifications

- Save implementation plan files in `/plan/` directory
- Use naming convention: `[purpose]-[component]-[version].md`
- Purpose prefixes: `upgrade|refactor|feature|data|infrastructure|process|architecture|design`
- Example: `upgrade-system-command-4.md`, `feature-auth-module-1.md`
- File must be valid Markdown with proper front matter structure

## Mandatory Template Structure

All implementation plans must strictly adhere to the following template. Each section is required and must be populated with specific, actionable content. AI agents must validate template compliance before execution.

## Template Validation Rules

- All front matter fields must be present and properly formatted
- All section headers must match exactly (case-sensitive)
- All identifier prefixes must follow the specified format
- Tables must include all required columns
- No placeholder text may remain in the final output
- **Identifiers must be uniquely declared.** Every identifier (`REQ-NNN`, `SEC-NNN`, `CON-NNN`, `GUD-NNN`, `PAT-NNN`, `GOAL-NNN`, `TASK-NNN`, `ALT-NNN`, `DEP-NNN`, `FILE-NNN`, `TEST-NNN`, `RISK-NNN`, `ASSUMPTION-NNN`) must be **declared exactly once**. A declaration is where the identifier introduces a row: the leading cell in a TASK/GOAL table row, or the bolded prefix in a bullet line like `- **REQ-001**: ...`. The same identifier may then appear any number of times as a **reference** elsewhere in the plan (a `TASK` body citing a `REQ`, one `TASK` citing another `TASK`, the Dependencies section pointing at a `DEP` already declared upstream, etc.). References are expected and not collisions.

## Identifier Uniqueness Check

Run these checks before finalizing the plan. Checks (1) and (2) target declarations and must return zero rows. Check (3) is a broad informational scan: it will surface valid references too, so use it for awareness rather than as a gate.

```bash
# Set PLAN_FILE to the plan being validated.
PLAN_FILE="/plan/<purpose>-<component>-<version>.md"

# 1) Duplicate TASK / GOAL declarations in table rows.
grep -oE '\| (TASK|GOAL)-[0-9]+ \|' "$PLAN_FILE" \
  | sed -E 's/.*((TASK|GOAL)-[0-9]+).*/\1/' \
  | sort | uniq -d

# 2) Duplicate declaration IDs in bullet-style spec lines.
grep -oE '^- \*\*(REQ|SEC|CON|GUD|RISK|ASSUMPTION|TASK|GOAL|FILE|TEST|PAT|ALT|DEP)-[0-9]+\*\*:' "$PLAN_FILE" \
  | sed -E 's/^- \*\*([A-Z]+-[0-9]+)\*\*:.*/\1/' \
  | sort | uniq -d

# 3) Broad duplicate scan (diagnostic only; may include valid references).
grep -oE '(REQ|SEC|CON|GUD|RISK|ASSUMPTION|TASK|GOAL|FILE|TEST|PAT|ALT|DEP)-[0-9]+' "$PLAN_FILE" \
  | sort | uniq -d
```

Prerequisites: a POSIX-compatible shell (`sh` / `bash`) with `grep`, `sed`, `sort`, and `uniq`. On Windows without these tools, use equivalent platform-native commands and preserve the same declaration-vs-reference logic.

If check (1) or (2) returns any row, re-number the duplicate so each identifier is declared exactly once, then re-run the checks until both are empty.

## Status

The status of the implementation plan must be clearly defined in the front matter and must reflect the current state of the plan. The status can be one of the following (status_color in brackets): `Completed` (bright green badge), `In progress` (yellow badge), `Planned` (blue badge), `Deprecated` (red badge), or `On Hold` (orange badge). It should also be displayed as a badge in the introduction section.

```md
---
goal: [Concise Title Describing the Package Implementation Plan's Goal]
version: [Optional: e.g., 1.0, Date]
date_created: [YYYY-MM-DD]
last_updated: [Optional: YYYY-MM-DD]
owner: [Optional: Team/Individual responsible for this spec]
status: 'Completed'|'In progress'|'Planned'|'Deprecated'|'On Hold'
tags: [Optional: List of relevant tags or categories, e.g., `feature`, `upgrade`, `chore`, `architecture`, `migration`, `bug` etc]
---

# Introduction

![Status: <status>](https://img.shields.io/badge/status-<status>-<status_color>)

[A short concise introduction to the plan and the goal it is intended to achieve.]

## 1. Requirements & Constraints

[Explicitly list all requirements & constraints that affect the plan and constrain how it is implemented. Use bullet points or tables for clarity.]

- **REQ-001**: Requirement 1
- **SEC-001**: Security Requirement 1
- **[3 LETTERS]-001**: Other Requirement 1
- **CON-001**: Constraint 1
- **GUD-001**: Guideline 1
- **PAT-001**: Pattern to follow 1

## 2. Implementation Steps

### Implementation Phase 1

- GOAL-001: [Describe the goal of this phase, e.g., "Implement feature X", "Refactor module Y", etc.]

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-001 | Description of task 1 | ✅ | 2025-04-25 |
| TASK-002 | Description of task 2 | |  |
| TASK-003 | Description of task 3 | |  |

### Implementation Phase 2

- GOAL-002: [Describe the goal of this phase, e.g., "Implement feature X", "Refactor module Y", etc.]

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-004 | Description of task 4 | |  |
| TASK-005 | Description of task 5 | |  |
| TASK-006 | Description of task 6 | |  |

## 3. Alternatives

[A bullet point list of any alternative approaches that were considered and why they were not chosen. This helps to provide context and rationale for the chosen approach.]

- **ALT-001**: Alternative approach 1
- **ALT-002**: Alternative approach 2

## 4. Dependencies

[List any dependencies that need to be addressed, such as libraries, frameworks, or other components that the plan relies on.]

- **DEP-001**: Dependency 1
- **DEP-002**: Dependency 2

## 5. Files

[List the files that will be affected by the feature or refactoring task.]

- **FILE-001**: Description of file 1
- **FILE-002**: Description of file 2

## 6. Testing

[List the tests that need to be implemented to verify the feature or refactoring task.]

- **TEST-001**: Description of test 1
- **TEST-002**: Description of test 2

## 7. Risks & Assumptions

[List any risks or assumptions related to the implementation of the plan.]

- **RISK-001**: Risk 1
- **ASSUMPTION-001**: Assumption 1

## 8. Related Specifications / Further Reading

[Link to related spec 1]
[Link to relevant external documentation]
```

## 在 Cheshire 仓库中的使用说明

- **输出位置**：本仓库没有 `/plan/` 目录，也不希望在根目录新增。实施计划请写到 `docs/plan/<purpose>-<component>-<version>.md`（首次使用时创建该目录），或直接贴在 GitHub issue / PR 描述里；不要把计划文件加入 `mkdocs.yml` 导航，除非它是长期文档。
- **语言**：正文中文，`REQ-` / `TASK-` 等标识符、文件路径、命令保持英文；frontmatter 字段名保持上面的英文原样。
- **`## 6. Testing` 一节必须落到本仓库的真实验证手段**：列出要重建的目标（`make hw-all`、具体 ELF）、要跑的 lint（许可证头、Verible、clang-format 14、tclint）、要运行的仿真命令（`make -f Makefile.xcelium xrun-run BINARY=...` / `xrun-regress REGRESS_ELFS=...`）与期望证据（日志路径、`PASS:` 行）。决定「改了什么要跑什么」请参考 `cheshire-verify-change`。
- **`## 7. Risks & Assumptions` 必须写明执行环境**：哪些任务云端 Copilot coding agent / CI 可以完成（build、lint、文档），哪些只能在有 Xcelium 许可证的机器上完成（仿真、覆盖率、波形）。
- 涉及硬件依赖升级（`Bender.lock`）或生成文件（`hw/regs/*`、`sw/include/regs/*.h`）的任务，按 `article.md` 第 26.3 / 26.8 节单独成阶段，并在 TASK 中写清描述源与生成命令。
- 标识符唯一性检查脚本需要 POSIX shell；在 Windows 上可用 Git Bash / WSL 执行，或用 `rg -o` 代替 `grep -oE`。
