# claude-skills

Claude skills for cybersecurity and infrastructure work.

A skill is a folder with a `SKILL.md` that tells Claude how to do one job properly —
the checklist, the format, the gotchas. Claude loads it when the job comes up, so you
get the same quality every time instead of re-explaining yourself.

These are the ones I use in my own work: security assessments, infrastructure
documentation, compliance scaffolding. Written for small and mid-sized organisations,
where there is no dedicated security team.

## Skills

| Skill | What it does |
|-------|--------------|
| _(coming soon)_ | |

## Installing a skill

Copy the skill folder into your skills directory:

**Claude Code / Cowork**

```bash
git clone https://github.com/JAFCasimiro/claude-skills.git
cp -r claude-skills/skills/<skill-name> ~/.claude/skills/
```

**Project-scoped** — commit it alongside your code so the whole team gets it:

```bash
cp -r claude-skills/skills/<skill-name> .claude/skills/
```

Claude picks it up automatically when the task matches the skill's description.

## Writing your own

`_template/SKILL.md` is a starting point. The short version:

- **`name`** — kebab-case, matches the folder name
- **`description`** — this is what decides when the skill fires. Write it as *when to
  use this*, with the words someone would actually type. A vague description means the
  skill never triggers.
- **Body** — the procedure. Concrete steps, real commands, the output format you want.
  Write it for someone competent who has not done this specific task before.

Keep `SKILL.md` short. Long reference material goes in separate files in the skill
folder, referenced from the body, so it loads only when needed.

## Contributing

Issues and pull requests are welcome. If you use one of these and it gets something
wrong, an issue describing the case is more useful than a silent fork.

## License

MIT — see [LICENSE](LICENSE).
