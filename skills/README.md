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
| `codex-cli` | 编排 OpenAI Codex CLI 进行并行任务执行 | 需要预装 [Codex CLI](https://developers.openai.com/codex/cli/) |

## 常见问题 (Troubleshooting)

### Windows Git Bash 环境下的执行超时/无输出问题

**现象**：
在 Windows Git Bash 环境中运行 Skill（如 `codex-cli`）时，命令执行出现 **无限等待 (Timeout)** 或 **无任何内容返回 (No content)**。

**原因**：
Claude Code 在部分 Windows 环境下无法自动定位到正确的 Bash 执行路径。

**解决方案**：
此问题可以通过显式指定 Bash 路径解决（参考 GitHub Issue [#5041](https://github.com/anthropics/claude-code/issues/5041)）。

1. **设置环境变量**：新建系统环境变量 `CLAUDE_CODE_GIT_BASH_PATH`。
2. **填入路径**：值为你的 `bash.exe` 绝对路径。
   * 示例：`D:\Program Files\Git\bin\bash.exe` (请根据你 Git 的实际安装位置修改)。
3. **重启生效**：设置完成后，请务必**重启电脑**，确保 Claude Code 能够正确加载该配置。
