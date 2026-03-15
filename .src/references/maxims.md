# Maxims（准则）

跨项目、跨问题的长期 MUST 级规则。

## 放在这里的标准

只有同时满足下面几条，才配进 `maxims/`：

1. 换项目仍成立
2. 换语言仍成立
3. 违反它会显著提高回归风险
4. 能用一句话讲清楚

如果它只在当前项目有效，那不是 `maxim`，那是 `decision`。

## 存储位置

```text
<project>/.pensieve/maxims/
└── {one-sentence-conclusion}.md
```

每条准则一个文件。  
初始化时会从 `.src/templates/maxims/` 种子化默认条目；之后用户可自由修改，升级不覆盖。

## 推荐格式

```markdown
# {一句话结论}

## 一句话结论
> {可直接执行的一句话}

## 指导规则
- Rule 1
- Rule 2

## 边界
- 什么情况下不适用

## 上下文链接（推荐）
- 基于：[[相关 decision 或 knowledge]]
- 导致：[[相关 pipeline 或 decision]]
- 相关：[[相关 maxim]]
```

## 规则

- `maxim` 应保持稀缺，不要把一次性偏好塞进来
- 链接是推荐项，但有来源时最好写清楚
- `基于` 只能指向 `knowledge/decision`
- `导致` 只能指向 `pipeline/decision`
- `相关` 适合指向平行 `maxim`
