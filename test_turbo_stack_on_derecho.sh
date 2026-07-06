#!/bin/bash
#PBS -N turbo-stack-on-derecho-test
#PBS -A NCGD0067
#PBS -q main
#PBS -l select=1:ncpus=128:mpiprocs=128:mem=100GB
#PBS -l walltime=01:00:00
#PBS -j oe
#PBS -V

# Usage: ./test_turbo_stack_on_derecho.sh [options]
#
# End-to-end test driver (Derecho / Lmod modules).  Thin wrapper: it parses the
# common driver args, then hands off to turbo_run_test_driver (scripts/lib/common.sh),
# which builds + ctests each selected backend (FMS2, TIM) by running the real
# single-backend builder scripts/build_on_derecho.sh in its own process -- a full,
# independent Tier-1 -> Tier-2 -> Tier-3 run per backend -- and prints a per-backend
# matrix/verdict.  The local analogue, test_turbo_stack_locally.sh, is identical
# except for its toolchain (spack) and builder.  See docs/turbo_stack_pipeline_prompt.md
# and docs/dependency_tiers_prompt.md.
#
# Tests the MOM6 / TIM / FMS sources turbo-stack pins as submodules; the builder
# guards them.  Nothing is written into $TURBO_STACK_ROOT.
#
# Options:
#   --only FMS2|TIM     Run only the named flavor (default: both)
#   --parallel N, -j N  Parallel build jobs (default: 128 = one Derecho node)
#   --clean             rm -rf $TURBO_BUILD_SYSTEM_TEST_DIR first (from scratch;
#                       clears Tier-2 deps + Tier-3, same as the orchestrators)
#   -h, --help          Print this usage text and exit.
#
# Configuration (env vars):
#   TURBO_STACK_ROOT             turbo-stack clone (optional; self-located)
#   TURBO_BUILD_SYSTEM_TEST_DIR  Artifact root (default: $TMPDIR/turbo_build_system_test)
#   MOM6_ROOT / TIM_ROOT / FMS_ROOT      Out-of-tree source overrides

set -euo pipefail

# --- bootstrap: locate + source the shared library ----------------------------
# This driver can run from a PBS spool copy, so search a few candidates for the
# in-repo library; common.sh then self-locates and exports TURBO_STACK_ROOT.
_self="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
_common=""
for _cand in "${TURBO_STACK_ROOT:-}" "$_self" "${PBS_O_WORKDIR:-}"; do
    [[ -n "$_cand" && -f "$_cand/scripts/lib/common.sh" ]] && { _common="$_cand/scripts/lib/common.sh"; break; }
done
[[ -n "$_common" ]] || { echo "Error: cannot locate scripts/lib/common.sh; set TURBO_STACK_ROOT=/path/to/turbo-stack." >&2; exit 1; }
# shellcheck source=/dev/null
source "$_common"
turbo_resolve_stack_root

TURBO_JOBS=128                 # default: one full Derecho compute node
turbo_parse_driver_args "$@"

turbo_run_test_driver "$TURBO_STACK_ROOT/scripts/build_on_derecho.sh"
