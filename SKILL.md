---
name: pensieve
description: >-
  项目知识库和工作流路由器。
  knowledge/ 缓存已探索的文件位置、模块边界和调用链，可直接复用；
  decisions/maxims 是已确立的架构决策和编码标准，遵循而非重新讨论；
  pipelines 是可复用工作流；short-term/ 暂存新结论，到期后 promote 或删除。
  完成任务后使用 self-improve 捕获新洞察。
  提供 init、upgrade、migrate、doctor、self-improve 五个工具。
---

# Pensieve

将用户请求路由到正确的工具。不确定时先确认。

## Routing
- Init: 初始化当前项目用户数据目录并填充种子文件。工具规格：`.src/tools/init.md`。
- Upgrade: 刷新全局 git clone 中的 Pensieve skill 源代码。工具规格：`.src/tools/upgrade.md`。
- Migrate: 结构迁移和遗留清理。工具规格：`.src/tools/migrate.md`。
- Doctor: 只读扫描当前项目用户数据目录。工具规格：`.src/tools/doctor.md`。
- Self-Improve: 提取可复用结论并写入用户数据。工具规格：`.src/tools/self-improve.md`。
- Refine: 精炼知识库（triage 五问审阅 + compress 压缩抽象）。工具规格：`.src/tools/refine.md`。
- Graph View: 读取 `<project-root>/.pensieve/.state/pensieve-user-data-graph.md`。

## Project Data
项目级用户数据存储在 `<project-root>/.pensieve/`。
当前项目的生命周期状态见 `.pensieve/state.md`；知识图谱见 `.pensieve/.state/pensieve-user-data-graph.md`（按需读取）。
