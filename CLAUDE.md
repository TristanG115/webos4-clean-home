# CLAUDE.md

All agent guidance for this repository lives in **AGENTS.md** (what the project is, layout, how it works, safety net, workflow, gotchas, how to port it to another TV
with or without root, and the pre-push privacy audit). Claude Code imports it here:

@AGENTS.md

## Claude-specific reminders
- The owner's one rule: **don't break the TV, and always keep a way back in** (`./revert.sh`, Telnet, the init hook). Run `tools/check.sh` after every TV change and record it in `CHANGES.md`.
- **Change notes**: every push that touches `tv/` needs a new first entry in `tv/notes.json` plus the same `tv/VERSION`, in plain language for non-technical family (AGENTS.md section 11); `node tools/release-check.js` must pass. Pushing ships to every TV that auto-updates from the repo.
- The owner's photos (`photos-trist/`, `tv/launcher/photos/`) and `tv-report/` are private and git-ignored: never commit or publish them; run the audit in AGENTS.md section 12 before any push.
- **Commit incrementally with a detailed log** of what was done after each finished piece of work, then **push once at the end of the task** (pre-authorized by the owner for their own repo, after the AGENTS.md section 12 audit). Still ask before issues, PRs or posting anywhere else. Drafts for upstream are in `UPSTREAM-DRAFT.md`.
- On Windows use the Bash tool for the TV (`./tv.sh`); put anything containing `pkill -f` / `pgrep -f` in a script file (`./tv.sh -s < file`), or it kills your own ssh session.
- Prefer the editor tool over bash heredocs for multi-line source edits (CRLF/escape/comment pitfalls, see AGENTS.md section 7).
