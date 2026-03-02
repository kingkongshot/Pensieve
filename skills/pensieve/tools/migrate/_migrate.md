---
description: 结构迁移与旧残留清理。仅处理用户数据目录迁移、关键种子文件对齐、历史残留清理；不做版本升级、不做体检分级。
---

# 迁移工具

> 工具边界见 `<SYSTEM_SKILL_ROOT>/references/tool-boundaries.md` | 共享规则见 `<SYSTEM_SKILL_ROOT>/references/shared-rules.md`

## Tool Contract

### Use when
- 用户要求迁移旧版本用户数据
- 用户要求清理旧路径/旧 graph/旧 README 残留
- doctor 报告迁移类 MUST_FIX（旧路径并存、关键文件漂移、历史残留未清理）

### Failure fallback
- 迁移冲突：输出 `*.migrated.*` 文件列表，要求人工合并
- 模板缺失：停止并提示修复插件安装
- 文件系统写入失败：输出失败路径与重试命令

## 执行原则
1. **只做结构迁移**：迁移目录、关键文件对齐、残留清理。
2. **不做版本动作**：不执行 marketplace/plugin update。
3. **不做体检结论**：不输出 PASS/PASS_WITH_WARNINGS/FAIL。
4. **doctor 后置**：迁移完成后引导用户手动运行 doctor。

## 标准执行

```bash
bash <SYSTEM_SKILL_ROOT>/tools/migrate/scripts/run-migrate.sh
```

可选：仅预演不落盘

```bash
bash <SYSTEM_SKILL_ROOT>/tools/migrate/scripts/run-migrate.sh --dry-run
```

## 输出要求

迁移完成后必须输出：
- 目录/文件迁移统计
- 冲突文件列表（若有）
- 报告与摘要路径
- 明确下一步命令（手动运行 doctor）：

```bash
bash <SYSTEM_SKILL_ROOT>/tools/doctor/scripts/run-doctor.sh --strict
```
