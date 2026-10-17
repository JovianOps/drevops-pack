#!/usr/bin/env bash
#
# Dispatcher and host-wrapper tests. No Docker required.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPATCHER="${ROOT}/image/drevops"
WRAPPER="${ROOT}/src/drevops.sh"
FAILS=0
PASSES=0

red() { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASSES=$((PASSES + 1))
    printf 'ok  %s\n' "$label"
  else
    FAILS=$((FAILS + 1))
    red "FAIL  ${label}"
    printf '     expected: %s\n     actual:   %s\n' "$expected" "$actual"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASSES=$((PASSES + 1))
    printf 'ok  %s\n' "$label"
  else
    FAILS=$((FAILS + 1))
    red "FAIL  ${label}"
    printf '     missing: %s\n     in: %s\n' "$needle" "$haystack"
  fi
}

assert_status() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" -eq "$actual" ]]; then
    PASSES=$((PASSES + 1))
    printf 'ok  %s\n' "$label"
  else
    FAILS=$((FAILS + 1))
    red "FAIL  ${label} (exit ${actual}, want ${expected})"
  fi
}

run_drevops() {
  local home="$1"
  shift
  DREVOPS_PACK_HOME="$home" "$DISPATCHER" "$@"
}

make_stub() {
  local path="$1" id="$2"
  cat > "$path" <<EOF
#!/usr/bin/env bash
printf 'stub:%s' '$id'
if [[ \$# -gt 0 ]]; then printf ':%s' "\$*"; fi
printf '\n'
EOF
  chmod +x "$path"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOME_OK="${TMP}/pack"
mkdir -p "${HOME_OK}/bin"
make_stub "${HOME_OK}/bin/unique" unique
make_stub "${HOME_OK}/bin/ci-vortex" vortex-ci
make_stub "${HOME_OK}/bin/ci-eddy" eddy-ci
make_stub "${HOME_OK}/bin/eddy" eddy

# commands.tsv: unique + ambiguous `ci`, plus malformed / CR lines that must be ignored.
{
  printf 'vortex-tooling\tci\t%s\n' "${HOME_OK}/bin/ci-vortex"
  printf 'vortex-tooling\tunique\t%s\n' "${HOME_OK}/bin/unique"
  printf 'eddy-tooling\tci\t%s\n' "${HOME_OK}/bin/ci-eddy"
  printf 'eddy-tooling\teddy\t%s\n' "${HOME_OK}/bin/eddy"
  printf '\n'
  printf '# comment\n'
  printf 'onlytwo\tfields\n'
  printf 'broken\tmissingpath\t\n'
  printf 'vortex-tooling\tcrlf\t%s\r\n' "${HOME_OK}/bin/unique"
} > "${HOME_OK}/commands.tsv"

{
  printf 'vortex-tooling\t1.1.3\tcomposer-scripts\tdrevops/vortex-tooling\tok\n'
  printf 'eddy-tooling\t1.0.5\tcomposer-bin\tdrevops/eddy-tooling\tok\n'
  printf 'behat-steps\t*\tcomposer-lib\tdrevops/behat-steps\tok\n'
  printf 'str2name\t-\tcomposer-bin\tdrevops/str2name\tunavailable\n'
} > "${HOME_OK}/tools.tsv"

# --- builtins ---
out="$(run_drevops "$HOME_OK" 2>&1)" || true
assert_contains "empty args show usage" "Usage:" "$out"

out="$(run_drevops "$HOME_OK" help 2>&1)"
assert_contains "help mentions unique commands" "when the name is unique" "$out"
assert_contains "help mentions docker ENTRYPOINT" "docker run --rm IMAGE list" "$out"

out="$(run_drevops "$HOME_OK" --help 2>&1)"
assert_contains "--help is help" "Usage:" "$out"

out="$(run_drevops "$HOME_OK" list 2>&1)"
assert_contains "list shows tools" "vortex-tooling" "$out"
assert_contains "list shows unavailable" "unavailable" "$out"
assert_contains "list shows unique command" "unique" "$out"

out="$(run_drevops "$HOME_OK" ls 2>&1)"
assert_contains "ls aliases list" "TOOL" "$out"

out="$(run_drevops "$HOME_OK" version 2>&1)"
assert_contains "version lists ok tools" "vortex-tooling 1.1.3" "$out"
if [[ "$out" == *str2name* ]]; then
  FAILS=$((FAILS + 1))
  red "FAIL  version should omit unavailable tools"
else
  PASSES=$((PASSES + 1))
  printf 'ok  version omits unavailable tools\n'
fi

# --- docker double-prefix (CMD replaced by `drevops list`) ---
out="$(run_drevops "$HOME_OK" drevops list 2>&1)"
assert_contains "drevops list after ENTRYPOINT still lists" "vortex-tooling" "$out"

out="$(run_drevops "$HOME_OK" drevops unique extra 2>&1)"
assert_eq "drevops unique routes after strip" "stub:unique:extra" "$out"

out="$(run_drevops "$HOME_OK" -- unique 2>&1)"
assert_eq "-- unique routes" "stub:unique" "$out"

# --- tool-less unique command ---
out="$(run_drevops "$HOME_OK" unique --flag 2>&1)"
assert_eq "tool-less unique command" "stub:unique:--flag" "$out"

# --- qualified forms ---
out="$(run_drevops "$HOME_OK" vortex-tooling ci --x 2>&1)"
assert_eq "tool command form" "stub:vortex-ci:--x" "$out"

out="$(run_drevops "$HOME_OK" eddy-tooling/ci 2>&1)"
assert_eq "tool/command form" "stub:eddy-ci" "$out"

# --- ambiguous ---
set +e
out="$(run_drevops "$HOME_OK" ci 2>&1)"
st=$?
set -e
assert_status "ambiguous command exits 1" 1 "$st"
assert_contains "ambiguous names both tools" "vortex-tooling/ci" "$out"
assert_contains "ambiguous names eddy" "eddy-tooling/ci" "$out"
assert_contains "ambiguous suggests qualified form" "drevops <tool> ci" "$out"

# --- unknown ---
set +e
out="$(run_drevops "$HOME_OK" nope 2>&1)"
st=$?
set -e
assert_status "unknown command exits 1" 1 "$st"
assert_contains "unknown mentions list" "drevops list" "$out"

# --- tool named with no command ---
set +e
out="$(run_drevops "$HOME_OK" vortex-tooling 2>&1)"
st=$?
set -e
assert_status "tool without command exits 1" 1 "$st"
assert_contains "tool-only lists its commands" "vortex-tooling/ci" "$out"
assert_contains "tool-only usage" "drevops vortex-tooling <command>" "$out"

# --- library (ok, no commands) ---
set +e
out="$(run_drevops "$HOME_OK" behat-steps 2>&1)"
st=$?
set -e
assert_status "library tool exits 1" 1 "$st"
assert_contains "library explains no CLI" "no CLI commands" "$out"

# --- unavailable optional tool ---
set +e
out="$(run_drevops "$HOME_OK" str2name 2>&1)"
st=$?
set -e
assert_status "unavailable tool exits 1" 1 "$st"
assert_contains "unavailable mentions build" "not available when this image was built" "$out"

set +e
out="$(run_drevops "$HOME_OK" str2name convert 2>&1)"
st=$?
set -e
assert_contains "unavailable tool + command" "not available when this image was built" "$out"

# --- unknown command on a known tool ---
set +e
out="$(run_drevops "$HOME_OK" eddy-tooling missing 2>&1)"
st=$?
set -e
assert_status "unknown command on tool exits 1" 1 "$st"
assert_contains "lists available on that tool" "eddy-tooling/eddy" "$out"

# --- slash edge cases ---
set +e
out="$(run_drevops "$HOME_OK" vortex-tooling/ 2>&1)"
st=$?
set -e
assert_status "trailing slash exits 1" 1 "$st"
assert_contains "trailing slash message" "invalid command" "$out"

set +e
out="$(run_drevops "$HOME_OK" /ci 2>&1)"
st=$?
set -e
assert_contains "leading slash message" "invalid command" "$out"

set +e
out="$(run_drevops "$HOME_OK" a/b/c 2>&1)"
st=$?
set -e
assert_contains "nested slash message" "invalid command" "$out"

# --- CR-stripped lookup ---
out="$(run_drevops "$HOME_OK" crlf 2>&1)"
assert_eq "CRLF command names still match" "stub:unique" "$out"

# --- missing executable ---
HOME_MISS="${TMP}/missing"
mkdir -p "$HOME_MISS"
printf 'ghost\thaunt\t/definitely/not/here\n' > "${HOME_MISS}/commands.tsv"
printf 'ghost\t1\tcomposer-bin\tdrevops/ghost\tok\n' > "${HOME_MISS}/tools.tsv"
set +e
out="$(run_drevops "$HOME_MISS" haunt 2>&1)"
st=$?
set -e
assert_status "missing executable exits 1" 1 "$st"
assert_contains "missing executable mentions doctor" "drevops doctor" "$out"

# --- missing manifests ---
HOME_EMPTY="${TMP}/empty"
mkdir -p "$HOME_EMPTY"
set +e
out="$(run_drevops "$HOME_EMPTY" list 2>&1)"
st=$?
set -e
assert_status "missing manifest exits 1" 1 "$st"
assert_contains "missing manifest path" "manifest not found" "$out"

# --- empty commands.tsv (tool-less bundle) ---
HOME_NONE="${TMP}/none"
mkdir -p "$HOME_NONE"
: > "${HOME_NONE}/commands.tsv"
printf 'libonly\t1\tcomposer-lib\tdrevops/libonly\tok\n' > "${HOME_NONE}/tools.tsv"
set +e
out="$(run_drevops "$HOME_NONE" anything 2>&1)"
st=$?
set -e
assert_status "empty command set unknown exits 1" 1 "$st"
assert_contains "empty command set unknown text" "unknown command" "$out"

set +e
out="$(run_drevops "$HOME_NONE" doctor 2>&1)"
st=$?
set -e
assert_status "doctor fails on empty commands.tsv" 1 "$st"
assert_contains "doctor reports empty commands" "commands.tsv is empty" "$out"

# --- doctor flags a bad path ---
set +e
out="$(run_drevops "$HOME_MISS" doctor 2>&1)"
st=$?
set -e
assert_status "doctor fails on missing bin" 1 "$st"
assert_contains "doctor names the command" "ghost/haunt" "$out"

# --- host wrapper: "$@" is after image, with -- so CMD replacement is clean ---
FAKE="${TMP}/fakebin"
mkdir -p "$FAKE"
cat > "${FAKE}/docker" <<'EOF'
#!/usr/bin/env bash
printf 'DOCKER'
for a in "$@"; do
  printf '\t%s' "$a"
done
printf '\n'
EOF
chmod +x "${FAKE}/docker"
# id is required by the wrapper; use the real one.

set +e
out="$(PATH="${FAKE}:$PATH" DREVOPS_IMAGE=drevops-pack:test bash "$WRAPPER" list 2>&1)"
st=$?
set -e
assert_status "wrapper invokes docker" 0 "$st"
assert_contains "wrapper uses run --rm" $'run\t--rm' "$out"
assert_contains "wrapper ends option parse before image" $'--\tdrevops-pack:test\tlist' "$out"

set +e
out="$(PATH="${FAKE}:$PATH" DREVOPS_IMAGE=drevops-pack:test bash "$WRAPPER" 2>&1)"
st=$?
set -e
assert_contains "wrapper with no args does not pass a command (CMD=help applies)" $'--\tdrevops-pack:test' "$out"
if [[ "$out" == *$'\tdrevops-pack:test\t'* ]]; then
  FAILS=$((FAILS + 1))
  red "FAIL  wrapper with no args should not replace CMD"
  printf '     got: %s\n' "$out"
else
  PASSES=$((PASSES + 1))
  printf 'ok  wrapper with no args leaves CMD to the image\n'
fi

set +e
out="$(PATH="${FAKE}:$PATH" DREVOPS_IMAGE=drevops-pack:test bash "$WRAPPER" --help 2>&1)"
st=$?
set -e
assert_contains "wrapper forwards --help after image" $'--\tdrevops-pack:test\t--help' "$out"

set +e
out="$(PATH="${FAKE}:$PATH" DREVOPS_IMAGE=drevops-pack:test bash "$WRAPPER" drevops list 2>&1)"
st=$?
set -e
assert_contains "wrapper can pass drevops list (dispatcher strips it)" $'--\tdrevops-pack:test\tdrevops\tlist' "$out"

printf '\n%s passed, %s failed\n' "$PASSES" "$FAILS"
[[ "$FAILS" -eq 0 ]]
