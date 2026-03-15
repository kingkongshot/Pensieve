---
id: run-when-syncing-to-main
type: pipeline
title: Sync to Main Pipeline
status: active
created: 2026-03-15
updated: 2026-03-15
tags: [pensieve, pipeline, sync, translation]
name: run-when-syncing-to-main
description: 将 experimental/zh 分支的变更同步到 main（英文分支）。从 main 建分支 → merge 源分支（保留贡献者历史）→ 翻译中文为英文 → PR → merge → 清理临时分支。触发词：sync to main, 同步到 main。

stages: [tasks]
gate: manual
---

# Sync to Main Pipeline

将 experimental 或 zh 分支的变更同步到 main（英文主干）。核心约束：main 不得包含中文内容，同时保留原始贡献者的 commit 历史。

**语言政策**：
- `zh` — 中文优先，快速迭代
- `main` — 纯英文，发布级
- 永远不要直接 merge zh/experimental 到 main（会带入中文）

**Context Links (at least one)**:
- Based on: none
- Related: none

---

## Task 1: 确认范围

**目标**：确认要同步的源分支和变更范围

**步骤**：
1. 确认源分支（通常是 `experimental`，有时是 `zh`）
2. 运行 `git diff --stat main..<source-branch>` 查看差异
3. 分类文件：
   - **脚本/代码**（`.sh`、`.py`、`.json`）：通常已英文或双语兼容，直接同步
   - **文档**（`.md`）：需要翻译
   - **删除的文件**：直接同步
   - **二进制/配置**：直接同步
4. 向用户汇报范围，确认是否全部同步

**完成标准**：用户确认同步范围

---

## Task 2: 创建分支并 merge

**目标**：从 main 创建 sync 分支，merge 源分支以保留贡献者历史

**步骤**：
1. `git checkout main && git pull kingkongshot main`
2. `git checkout -b sync/zh-to-main-<date>[-topic]`
3. `git merge <source-branch> -X theirs --no-edit`
   - `-X theirs`：冲突时取源分支版本（源分支是最新的）
   - 如果只有少量文件变更，也可以 `git checkout <source-branch> -- <file>` 逐文件取
4. 确认 merge 成功，无遗留冲突

**完成标准**：sync 分支包含源分支的完整 commit 历史，无冲突

---

## Task 3: 翻译

**目标**：将所有中文内容翻译为英文

**翻译规则**：
- 翻译所有中文文本为英文
- 保持代码、路径、文件引用、变量名不变
- 保持 markdown 结构、frontmatter、HTML 标签不变
- 双语 regex 模式不变（如 `探索减负|Exploration Reduction`）
- `git clone -b zh` 改为 `git clone -b main`
- `[English README](...main...)` 改为 `[中文 README](...zh...)`
- 脚本中的中文输出字符串需翻译（如 `maintain-project-state.sh` 中的引用文本）

**步骤**：
1. `grep -rln '[一-龥]'` 找出所有含中文的文件
2. 排除已知的双语 regex 模式（在脚本中故意保留的）
3. 对需要翻译的文件，按批次并行翻译（使用 Agent 工具）
4. 翻译完成后再次 `grep '[一-龥]'` 验证，确保只剩语言切换链接等故意保留的中文

**完成标准**：`grep -rn '[一-龥]'` 只返回故意保留的条目（如语言切换链接、双语 regex）

---

## Task 4: PR 并合并

**目标**：创建 PR、merge、清理

**步骤**：
1. 提交翻译变更：
   ```bash
   git add -A
   git commit -m "translate: sync <source> to main (English)"
   ```
   如有外部贡献者，添加 `Co-authored-by:` 标注
2. 推送到远端：
   ```bash
   git push kingkongshot sync/zh-to-main-<date>[-topic]
   ```
3. 创建 PR：
   ```bash
   gh pr create --repo kingkongshot/Pensieve --base main --head sync/zh-to-main-<date>[-topic] \
     --title "<title>" --body "<summary>"
   ```
4. 合并 PR：
   ```bash
   gh pr merge <number> --repo kingkongshot/Pensieve --merge
   ```
5. 清理临时分支：
   ```bash
   git checkout main && git pull kingkongshot main
   git branch -D sync/zh-to-main-<date>[-topic]
   git push kingkongshot --delete sync/zh-to-main-<date>[-topic]
   ```

**完成标准**：PR 已合入 main，临时分支已删除（本地和远端）

---

## Failure Fallback

1. **Merge 冲突无法自动解决**：用 `-X theirs` 重试，或逐文件 checkout 后翻译。
2. **翻译后仍有残留中文**：手动检查并修复，常见遗漏点：脚本中的中文字符串、文档中的中文注释。
3. **PR 创建失败（网络超时）**：重试 `gh pr create`，简化 body 内容。
4. **推送被拒（auth 问题）**：`gh auth switch --user kingkongshot` 后重试。
