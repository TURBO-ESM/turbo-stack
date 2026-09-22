#!/bin/bash
# test_turbo_stack_with_container.sh
#
# End-to-end test driver (container).  Thin wrapper: it parses the common driver
# args, then hands off to turbo_run_test_driver (scripts/lib/common.sh), which builds
# + ctests each selected backend (FMS2, TIM) by running the real single-backend
# builder scripts/build_with_container.sh in its own process, and prints a
# per-backend matrix/verdict.  Its siblings -- test_turbo_stack_locally.sh (a Spack
# env), test_turbo_stack_on_derecho.sh (Lmod modules) and
# test_turbo_stack_with_system_toolchain.sh (bring-your-own on PATH) -- are identical
# except for their toolchain and builder.  Here a container image supplies it, so
# nothing but a container engine is needed on the host.  It is the image CI uses, so
# this will often reproduce a CI failure without pushing a branch.  See
# docker/README.md, docs/build_test_orchestration_prompt.md and
# docs/dependency_tiers_prompt.md.
#
# Tests the MOM6 / TIM / FMS sources turbo-stack pins as submodules -- the container
# fetches nothing, so initialize them first (the wrapper guards them).  Export
# MOM6_ROOT / FMS_ROOT / TIM_ROOT to build your own trees instead: each is mounted and
# forwarded to both per-backend runs, and the matrix reports the component as
# (override).  Nothing is written into $TURBO_STACK_ROOT -- each backend builds under
# $TURBO_BUILD_SYSTEM_TEST_DIR, as you rather than as root, and those artifacts
# outlive the container.  To re-enter one, name it:
#
#     scripts/build_with_container.sh --shell \
#         --build_dir $TURBO_BUILD_SYSTEM_TEST_DIR/turbo-stack-with-TIM
#
# A bare --shell takes that script's own default instead, which is not where this
# driver built.
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
#   TURBO_CONTAINER_ENGINE       Container CLI (default: docker)
#   TURBO_STACK_ROOT             turbo-stack clone (optional; self-located)
#   TURBO_BUILD_SYSTEM_TEST_DIR  Artifact root (default:
#                                $TMPDIR/turbo_ci_container_test/<checkout>-<hash>,
#                                keyed on the checkout's full path, so no two
#                                checkouts ever share a build dir)
#   MOM6_ROOT / FMS_ROOT /       Build these trees instead of the submodules; each
#   TIM_ROOT                     is mounted into every container.
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

_runner="$TURBO_STACK_ROOT/scripts/build_with_container.sh"

# Container builds get their own artifact root, separate from the host-toolchain
# drivers' $TMPDIR/turbo_build_system_test: the container's toolchain lives at a
# different prefix (/opt/spack), and cmake aborts when a cached compiler path changes.
#
# Keyed per checkout, too, since cmake also caches the source dir it configured and
# turbo-stack is developed across worktrees.  On the FULL path, not the basename:
# ~/work/turbo-stack and ~/review/turbo-stack would otherwise collide into exactly
# that error.  Named for the basename (readable), disambiguated by a short hash.
_ckt=$(printf '%s' "$TURBO_STACK_ROOT" | (sha256sum 2>/dev/null || shasum -a 256) | cut -c1-8)
: "${TURBO_BUILD_SYSTEM_TEST_DIR:=${TMPDIR:-/tmp}/turbo_ci_container_test/$(basename -- "$TURBO_STACK_ROOT")-$_ckt}"
export TURBO_BUILD_SYSTEM_TEST_DIR
echo "[ci-container] artifacts under $TURBO_BUILD_SYSTEM_TEST_DIR"

turbo_run_test_driver "$_runner"
