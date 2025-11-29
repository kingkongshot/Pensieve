# Skills

Claude 技能文件集合。

## 什么是 Skills?

Skills 是包含指令、脚本和资源的专用文件夹，Claude 会在任务相关时自动加载。

Skills 具有四个特点：
- **可组合 (Composable)** - 多个技能可自动协同工作
- **可移植 (Portable)** - 同一格式适用于 Claude Apps、Claude Code 和 API
- **高效 (Efficient)** - 仅在需要时加载相关信息
- **强大 (Powerful)** - 可包含可执行代码以提高可靠性

详细文档请参阅官方博客：https://www.claude.com/blog/skills

## 使用方法

将 skill 文件夹复制到 `~/.claude/skills/` 目录下即可使用。

## 可用技能

| 技能 | 描述 | 依赖 |
|------|------|------|
| `taste-check` | 基于 Linus Torvalds "好品味"哲学的代码审查 | 无 |
| `research` | 使用 GitHub 和 Exa 搜索进行技术研究 | 需要远程 MCP：[mcp.exa.ai](https://mcp.exa.ai/mcp)、[mcp.grep.app](https://mcp.grep.app) |
