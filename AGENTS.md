# AGENTS.md

Canonical instruction file for AI agents working in this repository.

Follow the shared repo-local rules first:

@docs/conventions/agent-global-rules.md

Then the rules specific to this addon. They are not optional, and every one of
them was written after something broke:

@docs/conventions/addon-rules.md

The backend and frontend style guides do not apply here — this is Lua 5.1
against the WoW 3.3.5a client API and nothing else.

---

## What this project is

A single PvP interface addon for WoW 3.3.5a (Interface 30300), replacing a
stack of overlapping addons with one that shares a single event dispatcher and
a single timer. Public at https://github.com/Karimmm33/FycoPvP.

## The development loop

**This project is the source of truth. The copy inside the WoW client is
disposable.**

```powershell
# 1. edit here, in D:\Projects\FycoPvP
# 2. check every Lua file parses, is ASCII, and has no orphaned references
python scripts\luacheck.py Data.lua Core.lua Modules\*.lua

# 3. push it into the client and test in game
.\scripts\deploy.ps1          # -WhatIf to see what it would do first
#    then /reload in game
```

`deploy.ps1` **mirrors** `Modules\`, `Textures\` and `Voice\`, so anything
edited directly in the client folder is overwritten without warning. Never
treat the client copy as a place to make changes — it exists to be tested and
thrown away.

Nothing that makes this a project — `.git`, `docs\`, `scripts\`, `AGENTS.md`,
`CLAUDE.md` — is deployed. The client folder ends up looking exactly like what
a user unzips, which is the point: you test what you ship.

## Releasing

```powershell
# bump '## Version:' in FycoPvP.toc first -- package.ps1 reads it from there
.\scripts\package.ps1
gh release create v1.17.0 .\dist\FycoPvP-1.17.0.zip --title "FycoPvP 1.17.0" --notes-file notes.md
```

**Never tell anyone to use GitHub's green "Code → Download ZIP" button.** That
archive is named after the branch, so it extracts as `FycoPvP-main`, and WoW
matches a folder name against its `.toc` — the addon simply never appears in
the AddOns list. `Data.lua` also resolves `Voice\` and `Textures\` through the
absolute path `Interface\AddOns\FycoPvP\`, so the media would not load either.
The release zip built by `package.ps1` is the only supported download, and it
verifies its own structure before it finishes.

## Before telling Karim something is done

1. Every `.lua` parses, is ASCII-only, has no invalid escapes, and has no
   orphaned references — `scripts\luacheck.py` checks all four.
2. New commands are in `Core.lua`'s slash handler *and* its `help` output.
3. New modules are in `FycoPvP.toc`, the `Core.lua` defaults table, and the
   options module list.
4. `README.md` covers any new feature and command.
5. Say what was actually verified. A static check is not a runtime check, and
   this addon has shipped broken on exactly that difference.
