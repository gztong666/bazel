#!/usr/bin/env bash
#
# Copyright 2026 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---

source "$(rlocation io_bazel/src/test/shell/unittest.bash)" || exit 1
collect_cc_coverage="$(rlocation io_bazel/tools/test/collect_cc_coverage.sh)"

function set_up() {
  test_dir="$(mktemp -d "${TEST_TMPDIR}/collect-cc.XXXXXXXX")"
  cd "${test_dir}"
  export COVERAGE_DIR="${test_dir}/coverage"
  export COVERAGE_MANIFEST="${test_dir}/coverage_manifest.txt"
  export GENERATE_LLVM_LCOV=1
  export LLVM_PROFDATA="${test_dir}/llvm-profdata"
  export LLVM_COV="${test_dir}/llvm-cov"
  export LLVM_COV_ARGS="${test_dir}/llvm-cov.args"
  mkdir -p "${COVERAGE_DIR}"
  touch "${COVERAGE_DIR}/test.profraw"
  : > "${COVERAGE_MANIFEST}"
  # Only the LLVM tools are replaced: execute the complete collector and check
  # its argument protocol without requiring a compiler or valid profile data.
  printf '#!/usr/bin/env bash\nexit 0\n' > "${LLVM_PROFDATA}"
  cat > "${LLVM_COV}" <<'EOF'
#!/usr/bin/env bash
printf '%s\0' "$@" > "${LLVM_COV_ARGS}"
printf 'SF:/proc/self/cwd/source.cc\nDA:1,1\nend_of_record\n'
EOF
  chmod +x "${LLVM_PROFDATA}" "${LLVM_COV}"
}

function write_objects() {
  printf '%s\n' "$@" > runtime_objects_list.txt
  printf '%s\n' "${test_dir}/runtime_objects_list.txt" > "${COVERAGE_MANIFEST}"
}

function check_export() {
  bash "${collect_cc_coverage}" > "$TEST_log" 2>&1 \
      || fail "Coverage collection failed"
  local output="${COVERAGE_DIR}/_cc_coverage.dat"
  printf '%s\0' export -instr-profile "${output}.data" -format=lcov \
      '-ignore-filename-regex=^/tmp/.+' "$@" > expected.args
  cmp expected.args "${LLVM_COV_ARGS}" \
      || fail "llvm-cov arguments were split, expanded, or lost"
  printf 'SF:source.cc\nDA:1,1\nend_of_record\n' > expected.dat
  cmp expected.dat "${output}" || fail "Incorrect coverage output"
}

function test_plain_object() {
  write_objects bin/test
  check_export -object bin/test
}

function test_multiple_object_lists() {
  write_objects bin/test lib/first.so
  mkdir other
  printf '%s\n' lib/second.so > other/runtime_objects_list.txt
  printf '%s\n' other/runtime_objects_list.txt unrelated.gcno >> "${COVERAGE_MANIFEST}"
  check_export -object bin/test -object lib/first.so -object lib/second.so
}

function test_object_paths_with_spaces() {
  write_objects 'bin/test binary' 'lib/shared library.so'
  check_export -object 'bin/test binary' -object 'lib/shared library.so'
}

function test_object_paths_with_glob_characters() {
  touch 'binary[ab]' binarya binaryb
  write_objects 'binary[ab]'
  check_export -object 'binary[ab]'
}

function test_object_paths_with_surrounding_whitespace() {
  write_objects ' binary '
  check_export -object ' binary '
}

function test_object_list_path_with_leading_whitespace() {
  write_objects bin/test
  mv runtime_objects_list.txt ' runtime_objects_list.txt'
  printf '%s\n' ' runtime_objects_list.txt' > "${COVERAGE_MANIFEST}"
  check_export -object bin/test
}

function test_no_runtime_objects() {
  check_export
}

run_suite "LLVM coverage collector arguments"
