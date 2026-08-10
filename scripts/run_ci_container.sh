#!/bin/bash
# Usage: ./scripts/run_ci_container.sh [options]
#
# Run the CMake build (+ the pFUnit unit tests, with --tests) for ONE infra
# backend inside the SAME container CI uses -- ghcr.io/turbo-esm/turbo-stack/turbo-ci
# -- so a CI failure can be reproduced and debugged locally, without pushing a
# branch.  This is the local twin of .github/workflows/turbo-cmake-container-tests.yaml:
# it mounts your checkout into the image and runs exactly what that workflow runs:
#     assert the image's prebaked "turbo_stack" Spack env is present
#     git config --global --add safe.directory '*'
#     warn if the image's baked spack.yaml lags this checkout
#     scripts/build_local_with_spack_env.sh --infra <backend> --tests
# with the workflow's two environment settings (CMAKE_BUILD_PARALLEL_LEVEL and the
# PRRTE oversubscribe policy the MPI tests need).  For BOTH backends plus a
# matrix/verdict, use ./test_turbo_stack_in_ci_container.sh, which calls this
# script once per backend.
#
# The image bakes the repo's spack env (spack/spack.yaml, env name "turbo_stack")
# but does not activate it -- the repo scripts own activation -- so nothing here
# needs SPACK_ROOT.  Your host SPACK_ROOT / TURBO_STACK_ROOT are deliberately NOT
# passed into the container: spack lives at /opt/spack in the image, and the
# checkout is mounted at its own path so TURBO_STACK_ROOT self-locates to the same
# value inside and out.  Submodules are NOT fetched (the container clones nothing);
# initialize them first, as CI's checkout does.  When the checkout is a git worktree,
# the main repo's .git is mounted read-only as well: a worktree's .git is a file
# pointing outside the checkout (as are its submodule gitdirs), and git -- which
# build_dep uses to read source SHAs -- would otherwise fail inside the container.
#
# The container runs as root, like CI's job container, so bind-mounted writes would
# land root-owned; ownership of the build artifacts is handed back to you before the
# container exits (pass --as-me to run as your own uid instead).  Artifacts live on
# the bind mount, so they survive the container: a later --shell (or another run)
# re-enters the same build tree, and `ctest --test-dir <dir>` re-runs the suite with
# no rebuild.
#
# Options:
#   --infra FMS2|TIM      Infrastructure backend (default: TIM).  CI runs both.
#   --tests               Also build + run the pFUnit unit tests (default: off,
#                         as in every other builder).  CI always passes this.
#   --build_dir DIR       Build directory (default: $TURBO_STACK_ROOT/build/default,
#                         i.e. what CI uses).  Deps land in $DIR/deps/.  A path
#                         outside the checkout is mounted in as well -- prefer one,
#                         so the container never writes into your clone.
#   --debug               Build with CMAKE_BUILD_TYPE=Debug (passed through)
#   --clean               Clean rebuild from scratch (passed through: wipes the
#                         Stage-1 dep builds/installs, plus cmake --fresh)
#   --ninja               Use the Ninja generator (passed through)
#   --parallel N, -j N    Parallel build jobs.  Exported into the container as
#                         CMAKE_BUILD_PARALLEL_LEVEL (CI sets 4).  Default: nproc.
#   --image REF           Container image (default: the tag CI consumes, below).
#                         `gcc-openmpi` is MUTABLE -- pin gcc-openmpi-<sha> to
#                         reproduce a specific CI run.
#   --pull                Refresh the image before running (it is pulled
#                         automatically when absent).
#   --shell               Start an interactive shell in the container instead of
#                         building -- same mounts and environment.  For iterating
#                         on a failure: re-run ctest, poke at CMake, etc.
#   --as-me               Run the container as your own uid:gid instead of root.
#                         Diverges from CI, and spack re-clones its 180 MB package
#                         repo into the per-user HOME on first use (cached across
#                         runs under $TURBO_CI_CONTAINER_HOME).
#   --engine CMD          Container CLI (default: docker, else podman)
#   --fix-ownership       Chown the build artifacts back to you and exit.  For
#                         cleaning up after a run that was killed before the
#                         automatic chown-back could fire.
#   -h, --help            Print this usage text and exit.
#
# Configuration (env vars):
#   TURBO_CI_IMAGE            Default image (overrides the built-in default)
#   TURBO_CONTAINER_ENGINE    Default container CLI
#   TURBO_CI_CONTAINER_HOME   HOME for --as-me (default: $TMPDIR/turbo_ci_container_home)
#   CMAKE_BUILD_PARALLEL_LEVEL  Parallel jobs, when --parallel is not given
#
# Examples:
#   scripts/run_ci_container.sh --infra TIM --tests            # what CI runs, TIM
#   scripts/run_ci_container.sh --infra FMS2 --tests \
#       --build_dir /tmp/turbo-ci/fms2                         # keep the clone clean
#   scripts/run_ci_container.sh --shell                        # poke around inside
#   scripts/run_ci_container.sh --pull --image \
#       ghcr.io/turbo-esm/turbo-stack/turbo-ci:gcc-openmpi-5feaf15   # pin an image

set -eo pipefail

# Source the shared library (defines the builder arg parser + helpers; no side
# effects).  This script lives in scripts/, so the library is the sibling lib/.
# shellcheck source=/dev/null
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# Must match `container.image` in .github/workflows/turbo-cmake-container-tests.yaml.
_default_image="ghcr.io/turbo-esm/turbo-stack/turbo-ci:gcc-openmpi"

# --- container-only options ----------------------------------------------------
# Pre-strip them before the common parser sees them (the shared
# turbo_parse_builder_args rejects unknown flags, by design -- same idiom as
# --recreate-spack-env in build_local_with_spack_env.sh, but a while loop because
# some of these take a value).
_image="${TURBO_CI_IMAGE:-$_default_image}"
_engine="${TURBO_CONTAINER_ENGINE:-}"
_pull=false
_shell=false
_as_me=false
_fix_ownership=false
_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --image)         _turbo_opt_needs_value "$1" "$#" || exit 1; _image="$2"; shift 2 ;;
        --engine)        _turbo_opt_needs_value "$1" "$#" || exit 1; _engine="$2"; shift 2 ;;
        --pull)          _pull=true; shift ;;
        --shell)         _shell=true; shift ;;
        --as-me)         _as_me=true; shift ;;
        --fix-ownership) _fix_ownership=true; shift ;;
        *)               _args+=("$1"); shift ;;
    esac
done

# Everything else is the standard builder vocabulary (--infra/--tests/--build_dir/
# --debug/--clean/--ninja/--parallel/--help), validated once, in one place, and
# forwarded verbatim to the builder inside the container.
turbo_parse_builder_args "${_args[@]}"
turbo_resolve_stack_root

# --- container engine ----------------------------------------------------------
if [[ -z "$_engine" ]]; then
    if command -v docker >/dev/null 2>&1; then
        _engine=docker
    elif command -v podman >/dev/null 2>&1; then
        _engine=podman
    else
        echo "Error: no container engine found (looked for docker, then podman)." >&2
        echo "       Install one, or point --engine / \$TURBO_CONTAINER_ENGINE at it." >&2
        exit 1
    fi
fi
if ! command -v "$_engine" >/dev/null 2>&1; then
    echo "Error: container engine '$_engine' is not on PATH." >&2
    exit 1
fi
if ! "$_engine" info >/dev/null 2>&1; then
    echo "Error: '$_engine info' failed -- the daemon is not reachable." >&2
    echo "       Start it (e.g. 'sudo systemctl start docker' or Docker Desktop), and" >&2
    echo "       make sure your user may talk to it (the 'docker' group, or rootless)." >&2
    exit 1
fi

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
    echo "       read:packages (see docker/README.md):" >&2
    echo "         echo \"\$GHCR_TOKEN\" | $_engine login ghcr.io -u <github-user> --password-stdin" >&2
    echo "       Or build the image yourself (~1 h) and select it with --image:" >&2
    echo "         $_engine buildx build --load -f docker/Dockerfile.turbo-ci -t turbo-ci:gcc-openmpi ." >&2
    echo "         $(basename -- "$0") --image turbo-ci:gcc-openmpi ..." >&2
    return 1
}

# --- paths: what to mount, and what to hand back afterwards --------------------
# Mount the checkout at its OWN path: TURBO_STACK_ROOT then self-locates to the
# same value inside the container as out, so log lines, CMakeCache.txt entries and
# ctest paths are valid on both sides.
_mounts=(-v "$TURBO_STACK_ROOT:$TURBO_STACK_ROOT")

# In a git WORKTREE, .git is a file pointing at <main repo>/.git/worktrees/<name> --
# an absolute path outside this checkout -- and the submodule gitdirs live under it
# too.  Without that directory every `git` call inside the container dies with
# "fatal: not a git repository", and build_dep cannot read the source SHA for its
# rebuild sentinel.  Mount it read-only: the build only reads SHAs, and a root
# container has no business writing to the main repo's .git.  A normal clone keeps
# .git inside the checkout, so this adds no mount at all.
_git_common=$(git -C "$TURBO_STACK_ROOT" rev-parse --git-common-dir 2>/dev/null || true)
if [[ "$_git_common" == /* && "$_git_common" != "$TURBO_STACK_ROOT"/* ]]; then
    _git_common=$(cd -P -- "$_git_common" && pwd)
    _mounts+=(-v "$_git_common:$_git_common:ro")
else
    _git_common=""
fi

_build_dir=""
if [[ -n "$TURBO_B_BUILD_DIR" ]]; then
    mkdir -p "$TURBO_B_BUILD_DIR"
    # Normalize: the mount needs an absolute path, and forwarding the same
    # absolute path keeps host and container in agreement.
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

# --- --fix-ownership: chown and exit ------------------------------------------
_uidgid="$(id -u):$(id -g)"
_chown_q=$(printf '%q ' "${_chown_targets[@]}")
if [[ "$_fix_ownership" == true ]]; then
    _ensure_image || exit 1
    echo "[ci-container] restoring ownership ($_uidgid) of: ${_chown_targets[*]}"
    "$_engine" run --rm "${_mounts[@]}" "$_image" \
        bash -c "_t=($_chown_q); chown -R $_uidgid -- \"\${_t[@]}\" >/dev/null 2>&1 || true"
    exit 0
fi

# --- preflight: the submodules the container consumes but cannot fetch ---------
# Spack supplies Tier 1 + 1.5, so this is the same guard set as
# build_local_with_spack_env.sh: MOM6 + MARBL, plus the selected backend.
turbo_guard_builder_submodules 2
_ensure_image || exit 1

# CI has no source overrides -- it tests the pinned submodules.  Honoring a host
# override would mean mounting that tree too, which is a different (useful, but
# not-CI) thing; say so instead of silently ignoring it.
for _v in MOM6_ROOT FMS_ROOT TIM_ROOT PFUNIT_ROOT AMREX_ROOT; do
    if [[ -n "${!_v}" ]]; then
        echo "[ci-container] note: $_v is set on the host but is NOT forwarded into the"
        echo "[ci-container]       container -- it builds the pinned submodule, as CI does."
    fi
done

# --- the run: mounts, environment, user ---------------------------------------
# The two env settings the consumer workflow sets on the job (everything else the
# build needs -- SPACK_ROOT, OMPI_ALLOW_RUN_AS_ROOT{,_CONFIRM} -- is baked into the
# image).  CMAKE_BUILD_PARALLEL_LEVEL is read natively by every `cmake --build` in
# the pipeline (deps + turbo-stack), so no per-call flag plumbing is needed.
_jobs="${TURBO_B_PARALLEL:-${CMAKE_BUILD_PARALLEL_LEVEL:-}}"
[[ -n "$_jobs" ]] || _jobs="$(command -v nproc >/dev/null 2>&1 && nproc || echo 4)"
_env=(-e "CMAKE_BUILD_PARALLEL_LEVEL=$_jobs")
# The pFUnit suites run `mpirun -np 4` (@test(npes=[1,2,4])); OpenMPI 5's PRRTE
# refuses to launch that on a host with fewer slots.  Harmless on a big machine.
_env+=(-e "PRTE_MCA_rmaps_default_mapping_policy=${PRTE_MCA_rmaps_default_mapping_policy:-:oversubscribe}")

_user=()
if [[ "$_as_me" == true ]]; then
    # Spack 1.x fetches its package repo into $HOME on first use, and the image's
    # 180 MB cache lives in root's home.  Give the run a persistent HOME on the
    # host so that clone happens once, not once per container.
    _home="${TURBO_CI_CONTAINER_HOME:-${TMPDIR:-/tmp}/turbo_ci_container_home}"
    mkdir -p "$_home"
    _mounts+=(-v "$_home:$_home")
    _user=(--user "$_uidgid" -e "HOME=$_home")
fi

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

# --- the command CI runs, inside the container --------------------------------
# Mirrors the two `run:` steps of turbo-cmake-container-tests.yaml, in order.  The
# EXIT trap hands the bind-mounted artifacts back to the caller -- even when the
# build fails -- so running as root (like CI) leaves nothing root-owned behind.
# Nothing is exec'd: exec would replace the shell and the trap would never fire.
_build_args=()
[[ "$TURBO_B_DEBUG" == true ]] && _build_args+=(--debug)
[[ "$TURBO_B_CLEAN" == true ]] && _build_args+=(--clean)
[[ "$TURBO_B_NINJA" == true ]] && _build_args+=(--ninja)
_build_args+=(--infra "$TURBO_B_INFRA")
[[ "$TURBO_B_TESTS" == true ]] && _build_args+=(--tests)
[[ -n "$_build_dir" ]] && _build_args+=(--build_dir "$_build_dir")

_lines=("set -eo pipefail")
if [[ "$_as_me" != true ]]; then
    # Materialize the targets as an array (printf %q makes that quote-safe) so the
    # trap body can reference them without nesting quotes inside its own quoting.
    _lines+=("_t=($_chown_q)")
    # INT/TERM too, so a Ctrl-C'd build still hands its artifacts back (bash does
    # not run EXIT traps for untrapped fatal signals).
    _lines+=("trap 'rc=\$?; chown -R $_uidgid -- \"\${_t[@]}\" >/dev/null 2>&1 || true; exit \$rc' EXIT INT TERM")
fi
# Assert the prebaked env, as the workflow's first step does.  Without it,
# spack_local_environment.sh's default --create-if-missing applies and a wrong or
# stale image would not error -- it would silently start a ~1 h from-source
# dependency build.  Fail in seconds instead.
_lines+=("if ! ( . \"\$SPACK_ROOT/share/spack/setup-env.sh\" && spack env list | grep -qw turbo_stack ); then")
_lines+=("    echo \"Error: image '$_image' has no prebaked 'turbo_stack' Spack env.\" >&2")
_lines+=("    echo \"       Refusing: the pipeline would silently build the whole dependency\" >&2")
_lines+=("    echo \"       stack from source (~1 h).  Use the CI image, or rebuild it --\" >&2")
_lines+=("    echo \"       see docker/README.md.\" >&2")
_lines+=("    exit 1")
_lines+=("fi")
# Root against a checkout owned by another uid: git refuses without this (the
# workflow has the same step).
_lines+=("git config --global --add safe.directory '*'")
# The image bakes spack.yaml at image-build time and the producer workflow is
# manual, so the env can lag this checkout's spec -- more easily here than in CI,
# since refreshing the image locally is a ~1 h build.  Warn, never fail: the
# decoupling is deliberate and the CMake lane does not need every spec present.
# (Same check, and same rationale, as the workflow's staleness step.)
_lines+=("if ! diff -q /opt/turbo-spack/spack.yaml spack/spack.yaml >/dev/null 2>&1; then")
_lines+=("    echo \"[ci-container] warning: the image's baked spack.yaml differs from this checkout\"")
_lines+=("    echo \"[ci-container]          -- the image may predate a spec you added.  Refresh it with\"")
_lines+=("    echo \"[ci-container]          'gh workflow run build-turbo-ci-container.yaml' (see docker/README.md).\"")
_lines+=("    diff -u /opt/turbo-spack/spack.yaml spack/spack.yaml || true")
_lines+=("fi")
if [[ "$_shell" == true ]]; then
    _lines+=("echo '[ci-container] The spack env is NOT activated -- the repo scripts own that.'")
    _lines+=("echo '[ci-container] Activate it by hand with:'")
    _lines+=("echo '    . \$SPACK_ROOT/share/spack/setup-env.sh && spack env activate turbo_stack'")
    _lines+=("echo '[ci-container] Or just run the pipeline: scripts/build_local_with_spack_env.sh --infra $TURBO_B_INFRA --tests'")
    _lines+=("bash -l")
else
    _lines+=("$(printf '%q ' scripts/build_local_with_spack_env.sh "${_build_args[@]}")")
fi

echo "[ci-container] engine    = $_engine"
echo "[ci-container] image     = $_image"
echo "[ci-container] mount     = $TURBO_STACK_ROOT (same path inside the container)"
[[ -n "$_git_common" ]] && \
    echo "[ci-container] git dir   = $_git_common (read-only; this checkout is a worktree)"
echo "[ci-container] user      = $([[ "$_as_me" == true ]] && echo "$_uidgid (--as-me)" || echo "root (as CI)")"
echo "[ci-container] jobs      = $_jobs"
echo "[ci-container] artifacts = ${_chown_targets[*]}"

"$_engine" run --rm --init "${_tty[@]}" "${_user[@]}" "${_mounts[@]}" "${_env[@]}" \
    -w "$TURBO_STACK_ROOT" "$_image" \
    bash -c "$(printf '%s\n' "${_lines[@]}")"
