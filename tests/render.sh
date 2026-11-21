#!/usr/bin/env bash
# Offline after tool installation; mutate only disposable local Git fixtures.
set -euo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
# Resolve mise shims before replacing HOME, so no real user state is needed later.
tool_dirs=()
for tool in copier just mise pre-commit betterleaks actionlint shfmt fnox check-yaml end-of-file-fixer trailing-whitespace-fixer python3 git tar; do
	tool_path=$(command -v "$tool") || {
		printf 'Missing prerequisite: %s (run mise install before this suite)\n' "$tool" >&2
		exit 1
	}
	case "$tool_path" in
	*/mise/shims/*) tool_path=$(mise which "$tool") ;;
	esac
	tool_dirs+=("$(dirname -- "$tool_path")")
done
printf -v installed_path '%s:' "${tool_dirs[@]}"
export PATH="${installed_path}/usr/bin:/bin"

work=$(mktemp -d "${TMPDIR:-/tmp}/copier-base-render.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
export HOME="$work/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export PRE_COMMIT_HOME="$XDG_CACHE_HOME/pre-commit"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_ALLOW_PROTOCOL=file
export GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME='Template Test'
export GIT_AUTHOR_EMAIL='template-test@example.invalid'
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export MISE_TRUSTED_CONFIG_PATHS="$work"
export MISE_AUTO_INSTALL=0
export MISE_YES=1
export LC_ALL=C
export TZ=UTC
unset BW_SESSION RBW_PROFILE FNOX_PROFILE FNOX_CONFIG_FILE MISE_CONFIG_FILE MISE_ENV_FILE
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"

fixture="$work/template"
mkdir -p "$fixture"
# Copy working content, not its Git metadata/tags or local user configuration.
tar -C "$source_dir" --exclude=.git -cf - . | tar -C "$fixture" -xf -
git -C "$fixture" init -b main
git -C "$fixture" add .
git -C "$fixture" -c core.hooksPath=/dev/null commit -m 'feat: create test template'
git -C "$fixture" tag v0.1.0

copy() {
	local destination=$1
	shift
	copier copy --defaults --vcs-ref v0.1.0 \
		-d project_name=demo-app -d description=Demo "$@" "$fixture" "$destination"
}

project="$work/default"
copy "$project"
[[ -f "$project/.copier-answers.base.yml" ]]
[[ -L "$project/CLAUDE.md" ]]
[[ $(readlink "$project/CLAUDE.md") == AGENTS.md ]]
[[ $(wc -l <"$project/AGENTS.md") -lt 60 ]]
[[ -f "$project/LICENSE" ]]
[[ ! -e "$project/.copier-answers.infra-ops.yml" ]]

python3 - "$project" "$fixture" <<'PY'
import json
import pathlib
import sys
import tomllib

project, fixture = map(pathlib.Path, sys.argv[1:])
provider = tomllib.loads((project / '.config/fnox/provider.toml').read_text())['providers']['vault']
assert provider == {'type': 'bitwarden', 'backend': 'rbw', 'folder': 'proj', 'auth_command': 'rbw unlock'}
config = tomllib.loads((project / 'fnox.toml').read_text())
assert config['import'] == ['.config/fnox/provider.toml']
assert config['secrets'] == {}
answers = (project / '.copier-answers.base.yml').read_text()
assert '_commit: v0.1.0' in answers
assert f'_src_path: {fixture}' in answers
assert 'project_slug: demo-app' in answers
assert 'backend = "rbw"' not in answers
policy = json.loads((project / '.omp/permissions.json').read_text())
assert policy['allowOutside'] == [] and policy['allowedPaths'] == []
assert 'git push' in policy['ask']
sandbox = tomllib.loads((project / '.agents/sandbox.toml').read_text())
assert sandbox['network'] == 'none' and sandbox['secrets'] == 'fnox'
assert sandbox['allow_domains'] == sandbox['allow_private'] == sandbox['extra_rw_paths'] == []
PY

# A real empty Git repo is necessary for the generated pre-commit gate.
git -C "$project" init -b main
git -C "$project" add .
git -C "$project" -c core.hooksPath=/dev/null commit -m 'feat: create generated project'
(
	cd "$project"
	just --list
	just check
	just doctor
	pre-commit run --all-files
	actionlint
)

# Whitespace and EOF hooks ignore DXF/SVG exports while still checking normal text.
mkdir -p "$project/assets"
printf '0\nSECTION  \nEOF' >"$project/assets/part.dxf"
printf '<svg>  </svg>' >"$project/assets/diagram.svg"
printf '<svg>  </svg>' >"$project/assets/UPPER.SVG"
git -C "$project" add assets/part.dxf assets/diagram.svg assets/UPPER.SVG
(
	cd "$project"
	pre-commit run end-of-file-fixer --all-files
	pre-commit run trailing-whitespace --all-files
)
python3 - "$project" <<'PY'
import pathlib
import sys

project = pathlib.Path(sys.argv[1])
assert (project / 'assets/part.dxf').read_bytes() == b'0\nSECTION  \nEOF'
assert (project / 'assets/diagram.svg').read_bytes() == b'<svg>  </svg>'
assert (project / 'assets/UPPER.SVG').read_bytes() == b'<svg>  </svg>'
PY
printf 'trailing space  ' >"$project/plain.txt"
if (cd "$project" && pre-commit run end-of-file-fixer --files plain.txt >/dev/null 2>&1); then
	printf 'end-of-file-fixer unexpectedly ignored plain.txt\n' >&2
	exit 1
fi
printf 'trailing space  \n' >"$project/plain.txt"
if (cd "$project" && pre-commit run trailing-whitespace --files plain.txt >/dev/null 2>&1); then
	printf 'trailing-whitespace unexpectedly ignored plain.txt\n' >&2
	exit 1
fi
rm -f "$project/plain.txt"
git -C "$project" reset -q -- assets/part.dxf assets/diagram.svg assets/UPPER.SVG
rm -rf "$project/assets"

# Different backend/profile, quoted TOML values, and conditional file omission.
bw_project="$work/bw"
copy "$bw_project" -d bw_backend=bw -d 'bw_profile=work "vault"' \
	-d 'secrets_folder=team "ops"' -d license=none -d ci=false
[[ ! -e "$bw_project/LICENSE" ]]
[[ ! -e "$bw_project/.github/workflows/ci.yml" ]]
python3 - "$bw_project" <<'PY'
import pathlib
import sys
import tomllib

project = pathlib.Path(sys.argv[1])
provider = tomllib.loads((project / '.config/fnox/provider.toml').read_text())['providers']['vault']
assert provider == {'type': 'bitwarden', 'backend': 'bw', 'folder': 'team "ops"', 'profile': 'work "vault"'}
assert 'auth_command' not in provider
PY

# Default slug transformation, strict validator, explicit answers-file override.
copy "$work/named" -d 'project_name=Demo App'
if copy "$work/invalid" -d project_slug=Bad_Slug; then
	printf 'Invalid slug unexpectedly accepted\n' >&2
	exit 1
fi
copy "$work/custom-answers" --answers-file .copier-answers.custom.yml
[[ -f "$work/custom-answers/.copier-answers.custom.yml" ]]
[[ ! -e "$work/custom-answers/.copier-answers.base.yml" ]]

# Earlier imports win: project > archetype > base, then fall back to archetype.
cat >"$project/archetype.just" <<'JUST'
lint:
    @echo archetype-lint
JUST
cat >"$project/project.just" <<'JUST'
lint:
    @echo project-lint
JUST
[[ $(cd "$project" && just lint) == project-lint ]]
printf '# Project has no lint override.\n' >"$project/project.just"
[[ $(cd "$project" && just lint) == archetype-lint ]]

# Exercise a tagged Copier update, preserving every user-owned starter.
cat >>"$project/project.just" <<'JUST'

custom:
    @echo custom
JUST
cat >>"$project/fnox.toml" <<'TOML'
# Project-owned reference; it is never resolved by offline checks.
CUSTOM_TOKEN = { provider = "vault", value = "demo-app/CUSTOM_TOKEN" }
TOML
printf '\n# User sandbox choice.\n' >>"$project/.agents/sandbox.toml"
printf '\nUser-owned README marker.\n' >>"$project/README.md"
printf '\nUser-owned project context marker.\n' >>"$project/.agents/project.md"
python3 - "$project" <<'PY'
import json
import pathlib
import sys

policy = pathlib.Path(sys.argv[1]) / '.omp/permissions.json'
data = json.loads(policy.read_text())
data['ask'].append('deploy-production')
policy.write_text(json.dumps(data, indent=2) + '\n')
PY
mkdir "$work/preserved"
for file in project.just fnox.toml README.md .agents/project.md .agents/sandbox.toml .omp/permissions.json; do
	cp "$project/$file" "$work/preserved/$(basename "$file")"
done
git -C "$project" add .
git -C "$project" -c core.hooksPath=/dev/null commit -m 'feat: customize generated project'
python3 - "$fixture/template/.config/fnox/provider.toml.jinja" <<'PY'
import pathlib
import sys

provider = pathlib.Path(sys.argv[1])
provider.write_text(provider.read_text().replace('folder = {{ secrets_folder | to_json }}', 'folder = "updated-folder"'))
PY
git -C "$fixture" add .
git -C "$fixture" -c core.hooksPath=/dev/null commit -m 'feat: update provider layer'
git -C "$fixture" tag v0.2.0
(
	cd "$project"
	copier update --defaults --answers-file .copier-answers.base.yml --vcs-ref v0.2.0
)
for file in project.just fnox.toml README.md .agents/project.md .agents/sandbox.toml .omp/permissions.json; do
	cmp "$project/$file" "$work/preserved/$(basename "$file")"
done
python3 - "$project" <<'PY'
import pathlib
import sys
import tomllib

project = pathlib.Path(sys.argv[1])
provider = tomllib.loads((project / '.config/fnox/provider.toml').read_text())['providers']['vault']
assert provider['folder'] == 'updated-folder'
assert '_commit: v0.2.0' in (project / '.copier-answers.base.yml').read_text()
assert not list(project.rglob('*.rej'))
assert (project / 'CLAUDE.md').is_symlink()
PY
printf 'copier-base render and update assertions passed\n'
