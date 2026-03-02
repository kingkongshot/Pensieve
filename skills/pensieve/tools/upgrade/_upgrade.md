---
description: 版本升级与插件配置键对齐。仅做版本对比、拉取最新、插件键清理；不做结构迁移与前置体检。升级完成后引导用户手动运行 doctor。
---

# 升级工具

> 工具边界见 `<SYSTEM_SKILL_ROOT>/references/tool-boundaries.md` | 共享规则见 `<SYSTEM_SKILL_ROOT>/references/shared-rules.md`

## Tool Contract

### Use when
- 用户要求升级 Pensieve
- 用户要求确认升级前后版本变化
- 用户要求修复插件兼容或 enabledPlugins 键漂移

### Failure fallback
- `claude` 命令不可用：停止并返回安装/环境问题
- 版本拉取失败：返回失败日志路径，停止后续动作
- settings.json 语法异常：输出警告并保留原文件

## 执行原则（简化后）
1. **以脚本结果为准**：`run-upgrade.sh` 的 summary/report 是唯一事实源，不做人工推断。
2. **不做升级前结构检查**：upgrade 阶段不运行 doctor，不输出 PASS/FAIL。
3. **升级只做版本动作**：版本比对、拉取最新、插件键/旧插件名清理。
4. **doctor 后置**：升级完成后只引导用户手动运行 doctor。
5. **结构迁移另走 migrate**：旧路径迁移、关键文件对齐、残留清理由 `migrate` 负责。

## 标准执行

```bash
bash <SYSTEM_SKILL_ROOT>/tools/upgrade/scripts/run-upgrade.sh
```

可选：仅预演不落盘

```bash
bash <SYSTEM_SKILL_ROOT>/tools/upgrade/scripts/run-upgrade.sh --dry-run
```

## 输出要求

升级完成后必须输出：
- 升级前版本与升级后版本
- 是否发生版本变化
- 插件配置对齐统计
- 报告与摘要文件路径
- 明确下一步命令（手动运行 doctor）：

```bash
bash <SYSTEM_SKILL_ROOT>/tools/doctor/scripts/run-doctor.sh --strict
```

## 约束
- Upgrade 不得在执行中调用 doctor
- Upgrade 不得输出 doctor 分级结论（PASS/PASS_WITH_WARNINGS/FAIL）
- Upgrade 不得执行用户数据结构迁移（迁移需走 `migrate`）
