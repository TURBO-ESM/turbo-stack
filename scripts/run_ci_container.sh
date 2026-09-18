#!/bin/bash
# Usage: ./scripts/run_ci_container.sh [options]
#
# Build turbo-stack (+ the pFUnit unit tests, with --tests) for ONE infra backend
# inside the image CI uses: ghcr.io/turbo-esm/turbo-stack/turbo-ci, which ships the
# compiler and the Tier 1 + Tier 1.5 dependencies (MPI, NetCDF, CMake, pFUnit,
# AMReX) prebuilt in a Spack env.  Nothing but a container engine is needed on the
# host.
#
# It does three things: mount your checkout (plus any MOM6 / FMS / TIM tree you
# want built instead of the pinned submodule), then run the command CI runs --
# scripts/build_local_with_spack_env.sh --infra <backend> [--tests] -- which
# activates the prebaked Spack env, builds the Tier-2 backend, then configures,
# builds and tests turbo-stack.  So a red box in .github/workflows/cmake-build.yaml
# usually reproduces here, without pushing a branch and waiting on Actions.
#
#     scripts/run_ci_container.sh --infra TIM --tests
#     MOM6_ROOT=~/projects/MOM6 scripts/run_ci_container.sh --infra TIM --tests
#
# Swap a source the repo-wide way: export MOM6_ROOT, FMS_ROOT or TIM_ROOT (see
# scripts/lib/build_dep.sh) and that tree is mounted at its own path and built, on
# whatever branch it happens to be checked out on.  Everything else comes from the
# submodules, which the container does NOT fetch -- initialize them first, as CI's
# checkout does.  For both backends in one go plus a matrix/verdict, use
# ./test_turbo_stack_in_ci_container.sh, which calls this once per backend.
#
# The container runs as root, like CI's job container, so what it writes to the
# bind mounts lands root-owned; ownership is handed back to you when the run ends,
# a failed build included.  A run that is killed outright, or interrupted in a way
# that leaves the container going, is repaired by the next run or --fix-ownership.
# Artifacts live on the bind mount and outlive the container: a later --shell (or
# another run) re-enters the same build tree, where `ctest --test-dir <dir>` re-runs
# the suite with no rebuild.
#
# Options:
#   --infra FMS2|TIM    Infrastructure backend (default: TIM).  One per run.
#   --tests             Also build + run the pFUnit unit tests (default: off, as in
#                       every other builder).  CI always passes this.
#   --build_dir DIR     Build directory (default: $TURBO_STACK_ROOT/build/default,
#                       i.e. what CI uses).  Deps land in $DIR/deps/.  A path
#                       outside the checkout is mounted in as well -- prefer one,
#                       so the container never writes into your clone.
#   --debug             Build with CMAKE_BUILD_TYPE=Debug (passed through)
#   --clean             Clean rebuild from scratch (passed through: wipes the
#                       Stage-1 dep builds/installs, plus cmake --fresh)
#   --ninja             Use the Ninja generator (passed through)
#   --parallel N, -j N  Parallel build jobs.  Exported into the container as
#                       CMAKE_BUILD_PARALLEL_LEVEL (CI sets 4).  Default: nproc.
#   --image REF         Container image (default: the tag CI consumes, below).
#                       `gcc-openmpi` is MUTABLE -- pin gcc-openmpi-<sha> to
#                       reproduce a specific CI run.
#   --pull              Refresh the image before running (it is pulled
#                       automatically when absent).
#   --shell             Start an interactive shell in the container, Spack env
#                       activated, instead of building.  Same mounts and
#                       environment; for iterating on a failure.
#   --fix-ownership     Hand the build artifacts back to you and exit.  Only needed
#                       after a run that was killed, or interrupted with the
#                       container left running; a run that ends does this itself.
#   -h, --help          Print this usage text and exit.
#
# Configuration (env vars):
#   MOM6_ROOT / FMS_ROOT / TIM_ROOT   Build these trees instead of the submodules
#   TURBO_CI_IMAGE                    Default image (overrides the built-in default)
#   TURBO_CONTAINER_ENGINE            Container CLI (default: docker)
#   CMAKE_BUILD_PARALLEL_LEVEL        Parallel jobs, when --parallel is not given
#
# Examples:
#   scripts/run_ci_container.sh --infra TIM --tests             # pinned sources, TIM
#   MOM6_ROOT=~/projects/MOM6 \
#     scripts/run_ci_container.sh --infra TIM --tests           # your MOM6, as checked out
#   scripts/run_ci_container.sh --infra FMS2 --tests \
#       --build_dir /tmp/turbo-ci/fms2                          # keep the clone clean
#   scripts/run_ci_container.sh --shell                         # poke around inside

set -eo pipefail

# Source the shared library (defines the builder arg parser + helpers; no side
# effects).  This script lives in scripts/, so the library is the sibling lib/.
# shellcheck source=/dev/null
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# Must match `container.image` in .github/workflows/cmake-build.yaml.
_default_image="ghcr.io/turbo-esm/turbo-stack/turbo-ci:gcc-openmpi"

# --- container-only options ----------------------------------------------------
# Pre-strip them before the common parser sees them (the shared
# turbo_parse_builder_args rejects unknown flags, by design -- same idiom as
# --recreate-spack-env in build_local_with_spack_env.sh).
_image="${TURBO_CI_IMAGE:-$_default_image}"
_engine="${TURBO_CONTAINER_ENGINE:-docker}"
_pull=false
_shell=false
_fix_ownership=false
_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --image)         _turbo_opt_needs_value "$1" "$#" || exit 1; _image="$2"; shift 2 ;;
        --pull)          _pull=true; shift ;;
        --shell)         _shell=true; shift ;;
        --fix-ownership) _fix_ownership=true; shift ;;
        *)               _args+=("$1"); shift ;;
    esac
done

# Everything else is the standard builder vocabulary (--infra/--tests/--build_dir/
# --debug/--clean/--ninja/--parallel/--help), validated once, in one place, and
# forwarded verbatim to the builder inside the container.
turbo_parse_builder_args "${_args[@]}"
turbo_resolve_stack_root

command -v "$_engine" >/dev/null 2>&1 || {
    echo "Error: container engine '$_engine' is not on PATH." >&2
    echo "       Install docker, or point \$TURBO_CONTAINER_ENGINE at another CLI." >&2
    exit 1
}

# --- image ---------------------------------------------------------------------
# The image is private (TURBO-ESM policy), so a pull needs a one-time login; see
# docker/README.md.  A locally built tag works too, via --image.  Called late, so a
# missing submodule fails before a multi-GB pull rather than after it.
_ensure_image() {
    local have=false
    "$_engine" image inspect "$_image" >/dev/null 2>&1 && have=true
    [[ "$_pull" == true || "$have" == false ]] || return 0
    echo "[ci-container] pulling $_image"
    "$_engine" pull "$_image" && return 0
    if [[ "$have" == true ]]; then
        echo "[ci-container] pull failed; continuing with the local copy of $_image" >&2
        return 0
    fi
    echo "Error: could not pull '$_image' and it is not present locally." >&2
    echo "       The package is private -- log in once with a token carrying" >&2
    echo "       read:packages, or build the image yourself (docker/README.md):" >&2
    echo "         echo \"\$GHCR_TOKEN\" | $_engine login ghcr.io -u <github-user> --password-stdin" >&2
    return 1
}

# --- mounts --------------------------------------------------------------------
# Mount the checkout at its OWN path: TURBO_STACK_ROOT then self-locates to the
# same value inside the container as out, so log lines, CMakeCache.txt entries and
# ctest paths are valid on both sides.
_mounts=(-v "$TURBO_STACK_ROOT:$TURBO_STACK_ROOT")
_notes=()

# In a git WORKTREE, .git is a file pointing at <main repo>/.git/worktrees/<name> --
# an absolute path outside the checkout -- and the submodule gitdirs live under it
# too.  Without that directory every `git` call inside the container dies with
# "fatal: not a git repository", and build_dep cannot read the source SHA for its
# rebuild sentinel.  Mount it read-only: the build only reads SHAs, and a root
# container has no business writing to the main repo's .git.  A normal clone keeps
# .git inside the checkout, so this adds no mount at all.
_mount_git_dir() {   # <checkout>
    local git_dir
    git_dir=$(git -C "$1" rev-parse --git-common-dir 2>/dev/null) || return 0
    [[ "$git_dir" == /* && "$git_dir" != "$1"/* ]] || return 0
    git_dir=$(cd -P -- "$git_dir" && pwd)
    _mounts+=(-v "$git_dir:$git_dir:ro")
    _notes+=("$(printf '%-9s = %s' "git dir" "$git_dir") (read-only; $1 is a worktree)")
}
_mount_git_dir "$TURBO_STACK_ROOT"

# --- source overrides: build YOUR MOM6 / FMS / TIM, not the pinned submodule ----
# <NAME>_ROOT is the repo-wide way to swap a component's source: build_dep resolves
# it, and the submodule guards stand down for it.  The only extra thing needed here
# is visibility -- mount the tree at its own path and forward the variable, so the
# value means the same inside the container as out.  Whatever branch the tree is on
# is what gets built; switch branches on the host and run again.
#
# Mounted read-write, not :ro: the build writes nothing into a source tree, but git
# may refresh its index there.  The build dir is elsewhere either way.
#
# PFUNIT_ROOT / AMREX_ROOT are deliberately NOT forwarded: this image supplies
# pFUnit and AMReX from its Spack env, so the builder never calls build_dep for them
# and an override would silently have no effect.
_env=()
for _var in MOM6_ROOT FMS_ROOT TIM_ROOT; do
    _dir="${!_var}"
    [[ -n "$_dir" ]] || continue
    [[ -d "$_dir" ]] || {
        echo "Error: \$$_var is set to '$_dir', which is not a directory." >&2
        exit 1
    }
    _dir=$(cd -P -- "$_dir" && pwd)
    export "$_var=$_dir"
    _env+=(-e "$_var=$_dir")
    if [[ "$_dir" != "$TURBO_STACK_ROOT" && "$_dir" != "$TURBO_STACK_ROOT"/* ]]; then
        _mounts+=(-v "$_dir:$_dir")
        _mount_git_dir "$_dir"
    fi
    _notes+=("$(printf '%-9s = %s (%s)' "${_var%_ROOT}" "$_dir" \
        "$(git -C "$_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'not a git tree')")")
done

# MOM6 is the one source consumed as source rather than built as a dep, and its
# top-level CMakeLists hard-fails without these; catch it here rather than 20
# minutes into a container build.  CI gets them via submodules:recursive.
if [[ -n "$MOM6_ROOT" ]]; then
    [[ -f "$MOM6_ROOT/CMakeLists.txt" ]] || {
        echo "Error: '$MOM6_ROOT' has no CMakeLists.txt -- that is not a MOM6 checkout" >&2
        echo "       with the CMake build system (not every MOM6 branch has it)." >&2
        exit 1
    }
    for _p in pkg/CVMix-src pkg/GSW-Fortran; do
        [[ -e "$MOM6_ROOT/$_p/.git" ]] || {
            echo "Error: MOM6 submodule '$_p' is not initialized in $MOM6_ROOT." >&2
            echo "       git -C \"$MOM6_ROOT\" submodule update --init --recursive" >&2
            exit 1
        }
    done
fi

# --- build dir, and the artifacts handed back afterwards -----------------------
_build_dir=""
if [[ -n "$TURBO_B_BUILD_DIR" ]]; then
    mkdir -p "$TURBO_B_BUILD_DIR"
    # Normalize: the mount needs an absolute path, and forwarding the same absolute
    # path keeps host and container in agreement.
    _build_dir=$(cd -P -- "$TURBO_B_BUILD_DIR" && pwd)
    if [[ "$_build_dir" != "$TURBO_STACK_ROOT" && "$_build_dir" != "$TURBO_STACK_ROOT"/* ]]; then
        _mounts+=(-v "$_build_dir:$_build_dir")
    fi
    _chown_targets=("$_build_dir")
else
    # CI's layout: both land inside the checkout (see build_turbo_stack.sh and
    # turbo_run_backend_builder for the defaults).
    _chown_targets=("$TURBO_STACK_ROOT/build" "$TURBO_STACK_ROOT/deps")
fi

# --- ownership -----------------------------------------------------------------
# The container writes as root, so bind-mounted artifacts come back root-owned.
# Hand them back in a throwaway container on the way out.  The test is "is anything
# here not mine?", not "did I just run?", so this also repairs a previous run that
# never got to fire -- and costs nothing (no container at all) when there is
# nothing to fix, as on a rootless engine.
#
# It runs once `docker run` has returned, which is the only moment bash can run a
# trap: a signal arriving while a foreground command is in flight is held until
# that command finishes.  Interrupting a run therefore does not reliably stop the
# build -- the container can survive the signal and keep going (`docker ps`, then
# `docker rm -f`) -- and ownership is repaired on the next run or --fix-ownership.
_uidgid="$(id -u):$(id -g)"
_chown_back() {
    local rc=$?
    [[ -n "$(find "${_chown_targets[@]}" ! -user "$(id -u)" -print -quit 2>/dev/null)" ]] || return $rc
    echo "[ci-container] restoring ownership ($_uidgid) of: ${_chown_targets[*]}"
    "$_engine" run --rm "${_mounts[@]}" "$_image" \
        chown -R "$_uidgid" -- "${_chown_targets[@]}" >/dev/null 2>&1 || true
    return $rc
}

if [[ "$_fix_ownership" == true ]]; then
    _ensure_image || exit 1
    _chown_back
    exit 0
fi

# --- preflight: the submodules the container consumes but cannot fetch ---------
# Spack supplies Tier 1 + 1.5, so this is the same guard set as
# build_local_with_spack_env.sh: MOM6 + MARBL, plus the selected backend.  Each
# guard stands down for a component whose <NAME>_ROOT is set above.
turbo_guard_builder_submodules 2
_ensure_image || exit 1
trap _chown_back EXIT INT TERM

# --- environment ---------------------------------------------------------------
# The two settings cmake-build.yaml puts on the job; everything else the build needs
# (SPACK_ROOT, OMPI_ALLOW_RUN_AS_ROOT{,_CONFIRM}) is baked into the image.
# CMAKE_BUILD_PARALLEL_LEVEL is read natively by every `cmake --build` in the
# pipeline (deps + turbo-stack), so no per-call flag plumbing is needed.
_jobs="${TURBO_B_PARALLEL:-${CMAKE_BUILD_PARALLEL_LEVEL:-}}"
[[ -n "$_jobs" ]] || _jobs="$(command -v nproc >/dev/null 2>&1 && nproc || echo 4)"
_env+=(-e "CMAKE_BUILD_PARALLEL_LEVEL=$_jobs")
# The pFUnit suites run `mpirun -np 4` (@test(npes=[1,2,4])); OpenMPI 5's PRRTE
# refuses to launch that on a host with fewer slots.  Harmless on a big machine.
_env+=(-e "PRTE_MCA_rmaps_default_mapping_policy=${PRTE_MCA_rmaps_default_mapping_policy:-:oversubscribe}")

# tty: interactive for --shell; otherwise only when stdout is a terminal, since the
# end-to-end driver pipes this script through tee (turbo_run_flavor).
_tty=()
if [[ "$_shell" == true ]]; then
    if [[ ! -t 0 || ! -t 1 ]]; then
        echo "Error: --shell needs a terminal, but stdin/stdout is not one." >&2
        echo "       Run it directly, without a pipe or redirection." >&2
        exit 1
    fi
    _tty=(-i -t)
elif [[ -t 1 ]]; then
    _tty=(-t)
fi

# --- the command CI runs, inside the container ---------------------------------
# Mirrors the `run:` steps of cmake-build.yaml, in order, then hands off to the
# builder -- which owns Spack activation, the dep build and the turbo-stack build.
_build_args=()
[[ "$TURBO_B_DEBUG" == true ]] && _build_args+=(--debug)
[[ "$TURBO_B_CLEAN" == true ]] && _build_args+=(--clean)
[[ "$TURBO_B_NINJA" == true ]] && _build_args+=(--ninja)
_build_args+=(--infra "$TURBO_B_INFRA")
[[ "$TURBO_B_TESTS" == true ]] && _build_args+=(--tests)
[[ -n "$_build_dir" ]] && _build_args+=(--build_dir "$_build_dir")

if [[ "$_shell" == true ]]; then
    # Not `bash -l`: a login shell re-reads /etc/profile and would undo the
    # activation we just did.
    _final="spack env activate turbo_stack
echo '[ci-container] Spack env turbo_stack is active.  Build with:'
echo '    scripts/build_local_with_spack_env.sh --infra $TURBO_B_INFRA --tests'
exec bash"
else
    _final=$(printf '%q ' scripts/build_local_with_spack_env.sh "${_build_args[@]}")
fi

_cmd=$(cat <<EOF
set -eo pipefail

# Assert the prebaked env, as the workflow's first step does.  Without it,
# spack_local_environment.sh's default --create-if-missing applies and a wrong or
# stale image would not error -- it would silently start a ~1 h from-source
# dependency build.  Fail in seconds instead.
. "\$SPACK_ROOT/share/spack/setup-env.sh"
spack env list | grep -qw turbo_stack || {
    echo "Error: image '$_image' has no prebaked 'turbo_stack' Spack env." >&2
    echo "       Refusing: the build would start the whole dependency stack from" >&2
    echo "       source (~1 h).  Use the CI image, or rebuild it -- docker/README.md." >&2
    exit 1
}

# Root against a checkout owned by another uid: git refuses without this (the
# workflow has the same step).
git config --global --add safe.directory '*'

# The image bakes spack.yaml at image-build time and the producer workflow is
# manual, so the env can lag this checkout's spec -- more easily here than in CI,
# since refreshing the image locally is a ~1 h build.  Warn, never fail: the
# decoupling is deliberate and the CMake lane does not need every spec present.
if ! diff -q /opt/turbo-spack/spack.yaml spack/spack.yaml >/dev/null 2>&1; then
    echo "[ci-container] warning: the image's baked spack.yaml differs from this checkout"
    echo "[ci-container]          -- it may predate a spec you added.  Refresh it with"
    echo "[ci-container]          'gh workflow run build-turbo-ci-container.yaml'."
    diff -u /opt/turbo-spack/spack.yaml spack/spack.yaml || true
fi

$_final
EOF
)

echo "[ci-container] engine    = $_engine"
echo "[ci-container] image     = $_image"
echo "[ci-container] checkout  = $TURBO_STACK_ROOT (same path inside the container)"
for _n in "${_notes[@]}"; do echo "[ci-container] $_n"; done
echo "[ci-container] jobs      = $_jobs"
echo "[ci-container] artifacts = ${_chown_targets[*]} (root-owned until the run ends)"

"$_engine" run --rm --init "${_tty[@]}" "${_mounts[@]}" "${_env[@]}" \
    -w "$TURBO_STACK_ROOT" "$_image" \
    bash -c "$_cmd"
