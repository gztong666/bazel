"""Exercise the complete collector using real Clang coverage artifacts."""
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path.cwd()
original, fixed = map(lambda p: Path(p).resolve(), sys.argv[1:3])
clang = os.environ["VALIDATE_CLANG"]
profdata = os.environ["VALIDATE_PROFDATA"]
cov = os.environ["VALIDATE_COV"]
results = {}
for case, name in [("plain", "binary"), ("spaces", "test binary"), ("glob", "binary[ab]")]:
    folder = root / "validation-fixtures" / case
    folder.mkdir(parents=True)
    source = folder / "source.cc"
    source.write_text("int main() { return 0; }\n")
    binary = folder / name
    subprocess.run([clang, "-fprofile-instr-generate", "-fcoverage-mapping", str(source), "-o", str(binary)], check=True)
    coverage = folder / "coverage"
    coverage.mkdir()
    env = dict(os.environ, LLVM_PROFILE_FILE=str(coverage / "test.profraw"))
    subprocess.run([str(binary)], env=env, check=True)
    if case == "glob":
        (folder / "binarya").write_text("not an instrumented object\n")
        (folder / "binaryb").write_text("not an instrumented object\n")
    objects = folder / "runtime_objects_list.txt"
    objects.write_text(str(binary) + "\n")
    manifest = folder / "manifest.txt"
    manifest.write_text(str(objects) + "\n")
    env.update(COVERAGE_DIR=str(coverage), COVERAGE_MANIFEST=str(manifest), GENERATE_LLVM_LCOV="1", LLVM_PROFDATA=profdata, LLVM_COV=cov)
    for version, script in [("original", original), ("fixed", fixed)]:
        proc = subprocess.run(["bash", str(script)], cwd=folder, env=env, text=True, capture_output=True)
        output = coverage / "_cc_coverage.dat"
        report = output.read_text() if output.exists() else ""
        ok = proc.returncode == 0 and "SF:" in report and "DA:1,1" in report and "end_of_record" in report
        expected = version == "fixed" or case == "plain"
        print(f"{version}/{case}: status={proc.returncode}, valid_lcov={ok}, expected={expected}", flush=True)
        if proc.stderr:
            print(proc.stderr, flush=True)
        assert ok == expected, (version, case, proc.stdout, proc.stderr, report)
        results[f"{version}/{case}"] = ok
print("Real LLVM before/after results:", results)
