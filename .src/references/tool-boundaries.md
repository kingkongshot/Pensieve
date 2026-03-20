# Tool Boundaries

| Tool | Responsible for | Not responsible for |
|---|---|---|
| `init` | Initialize the project `.pensieve/` directory, seed default content, produce first-round exploration input | Does not write business conclusions directly |
| `upgrade` | Refresh global skill source code (`~/.claude/skills/pensieve/`) | Does not perform structural migration; does not produce PASS/FAIL |
| `migrate` | Migrate data from older versions, align directory structure, align key files | Does not update versions; does not produce PASS/FAIL |
| `doctor` | Structural and format health check, output a fixed report | Does not modify business code |
| `self-improve` | Create new entries in `short-term/`, edit existing files in place | Does not replace init/migrate/doctor |
| `refine` | Refine the knowledge base: triage via five-question review + compress to abstract | New entries produced by compress go through short-term |

## Common redirects

| User request | Correct tool |
|---|---|
| "How to install/reinstall Pensieve" | Read `.src/references/skill-lifecycle.md` first, then run `init` |
| "Upgrade Pensieve" | `upgrade` |
| "How to update Pensieve" | Read `.src/references/skill-lifecycle.md` first, then run `upgrade` |
| "Migrate to v2 / clean up old paths" | `migrate` |
| "Check if data has issues" | `doctor` |
| "Capture this experience as knowledge" | `self-improve` |
| "Organize / deduplicate / compress / refine knowledge" | `refine` |
