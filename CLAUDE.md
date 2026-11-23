# CLAUDE.md

iPXE sources, build configuration, and binaries for FOG Project. `README.md`
describes the layout and the build. `.github/workflows/build.yml` holds the
checks.

## Documentation

User docs live in [FOGProject/fog-docs](https://github.com/FOGProject/fog-docs),
published at <https://docs.fogproject.org/>. Every pull request here ships with
its docs decision. Write it as a `Docs:` line in the pull request body:

- `Docs: FOGProject/fog-docs#<n>` names the fog-docs pull request for the change.
- `Docs: none — <reason>` is for a change that a user cannot see.
- `Docs: needed — <what>` is for when you cannot open the fog-docs pull request.

Where the docs go, under fog-docs `docs/`:

| What changed | fog-docs target |
|---|---|
| A boot script, a menu, or a variable | `kb/customization/ipxe.md`, `kb/customization/ipxe-menu-variables.md`, `kb/customization/advanced-boot-menu.md` |
| A build option or a local build step | `kb/reference/compile_ipxe_binaries.md` |
| A bug fix that a user can see | a `kb/troubleshooting/` entry: the symptom text verbatim, the cause, the fixed-in version, and a workaround |

Follow fog-docs `CLAUDE.md` for the page format.
