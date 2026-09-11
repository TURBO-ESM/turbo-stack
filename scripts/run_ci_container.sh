#!/bin/bash
# Usage: ./scripts/run_ci_container.sh [options]
#
# Build turbo-stack (+ the pFUnit unit tests, with --tests) for ONE infra backend
# against a READY-MADE environment: ghcr.io/turbo-esm/turbo-stack/turbo-ci, the
# image CI uses, which ships the compiler and the Tier 1 + Tier 1.5 dependencies
# (MPI, NetCDF, CMake, pFUnit, AMReX) already installed in a Spack env.  You supply
# the rest: this mounts your checkout, builds the Tier-2 backend (FMS or TIM) from
# its submodule, then builds and tests turbo-stack against the MOM6 tree you point
# at -- on whatever branch it happens to be checked out.
#
#     scripts/run_ci_container.sh --infra TIM --tests
#     scripts/run_ci_container.sh --infra TIM --tests --mom6-root ~/projects/MOM6
#
# No toolchain setup on the host, and no waiting on Actions to find out whether a
# MOM6 branch still builds.  To sweep several MOM6 branches, switch branches in
# that tree and run again; for both backends in one go plus a matrix/verdict, use
# ./test_turbo_stack_in_ci_container.sh, which calls this script once per backend.
#
# Because it is CI's image and CI's command
# (scripts/build_local_with_spack_env.sh --infra <backend> --tests), plus the two
# environment settings that workflow sets (CMAKE_BUILD_PARALLEL_LEVEL and the PRRTE
# oversubscribe policy the MPI tests need), its safe.directory step and its two
# guardrails, a red box in .github/workflows/cmake-build.yaml usually reproduces
# here.  Usually, not always: CI also runs a MOM6 branch checked out fresh beside
# the workspace, where this builds the tree you hand it.
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
#   --infra FMS2|TIM      Infrastructure backend (default: TIM).  One per run.
#   --tests               Also build + run the pFUnit unit tests (default: off,
#                         as in every other builder).  CI always passes this.
#   --mom6-root DIR       Build this MOM6 tree instead of the pinned submodule, at
#                         whatever branch it is checked out on.  The tree is
#                         mounted at its own path and MOM6_ROOT is forwarded.  Its
#                         nested submodules (pkg/CVMix-src, pkg/GSW-Fortran) must be
#                         initialized.  Defaults to $MOM6_ROOT when that is
#                         exported, as in every other entry point.
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
#   scripts/run_ci_container.sh --infra TIM --tests            # pinned MOM6, TIM
#   scripts/run_ci_container.sh --infra TIM --tests \
#       --mom6-root ~/projects/MOM6                            # your MOM6, as checked out
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
_mom6_root="${MOM6_ROOT:-}"
_args=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --image)         _turbo_opt_needs_value "$1" "$#" || exit 1; _image="$2"; shift 2 ;;
        --engine)        _turbo_opt_needs_value "$1" "$#" || exit 1; _engine="$2"; shift 2 ;;
        --mom6-root)     _turbo_opt_needs_value "$1" "$#" || exit 1; _mom6_root="$2"; shift 2 ;;
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

# --- MOM6 source: the pinned submodule, or a tree you point at -----------------
# The whole point of this wrapper is to build YOUR MOM6 against a ready-made
# toolchain, so --mom6-root (or an exported MOM6_ROOT, as everywhere else in the
# repo) mounts that tree and forwards MOM6_ROOT into the container.  Whatever
# branch the tree is checked out on is what gets built -- switch branches on the
# host and re-run; nothing here knows or cares about branch names.
#
# Mounted read-write, not :ro, because MOM6's build writes nothing into the source
# but git may refresh its index there; the build dir is elsewhere either way.
_mom6_note=""
if [[ -n "$_mom6_root" ]]; then
    [[ -d "$_mom6_root" ]] || {
        echo "Error: --mom6-root '$_mom6_root' is not a directory." >&2
        exit 1
    }
    _mom6_root=$(cd -P -- "$_mom6_root" && pwd)
    [[ -f "$_mom6_root/CMakeLists.txt" ]] || {
        echo "Error: '$_mom6_root' has no CMakeLists.txt -- that is not a MOM6 checkout" >&2
        echo "       with the CMake build system (it lives on dev/turbo* branches)." >&2
        exit 1
    }
    # MOM6's top-level CMakeLists hard-fails without these; catch it here rather
    # than 20 minutes into a container build.  CI gets them via submodules:recursive.
    for _p in pkg/CVMix-src pkg/GSW-Fortran; do
        [[ -e "$_mom6_root/$_p/.git" ]] || {
            echo "Error: MOM6 submodule '$_p' is not initialized in $_mom6_root." >&2
            echo "       git -C \"$_mom6_root\" submodule update --init --recursive" >&2
            exit 1
        }
    done
    # Same worktree reasoning as the checkout above: build_dep reads source SHAs
    # with git, which needs the real git dir when .git is a file pointing out.
    _mom6_git=$(git -C "$_mom6_root" rev-parse --git-common-dir 2>/dev/null || true)
    [[ "$_mom6_git" == /* ]] && _mom6_git=$(cd -P -- "$_mom6_git" && pwd) || _mom6_git=""
    if [[ "$_mom6_root" != "$TURBO_STACK_ROOT" && "$_mom6_root" != "$TURBO_STACK_ROOT"/* ]]; then
        _mounts+=(-v "$_mom6_root:$_mom6_root")
        [[ -n "$_mom6_git" && "$_mom6_git" != "$_mom6_root"/* ]] && \
            _mounts+=(-v "$_mom6_git:$_mom6_git:ro")
    fi
    # Exported so turbo_guard_builder_submodules below skips the submodules/MOM6
    # check (the wrappers all treat a set *_ROOT as "this one comes from elsewhere").
    export MOM6_ROOT="$_mom6_root"
    _mom6_note="$_mom6_root ($(git -C "$_mom6_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'not a git tree'))"
else
    _mom6_note="submodules/MOM6 (the pinned commit)"
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

# MOM6 is the one source you can swap (--mom6-root, handled above): it is what you
# iterate on.  The rest would each need their own mount and their own tier of the
# build reworked, so they are not forwarded -- say so rather than ignoring them
# silently, since the host value would otherwise look like it took effect.
for _v in FMS_ROOT TIM_ROOT PFUNIT_ROOT AMREX_ROOT; do
    if [[ -n "${!_v}" ]]; then
        echo "[ci-container] note: $_v is set on the host but is NOT forwarded into the"
        echo "[ci-container]       container -- it builds the pinned submodule."
        echo "[ci-container]       (MOM6 is swappable: --mom6-root DIR.)"
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
# The mounted MOM6 tree, at the same path inside as out (see the mount above).
# build_turbo_stack.sh's CMake reads MOM6_ROOT; unset, it falls back to the submodule.
[[ -n "${MOM6_ROOT:-}" ]] && _env+=(-e "MOM6_ROOT=$MOM6_ROOT")

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
echo "[ci-container] MOM6      = $_mom6_note"
echo "[ci-container] user      = $([[ "$_as_me" == true ]] && echo "$_uidgid (--as-me)" || echo "root (as CI)")"
echo "[ci-container] jobs      = $_jobs"
echo "[ci-container] artifacts = ${_chown_targets[*]}"

"$_engine" run --rm --init "${_tty[@]}" "${_user[@]}" "${_mounts[@]}" "${_env[@]}" \
    -w "$TURBO_STACK_ROOT" "$_image" \
    bash -c "$(printf '%s\n' "${_lines[@]}")"
