# 用户数据结构迁移规范

Doctor / Migrate 共用的结构历史、目标结构与处理规则（单一事实源）。结构检查统一由脚本 `<SYSTEM_SKILL_ROOT>/tools/doctor/scripts/scan-structure.sh` 承载。

## 当前目标结构（Latest, Active）

唯一目标根目录：`<project>/.claude/skills/pensieve/`

最小目录结构：
- `maxims/`
- `decisions/`
- `knowledge/`
- `pipelines/`
- `loop/`

关键文件（初始化后应存在，且 Migrate 需对齐主体内容）：
- `pipelines/run-when-reviewing-code.md`
- `pipelines/run-when-committing.md`
- `knowledge/taste-review/content.md`

关键文件内容来源（单一事实源）：
- `<SYSTEM_SKILL_ROOT>/tools/upgrade/templates/pipeline.run-when-reviewing-code.md`
- `<SYSTEM_SKILL_ROOT>/tools/upgrade/templates/pipeline.run-when-committing.md`
- `<SYSTEM_SKILL_ROOT>/knowledge/taste-review/content.md`

自动维护文件（允许工具更新）：
- `SKILL.md`

## 历史结构与处理规则

| 历史结构 | 状态 | 处理动作 |
|---|---|---|
| `<project>/skills/pensieve/` | deprecated | 迁移用户数据到目标根目录后删除旧系统副本 |
| `<project>/.claude/pensieve/` | deprecated | 迁移用户数据到目标根目录后删除旧目录 |
| `<user-home>/.claude/skills/pensieve/` | deprecated | 删除（仅保留项目级用户数据根） |
| `<user-home>/.claude/pensieve/` | deprecated | 删除（仅保留项目级用户数据根） |
| `<project>/.claude/skills/pensieve/{_pensieve-graph.md,pensieve-graph.md,graph.md}` | deprecated | 删除（图谱仅保留在 `SKILL.md#Graph`） |
| `<project>/.claude/skills/pensieve/{maxims,decisions,knowledge,pipelines,loop}/{README*.md,readme*.md}` | deprecated | 删除（规范单一事实源在插件侧 `<SYSTEM_SKILL_ROOT>/*/README.md`） |
| `<project>/.claude/skills/pensieve/` | active | 作为唯一读写根目录 |

## 迁移判定（给 Doctor/Migrate）

判为"存在结构迁移问题"的条件：
1. 发现 deprecated 路径与 active 路径并行存在（双源）。
2. active 路径缺失最小目录结构。
3. active 路径缺失关键种子文件。
4. 关键文件主体内容与模板不一致（`pipeline` 的“基于/导致/相关”行仅校验键，不校验值）。
5. 发现独立 graph 文件（`_pensieve-graph*.md` / `pensieve-graph*.md` / `graph*.md`）。
6. 发现项目级子目录历史规范 README 副本（`{maxims,decisions,knowledge,pipelines,loop}/{README*.md,readme*.md}`）。

判为"结构层 no-op"的条件：
1. 仅存在 active 路径。
2. 最小目录结构齐全。
3. 关键种子文件齐全且主体内容与模板一致（`pipeline` 的“基于/导致/相关”行值可按项目实际维护）。
4. 不存在 deprecated 路径与独立 graph 文件。
5. 不存在项目级子目录历史规范 README 副本。

## 关键文件内容对齐策略

当关键文件缺失或主体内容不一致时，Migrate 必须执行完整对齐：
1. 若目标文件存在，先备份为 `*.bak.<timestamp>`。
2. 使用模板文件覆盖目标文件。
3. 在迁移报告中列出被替换文件与备份路径。

## 迁移内容边界

允许迁移：
- `maxims/*.md`（非系统 `_` 前缀）
- `decisions/*.md`
- `knowledge/**`
- `pipelines/*.md`
- `loop/**`

不应迁移：
- 插件内系统文件（`<SYSTEM_SKILL_ROOT>/` 下内容）
- 历史系统副本中的模板/脚本/说明文档（除明确属于用户数据的条目外）
- 项目级子目录历史规范 README 副本（`{maxims,decisions,knowledge,pipelines,loop}/{README*.md,readme*.md}`）

## 维护规则

1. 目录结构发生变化时，先更新本文件，再更新 Doctor/Migrate 文档。
2. 若 Doctor/Migrate 与本文件冲突，以本文件为准。
