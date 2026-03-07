# 共享规则

## 根规则

1. `.src/` 是系统文件目录；不要把用户数据或运行时状态写进去。
2. `.state/` 是隐藏运行时状态目录；报告、marker、缓存等脏数据写这里。
3. `maxims/decisions/knowledge/pipelines` 是用户数据目录；除此之外，只有根目录生成型 `SKILL.md` 可以被维护脚本重写。
4. 先确认再执行。用户没明确要求时，不自动跑长流程。
5. 先读规范再写数据：写 maxim/decision/knowledge/pipeline 前先读 `.src/references/` 里的对应规范。
6. 链接保持连通：`decision/pipeline` 至少一条 `[[...]]` 链接。

## 路径约定

- 工具规范：`.src/tools/*.md`
- 执行脚本：`.src/scripts/*.sh`
- 隐藏模板：`.src/templates/**`
- 隐藏运行时状态：`.state/**`
- 用户数据：
  - `maxims/*.md`
  - `decisions/*.md`
  - `knowledge/*/content.md`
  - `pipelines/run-when-*.md`

## 语义层

- `knowledge` = IS（事实）
- `decision` = WANT（取舍）
- `maxim` = MUST（硬规则）
- `pipeline` = HOW（流程）

## 何时用 migrate / upgrade

- 旧路径、关键文件漂移、旧 graph 残留：`migrate`
- 更新 skill 源码或刷新安装：`upgrade`
