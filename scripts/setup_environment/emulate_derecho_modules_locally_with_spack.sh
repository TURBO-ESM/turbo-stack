#!/bin/bash
# scripts/setup_environment/emulate_derecho_modules_locally_with_spack.sh
#
# SOURCED. Temporary driver that emulates a module-based machine (Derecho)
# on the laptop. Uses spack ONLY for the parts that come from Lmod on
# Derecho -- compiler, MPI, NetCDF, CMake. FMS, pFUnit, AMReX, and TIM are
# built from source by scripts/build_dependencies_from_source.sh; MOM6
# source comes from MOM6_ROOT (or submodule if unset).
#
# Once scripts/setup_environment/derecho_cpu_gcc_openmpi.sh is verified against real Lmod modules,
# delete this file and spack/derecho_modules_emulation_with_spack.yaml.
#
# Usage:
#   source scripts/setup_environment/emulate_derecho_modules_locally_with_spack.sh [build_dependencies_from_source.sh args]

if [[ -z "${TURBO_STACK_ROOT:-}" ]]; then
    echo "Error: TURBO_STACK_ROOT is not set." >&2
    return 1 2>/dev/null || exit 1
fi
if [[ -z "${SPACK_ROOT:-}" ]]; then
    echo "Error: SPACK_ROOT is not set." >&2
    return 1 2>/dev/null || exit 1
fi
if [[ ! -f "$SPACK_ROOT/share/spack/setup-env.sh" ]]; then
    echo "Error: SPACK_ROOT ($SPACK_ROOT) is not a valid Spack installation." >&2
    return 1 2>/dev/null || exit 1
fi

# shellcheck source=/dev/null
source "$SPACK_ROOT/share/spack/setup-env.sh"

_emu_env="derecho_modules_emulation_with_spack"
_emu_yaml="$TURBO_STACK_ROOT/spack/${_emu_env}.yaml"

if ! spack env list | grep -qw "$_emu_env"; then
    echo "Error: spack env '$_emu_env' does not exist." >&2
    echo "Create it once with:" >&2
    echo "  bash $TURBO_STACK_ROOT/spack/create_spack_environment.sh $_emu_env $_emu_yaml" >&2
    unset _emu_env _emu_yaml
    return 1 2>/dev/null || exit 1
fi

if ! spack env activate "$_emu_env"; then
    echo "Error: failed to activate spack env '$_emu_env'" >&2
    unset _emu_env _emu_yaml
    return 1 2>/dev/null || exit 1
fi

unset _emu_env _emu_yaml

# Build FMS + pFUnit + AMReX + TIM from source, set up MOM6_ROOT / TIM_ROOT,
# export CMAKE_PREFIX_PATH and PFUNIT_DIR.
# shellcheck source=/dev/null
source "$TURBO_STACK_ROOT/scripts/build_dependencies_from_source.sh" "$@"
