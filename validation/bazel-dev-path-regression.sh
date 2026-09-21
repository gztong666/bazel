#!/usr/bin/env bash
# Usage: bash bazel-dev-path-regression.sh ORIGINAL_SCRIPT FIXED_SCRIPT
# Exercises the complete wrapper with fake executables; no Bazel build is needed.
set -euo pipefail

original=$(realpath "$1")
fixed=$(realpath "$2")
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

bash -n "$original"
bash -n "$fixed"
bash -n "${BASH_SOURCE[0]}"
printf 'PASS: bash -n (original, fixed, regression harness)\n'

run_case() {
  local name=$1 script=$2 tool=$3 repo=$4 rebuild=$5 expected=$6
  local build_status=${7:-0} dev_status=${8:-0}
  local case_dir="$root/$name" status=0
  local bootstrap="$root/$name/$tool" checkout="$root/$name/$repo"
  mkdir -p "$(dirname "$bootstrap")" "$checkout/bazel-bin/src"
  cat > "$bootstrap" <<'BOOTSTRAP'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$CASE_DIR/build.args"
exit "$BUILD_STATUS"
BOOTSTRAP
  cat > "$checkout/bazel-bin/src/bazel-dev" <<'DEVELOPMENT'
#!/usr/bin/env bash
printf '%s\0' "$@" > "$CASE_DIR/dev.args"
exit "$DEV_STATUS"
DEVELOPMENT
  chmod +x "$bootstrap" "$checkout/bazel-bin/src/bazel-dev"
  (
    cd "$checkout"
    if [[ "$rebuild" == yes ]]; then
      cd "$case_dir"
    fi
    CASE_DIR="$case_dir" BUILD_STATUS="$build_status" DEV_STATUS="$dev_status" \
      BAZEL_BINARY="$bootstrap" BAZEL_DIR="$checkout" \
      bash "$script" version 'argument with spaces' '' '*.literal' \
      > "$case_dir/stdout" 2> "$case_dir/stderr"
  ) || status=$?
  if [[ "$status" != "$expected" ]]; then
    cat "$case_dir/stdout" "$case_dir/stderr" >&2
    printf 'FAIL: %s expected status %s, got %s\n' "$name" "$expected" "$status" >&2
    exit 1
  fi
  if [[ "$expected" == 127 ]]; then
    [[ ! -e "$case_dir/dev.args" ]]
  else
    if [[ "$rebuild" == yes ]]; then
      printf '%s\0' build //src:bazel-dev > "$case_dir/expected.build"
      cmp "$case_dir/expected.build" "$case_dir/build.args"
    else
      [[ ! -e "$case_dir/build.args" ]]
    fi
    if [[ "$build_status" == 0 ]]; then
      printf '%s\0' version 'argument with spaces' '' '*.literal' > "$case_dir/expected.dev"
      cmp "$case_dir/expected.dev" "$case_dir/dev.args"
    else
      [[ ! -e "$case_dir/dev.args" ]]
    fi
  fi
  printf 'PASS: %s (exit %s)\n' "$name" "$status"
}

run_case original_bootstrap_spaces "$original" 'tool dir/fake bazel' repo yes 127
run_case original_checkout_spaces "$original" bootstrap 'repo with spaces' no 127
run_case original_plain_paths "$original" bootstrap repo yes 0
run_case fixed_bootstrap_spaces "$fixed" 'tool dir/fake bazel' repo yes 0
run_case fixed_checkout_spaces "$fixed" bootstrap 'repo with spaces' no 0
run_case fixed_both_paths_spaces "$fixed" 'tool dir/fake bazel' 'repo with spaces' yes 0
run_case fixed_plain_paths "$fixed" bootstrap repo yes 0
run_case fixed_no_rebuild "$fixed" 'tool dir/fake bazel' repo no 0
run_case fixed_build_failure "$fixed" 'tool dir/fake bazel' 'repo with spaces' yes 42 42
run_case fixed_dev_failure "$fixed" bootstrap 'repo with spaces' no 23 0 23
printf 'All 10 regression cases passed.\n'
