# Tool Boundaries

| Tool | Responsible for | Not responsible for |
|---|---|---|
| `init` | Initializing the project `.pensieve/` directory, seeding default content, producing first-round exploration input | Does not write business conclusions directly |
| `upgrade` | Refreshing global skill source code (`~/.claude/skills/pensieve/`) | Does not perform structural migration, does not output PASS/FAIL |
| `migrate` | Legacy data migration, directory structure alignment, key file alignment | Does not update versions, does not output PASS/FAIL |
| `doctor` | Structural and format health checks, outputs a fixed report | Does not modify business code |
| `self-improve` | Distilling maxim/decision/knowledge/pipeline | Does not replace init/migrate/doctor |

## Common redirects

| User request | Correct tool |
|---|---|
| "How do I install/reinstall Pensieve" | Read `.src/references/skill-lifecycle.md` first, then use `init` |
| "Upgrade Pensieve" | `upgrade` |
| "How do I update Pensieve" | Read `.src/references/skill-lifecycle.md` first, then use `upgrade` |
| "Migrate to v2 / clean up old paths" | `migrate` |
| "Check if data has issues" | `doctor` |
| "Distill this experience for future use" | `self-improve` |
