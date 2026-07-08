#!/bin/bash
# test_turbo_stack_locally.sh
#
# End-to-end test driver (local / spack).  Thin wrapper: it parses the common
# driver args, then hands off to turbo_run_test_driver (scripts/lib/common.sh),
# which builds + ctests each selected backend (FMS2, TIM) by running the real
# single-backend builder scripts/build_local_with_spack_env.sh in its own process
# -- a full, independent Stage-1 (env setup) -> Stage-2 (build turbo-stack) run
# per backend -- and prints a per-backend matrix/verdict.  The Derecho analogue, test_turbo_stack_on_derecho.sh,
# is identical except for its toolchain (Lmod modules) and builder.  See
# docs/build_test_orchestration_prompt.md and docs/dependency_tiers_prompt.md.
#
# Tests the MOM6 / TIM / FMS sources turbo-stack pins as submodules; the builder
# guards them.  Nothing is written into $TURBO_STACK_ROOT.
#
# Options:
#   --only FMS2|TIM     Run only the named flavor (default: both)
#   --parallel N, -j N  Parallel build jobs (default: nproc)
#   --clean             rm -rf $TURBO_BUILD_SYSTEM_TEST_DIR first (from scratch;
#                       clears deps + turbo-stack build, same as the orchestrators)
#   -h, --help          Print this usage text and exit.
#
# Configuration (env vars):
#   SPACK_ROOT                   Spack installation (required)
#   TURBO_STACK_ROOT             turbo-stack clone (optional; self-located)
#   TURBO_BUILD_SYSTEM_TEST_DIR  Artifact root (default: $TMPDIR/turbo_build_system_test)
#   MOM6_ROOT / FMS_ROOT / TIM_ROOT      Out-of-tree source overrides (dev trees)

set -euo pipefail

# --- bootstrap: locate + source the shared library ----------------------------
# Search a few candidates for the in-repo library; common.sh then self-locates
# and exports TURBO_STACK_ROOT.  (Same bootstrap as test_turbo_stack_on_derecho.sh.)
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

turbo_run_test_driver "$TURBO_STACK_ROOT/scripts/build_local_with_spack_env.sh"
