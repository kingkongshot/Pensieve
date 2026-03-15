---
id: run-when-syncing-to-main
type: pipeline
title: Sync to Main Pipeline
status: active
created: 2026-03-15
updated: 2026-03-15
tags: [pensieve, pipeline, sync, translation]
name: run-when-syncing-to-main
description: Sync changes from the experimental/zh branch to main (English branch). Create branch from main → merge source branch (preserving contributor history) → translate Chinese to English → PR → merge → clean up temporary branch. Trigger phrases: sync to main.

stages: [tasks]
gate: manual
---

# Sync to Main Pipeline

Sync changes from the experimental or zh branch to main (English trunk). Core constraint: main must not contain Chinese content, while preserving the original contributors' commit history.

**Language Policy**:
- `zh` — Chinese-first, rapid iteration
- `main` — English-only, release-grade
- Never merge zh/experimental directly into main (it would bring in Chinese)

**Context Links (at least one)**:
- Based on: none
- Related: none

---

## Task 1: Confirm Scope

**Goal**: Confirm the source branch and scope of changes to sync

**Steps**:
1. Confirm the source branch (usually `experimental`, sometimes `zh`)
2. Run `git diff --stat main..<source-branch>` to view the diff
3. Categorize files:
   - **Scripts/Code** (`.sh`, `.py`, `.json`): Usually already in English or bilingual-compatible, sync directly
   - **Documentation** (`.md`): Needs translation
   - **Deleted files**: Sync directly
   - **Binary/Config**: Sync directly
4. Report the scope to the user and confirm whether to sync everything

**Completion Criteria**: User confirms sync scope

---

## Task 2: Create Branch and Merge

**Goal**: Create a sync branch from main and merge the source branch to preserve contributor history

**Steps**:
1. `git checkout main && git pull kingkongshot main`
2. `git checkout -b sync/zh-to-main-<date>[-topic]`
3. `git merge <source-branch> -X theirs --no-edit`
   - `-X theirs`: On conflicts, take the source branch version (source branch is the latest)
   - If only a few files changed, you can also use `git checkout <source-branch> -- <file>` to pick files individually
4. Confirm merge succeeded with no remaining conflicts

**Completion Criteria**: Sync branch contains the complete commit history from the source branch, no conflicts

---

## Task 3: Translation

**Goal**: Translate all Chinese content to English

**Translation Rules**:
- Translate all Chinese text to English
- Keep code, paths, file references, and variable names unchanged
- Keep markdown structure, frontmatter, and HTML tags unchanged
- Keep bilingual regex patterns unchanged (e.g., `探索减负|Exploration Reduction`)
- Change `git clone -b zh` to `git clone -b main`
- Change `[English README](...main...)` to `[中文 README](...zh...)`
- Translate Chinese output strings in scripts (e.g., quoted text in `maintain-project-state.sh`)

**Steps**:
1. Run `grep -rln '[一-龥]'` to find all files containing Chinese
2. Exclude known bilingual regex patterns (intentionally kept in scripts)
3. For files that need translation, translate in parallel batches (using the Agent tool)
4. After translation, run `grep '[一-龥]'` again to verify only intentionally retained Chinese remains (e.g., language switch links, bilingual regex)

**Completion Criteria**: `grep -rn '[一-龥]'` returns only intentionally retained entries (e.g., language switch links, bilingual regex)

---

## Task 4: PR and Merge

**Goal**: Create PR, merge, and clean up

**Steps**:
1. Commit translation changes:
   ```bash
   git add -A
   git commit -m "translate: sync <source> to main (English)"
   ```
   If there are external contributors, add `Co-authored-by:` annotations
2. Push to remote:
   ```bash
   git push kingkongshot sync/zh-to-main-<date>[-topic]
   ```
3. Create PR:
   ```bash
   gh pr create --repo kingkongshot/Pensieve --base main --head sync/zh-to-main-<date>[-topic] \
     --title "<title>" --body "<summary>"
   ```
4. Merge PR:
   ```bash
   gh pr merge <number> --repo kingkongshot/Pensieve --merge
   ```
5. Clean up temporary branch:
   ```bash
   git checkout main && git pull kingkongshot main
   git branch -D sync/zh-to-main-<date>[-topic]
   git push kingkongshot --delete sync/zh-to-main-<date>[-topic]
   ```

**Completion Criteria**: PR has been merged into main, temporary branch deleted (both local and remote)

---

## Failure Fallback

1. **Merge conflicts cannot be auto-resolved**: Retry with `-X theirs`, or checkout files individually and then translate.
2. **Residual Chinese remains after translation**: Manually inspect and fix. Common missed spots: Chinese strings in scripts, Chinese comments in documentation.
3. **PR creation fails (network timeout)**: Retry `gh pr create` with simplified body content.
4. **Push rejected (auth issue)**: Run `gh auth switch --user kingkongshot` and retry.
