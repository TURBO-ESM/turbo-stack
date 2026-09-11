#!/bin/bash
# test_turbo_stack_in_ci_container.sh
#
# End-to-end test driver (CI container).  Runs what
# .github/workflows/turbo-cmake-container-tests.yaml runs -- the CMake build plus
# the pFUnit unit tests, for BOTH infra backends (TIM, FMS2) -- inside the same
# image CI uses, so a CI failure can be reproduced locally without pushing a
# branch.  Thin wrapper: it parses the common driver args, then hands off to
# turbo_run_test_driver (scripts/lib/common.sh), which runs the real container
# wrapper scripts/run_ci_container.sh once per backend in its own process and
# prints a per-backend matrix/verdict.
#
# Its siblings run the same two stages on a host toolchain instead of in a
# container: test_turbo_stack_locally.sh (spack), test_turbo_stack_on_derecho.sh
# (Lmod modules), test_turbo_stack_with_system_toolchain.sh (bring-your-own on
# PATH).  See docs/build_test_orchestration_prompt.md, docs/dependency_tiers_prompt.md
# and docker/README.md.
#
# Tests the MOM6 / TIM / FMS sources turbo-stack pins as submodules -- the container
# fetches nothing, so initialize them first (the wrapper guards them).  To build a
# MOM6 tree of your own instead, export MOM6_ROOT before running: it is inherited by
# both per-backend runs, which mount that tree and forward it (run_ci_container.sh's
# --mom6-root is the same thing, per invocation), and the matrix below then reports
# MOM6 as (override).  Whatever branch that tree is on is what gets built.  Nothing is
# written into $TURBO_STACK_ROOT: each backend builds under
# $TURBO_BUILD_SYSTEM_TEST_DIR, which is mounted into the container, and the
# artifacts are handed back to your uid before each container exits.  They outlive
# the container, so `scripts/run_ci_container.sh --shell` re-enters the same build
# tree and can re-run ctest with no rebuild.
#
# Options:
#   --only FMS2|TIM     Run only the named backend (default: both, as CI's matrix)
#   --parallel N, -j N  Parallel build jobs (default: nproc; CI uses 4)
#   --clean             rm -rf $TURBO_BUILD_SYSTEM_TEST_DIR first (from scratch;
#                       clears deps + turbo-stack build, same as the orchestrators)
#   -h, --help          Print this usage text and exit.
#
# Configuration (env vars):
#   TURBO_CI_IMAGE               Image to run (default: the tag CI consumes --
#                                ghcr.io/turbo-esm/turbo-stack/turbo-ci:gcc-openmpi)
#   TURBO_CONTAINER_ENGINE       Container CLI (default: docker, else podman)
#   TURBO_STACK_ROOT             turbo-stack clone (optional; self-located)
#   TURBO_BUILD_SYSTEM_TEST_DIR  Artifact root (default:
#                                $TMPDIR/turbo_ci_container_test/<checkout dir name>,
#                                so sibling worktrees never share a build dir)
#   MOM6_ROOT                    Build this MOM6 tree instead of the submodule; it
#                                is mounted into each container.  FMS_ROOT /
#                                TIM_ROOT are NOT forwarded (reported, not silent).
#
# SPACK_ROOT is NOT required: the image brings its own spack (/opt/spack) with the
# repo's env baked in.  A host SPACK_ROOT / TURBO_STACK_ROOT is never passed in.

set -euo pipefail

# --- bootstrap: locate + source the shared library ----------------------------
# Search a few candidates for the in-repo library; common.sh then self-locates
# and exports TURBO_STACK_ROOT.  (Same bootstrap as test_turbo_stack_locally.sh.)
_self="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
_common=""
for _cand in "$_self" "${PBS_O_WORKDIR:-}"; do
    [[ -n "$_cand" && -f "$_cand/scripts/lib/common.sh" ]] && { _common="$_cand/scripts/lib/common.sh"; break; }
done
[[ -n "$_common" ]] || { echo "Error: cannot locate scripts/lib/common.sh; run this driver from inside a turbo-stack checkout." >&2; exit 1; }
# shellcheck source=/dev/null
source "$_common"

TURBO_JOBS="$(command -v nproc >/dev/null 2>&1 && nproc || echo 4)"
turbo_parse_driver_args "$@"
turbo_resolve_stack_root

_runner="$TURBO_STACK_ROOT/scripts/run_ci_container.sh"

# Container builds get their own artifact root, separate from the host-toolchain
# drivers' $TMPDIR/turbo_build_system_test: the same build dir cannot be shared,
# because the container's toolchain lives at a different prefix (/opt/spack) and
# cmake aborts when a cached compiler path changes.
#
# Per checkout, too -- unlike the host-toolchain drivers, which use one fixed path.
# turbo-stack is developed across several git worktrees, and cmake caches the source
# dir it configured: two checkouts sharing one build dir is a hard error ("does not
# match the source ... used to generate cache"), so key the default on the checkout.
: "${TURBO_BUILD_SYSTEM_TEST_DIR:=${TMPDIR:-/tmp}/turbo_ci_container_test/$(basename -- "$TURBO_STACK_ROOT")}"
export TURBO_BUILD_SYSTEM_TEST_DIR
echo "[ci-container] artifacts under $TURBO_BUILD_SYSTEM_TEST_DIR"

# --clean's rm -rf runs here on the host, but the container writes as root.  A run
# killed before its chown-back could fire leaves root-owned dirs that we cannot
# unlink; repair them in a throwaway container first so --clean can't die on EPERM.
if [[ "${TURBO_CLEAN:-false}" == true && -d "$TURBO_BUILD_SYSTEM_TEST_DIR" ]] \
   && [[ -n "$(find "$TURBO_BUILD_SYSTEM_TEST_DIR" ! -user "$(id -u)" -print -quit 2>/dev/null)" ]]; then
    echo "[ci-container] artifacts contain files not owned by you (an interrupted run?);"
    echo "[ci-container] restoring ownership so --clean can remove them"
    bash "$_runner" --fix-ownership --build_dir "$TURBO_BUILD_SYSTEM_TEST_DIR"
fi

turbo_run_test_driver "$_runner"
