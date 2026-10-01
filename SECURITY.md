# Security

## What this repository handles

- This repository ships markdown skill files and a shell installer. Nothing here runs on
  its own; an AI coding agent reads the skills and decides what to do.
- **`BLOCKS_API_KEY`** is the only secret the skills refer to. It stays in your environment
  and is sent only as an `Authorization: ApiKey` header to `https://api.blocks.team`. The
  skills never ask an agent to print it, write it to disk, or send it anywhere else.
- Presigned artifact URLs returned by the API are fetched without the `Authorization`
  header, as the skills state, so the key is never sent to a storage host.
- `install.sh` runs `npx skills add` against this repository and nothing else. CI checks
  that every example uses the public host and a placeholder key.

## Trust boundaries

- `main` requires review and passing checks, so what a user installs is what was reviewed.
- What an agent does with a session it reads is governed by the agent, its configuration,
  and the credentials it holds. These skills only describe how to call the API.

## Reporting a vulnerability

Please report suspected vulnerabilities privately via
[GitHub's private vulnerability reporting](https://github.com/BlocksOrg/skills/security/advisories/new)
rather than opening a public issue. Include a description, reproduction steps, and impact.
We aim to acknowledge reports within a few business days.
