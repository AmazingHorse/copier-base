# copier-base

Portable, offline-checkable project underlay for the AmazingHorse template stack.
Requires Copier **9.19.1+**, Git and Bash. Install the pinned tools with `mise install`.

```sh
copier copy --defaults -d project_name=demo-app -d description="Demo" \
  gh:AmazingHorse/copier-base ./demo-app
cd demo-app
git init -b main
git add . && git commit -m "feat: initialize project"
just setup
just check
```

`just setup` downloads tools and installs Git hooks. After setup, `just check` is
fully offline and does not unlock Bitwarden or resolve secrets. The generated
pre-commit hooks use installed system binaries, not network-built hook environments.
Run `mise exec -- just check` if mise is not activated in your shell.

## Layers and ownership

Base answers live in `.copier-answers.base.yml`. An archetype keeps its own answers
file and owns `archetype.just`; project overrides belong in
`project.just`. Imports resolve project > archetype > base. `project.just`, `fnox.toml`,
`README.md`, `.agents/project.md`, `.agents/sandbox.toml` and `.omp/permissions.json`
are starter files: subsequent base renders/updates preserve existing copies.

The provider configuration is base-owned `.config/fnox/provider.toml`.
Project-owned `fnox.toml` imports it and contains only secret references.
Vault layout: folder `proj` (or `secrets_folder`), item `project_slug`, custom field
named after each variable. `bw_backend=rbw` is the Linux default; choose `bw` for
Windows/macOS. `bw_profile` is optional; `ci=false` omits CI. `license=none` omits LICENSE.
Provider values are safely TOML-quoted; no secret values belong in template answers.
`just doctor` reports tool versions and config presence offline. Resolving secret
references with `fnox check` is a separate, explicitly authorized live gate.

Update from the project root, choosing a released tag explicitly:

```sh
copier update --answers-file .copier-answers.base.yml --vcs-ref v0.1.0
```

Commit project changes first, review the update diff and run `just check`.
Answer files are generated Copier state: do not replace the template's metadata
with hand-maintained version fields. Agent and sandbox files describe workspace-only
permissions; the sandbox policy is intent until a launcher enforces it.

## Template development

`just check` runs Actionlint, shfmt's read-only check, and `tests/render.sh`.
The shell suite snapshots this checkout into a throwaway local Git repository,
creates local tags, renders both vault backends, checks recipe precedence, and
exercises Copier update while preserving project-owned content. It never changes
this checkout's tags, requires no network or vault, and isolates HOME/XDG/Git config.
Install tools first; expose real tool paths (for example, `mise exec -- just check`).
CI installs tools before running the same gate. Git actions are pinned to upstream
commit SHAs. No live `smoke` operation runs in CI.
