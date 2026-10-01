## Summary

<!-- What changed and why, in your own words. Keep it short. -->

## Linked issue

Fixes #

## How I verified

<!-- Which API calls you ran, against which environment, and what came back.
     For a new or changed skill: the prompt you used to trigger it and what the agent did. -->

## Checklist

- [ ] `npx skills add . --list` lists every skill under `skills/`
- [ ] Frontmatter `name` matches the skill directory and `description` says when to trigger
- [ ] Examples use `https://api.blocks.team` and `$BLOCKS_API_KEY`; no real keys or internal hosts
- [ ] Docs links resolve and the skill does not restate what the public docs already cover
- [ ] PR title follows Conventional Commits (`type(scope): summary`)
