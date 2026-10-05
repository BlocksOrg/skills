<p align="center">
  <a href="https://blocks.team">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset=".github/assets/blocks-logo-dark.svg">
      <img alt="Blocks" src=".github/assets/blocks-logo-light.svg" width="220">
    </picture>
  </a>
</p>

# Blocks Agent Skills

[![CI](https://github.com/BlocksOrg/skills/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/BlocksOrg/skills/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)

Installable `SKILL.md` skills for working with the [Blocks](https://blocks.team) REST API from AI coding agents.

## Install

List the skills in this repo:

```bash
npx skills add https://github.com/BlocksOrg/skills --list
```

Install every skill globally:

```bash
npx skills add https://github.com/BlocksOrg/skills --all --global
```

Install a single skill:

```bash
npx skills add https://github.com/BlocksOrg/skills --skill blocks-api --global
```

Omit `--global` to install into the current project instead of your home directory.

Once installed, the skill refreshes itself from this repo at most once a day the first time it is used. Set `BLOCKS_SKILLS_NO_UPDATE=1` to disable that.

One-liner alternative:

```bash
curl -fsSL https://raw.githubusercontent.com/BlocksOrg/skills/main/install.sh | sh
```

## Skills

| Skill | What it does |
| --- | --- |
| [`blocks-api`](skills/blocks-api/SKILL.md) | Fetch an existing Blocks session by ID, read its plan and transcript as an overview, and drill into tool calls when more detail is needed. Requires `BLOCKS_API_KEY`. |

## Verify

After installing, ask your agent:

> Fetch the transcript for Blocks session `<session-id>` and summarize what the agent did.

## Source of truth

The skills follow the public REST API docs: https://docs.blocks.team/rest-api/quick-start

## License

MIT
