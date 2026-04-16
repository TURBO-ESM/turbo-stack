#!/usr/bin/env python3
"""
Configure, build, and test turbo-stack.

Assumes the environment (CMAKE_PREFIX_PATH etc.) is already active.
Call via scripts/build_and_test.sh to have Spack set up the environment first.
"""

import os
import sys
import subprocess
import argparse
from pathlib import Path


def run(cmd, label):
    print(f"\n==> {label}")
    print("    " + " ".join(str(c) for c in cmd))
    result = subprocess.run(cmd)
    if result.returncode != 0:
        print(f"Error: {label} failed (exit code {result.returncode})", file=sys.stderr)
        sys.exit(result.returncode)


def main():
    turbo_stack_root = os.environ.get("TURBO_STACK_ROOT", "")
    if not turbo_stack_root:
        sys.exit("Error: TURBO_STACK_ROOT is not set.")
    repo_root = Path(turbo_stack_root)
    if not repo_root.is_dir():
        sys.exit(f"Error: TURBO_STACK_ROOT ({turbo_stack_root}) is not a valid directory.")

    parser = argparse.ArgumentParser(
        description="Configure, build, and test turbo-stack."
    )
    parser.add_argument(
        "--build-dir", "-B", default=str(repo_root / "build" / "default"),
        help="Build directory"
    )
    parser.add_argument(
        "--no-configure", action="store_true",
        help="Skip cmake configure step (build dir must already exist)"
    )
    parser.add_argument(
        "--no-build", action="store_true",
        help="Skip cmake build step"
    )
    parser.add_argument(
        "--no-test", action="store_true",
        help="Skip ctest step"
    )
    parser.add_argument(
        "--jobs", "-j", type=int,
        help="Parallel build jobs"
    )
    args = parser.parse_args()

    build_dir = Path(args.build_dir)

    if not args.no_configure:
        run(["cmake", "-S", str(repo_root), "-B", str(build_dir)], "CMake configure")
    elif not build_dir.exists():
        sys.exit(f"Error: --no-configure was given but build dir does not exist: {build_dir}")

    if not args.no_build:
        build_cmd = ["cmake", "--build", str(build_dir)]
        if args.jobs:
            build_cmd += ["--parallel", str(args.jobs)]
        run(build_cmd, "CMake build")

    if not args.no_test:
        run(
            ["ctest", "--test-dir", str(build_dir), "--output-on-failure"],
            "CTest"
        )


if __name__ == "__main__":
    main()
