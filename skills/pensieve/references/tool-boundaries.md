# 工具边界

每个工具有明确职责边界。路由到错误工具时，按此表重定向。

## 职责定位

| 工具 | 职责 | 不负责 |
|------|------|--------|
| `upgrade` | 版本同步 + 插件配置键对齐 | 不给 PASS/FAIL，不做结构迁移与逐文件语义审查 |
| `migrate` | 结构迁移 + 关键文件对齐 + 残留清理 | 不更新插件版本，不给 PASS/FAIL |
| `doctor` | 只读检查 + 合规报告 | 不改用户数据文件，不做迁移（仅允许自动维护 `SKILL.md` 与 auto memory `MEMORY.md` 引导块） |
| `self-improve` | 沉淀经验到四类用户数据 | 不做迁移/检查 |
| `init` | 初始化项目目录 + 种子化 + 基线探索与代码审查（只读） | 不做迁移清理，不直接写入沉淀 |
| `loop` | 拆解复杂任务 + 子代理循环执行 | 小任务直接完成，不开 loop |

## 路由速查

| 用户意图 | 正确工具 | 常见误路由 |
|----------|----------|-----------|
| 更新插件版本 / 插件兼容问题 | `upgrade` | `init`, `doctor`, `migrate` |
| 迁移旧数据 / 清理旧路径 / 关键文件对齐 | `migrate` | `upgrade`, `init` |
| 新项目首次接入 / 补齐种子文件 / 生成首轮审查基线 | `init` | `upgrade`（除非有旧数据） |
| 初始化完成后的合规复检 | `doctor`（必跑） | 跳过 doctor 直接开发 |
| 合规检查 / PASS-FAIL 分级报告 | `doctor` | `upgrade`, `self-improve` |
| 沉淀经验 / 写 maxim / decision / pipeline | `self-improve` | `doctor`, `upgrade` |
| 复杂任务拆解自动执行 | `loop` | 直接执行（小任务） |
| 执行某个具体 pipeline | `loop`（加载 pipeline） | 直接执行（应走 loop） |

## 负面示例

| 用户说 | 不应 | 应转 |
|--------|------|------|
| "项目里有旧版 skills/pensieve/，顺手帮我迁移" | 继续 init | `migrate` |
| "先给我 PASS/FAIL 检查结论" | init 或 upgrade 给结论 | `doctor` |
| "初始化后直接把候选写进 knowledge/decision" | init 直接写入 | `self-improve` |
| "先跑 doctor，再决定要不要迁移" | 强制改成先 `migrate` | `doctor`（若报告迁移/旧路径/旧键问题，再执行 `migrate`） |
| "边检查边帮我改" | doctor 批量修改用户数据文件 | 先 `doctor` 报告，再手动修（仅保留 `SKILL.md`/auto memory 自动维护） |
| "先自动把这次会话都沉淀了，不用我确认" | 自动沉淀 | `self-improve`（可直接写入） |
| "改 1 个文案文件，顺便 loop" | 开 loop | 直接完成 |
| "版本已经最新，仍然直接进入迁移" | 绕过版本检查 | 停在询问 `doctor` 自检 |
| "不跑快检直接给 PASS" | 跳过 frontmatter 快检 | 必须先跑 `check-frontmatter.sh` |
| "还没确认需求，先建 10 个任务" | 跳过确认直接拆分 | 先确认目标再生成任务 |
| "顺手把旧目录也迁了" | self-improve 做迁移 | `migrate` |
| "迁移时顺便给我判定 PASS/FAIL" | migrate 给合规结论 | 先 `migrate` 再 `doctor` |
