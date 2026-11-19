#!/usr/bin/env bash
# scripts/test_protomomxx_gpu.sh
#
# Build AMReX with the CUDA GPU backend, build protoMOMxx's standalone solo
# driver against it, then run protoMOMxx's double_gyre smoke test and compare
# its output to the golden regression fixture.
#
# Standalone on purpose: this does NOT go through turbo-stack's TIM-backend
# pipeline (build_turbo_stack.sh) or scripts/lib/common.sh's turbo_build_amrex
# / turbo_build_protomomxx wrappers, which build a KERNELS_ONLY protoMOMxx for
# MOM6's Fortran<->C++ bridge and never enable CUDA. This exercises
# protoMOMxx's own full solo-driver executable under -DPROTOMOM_CUDA=ON, the
# same way it was hand-verified on an NCAR Casper A100 node.
#
# Requires a CUDA-aware NVHPC toolchain already on PATH: nvcc, nvc++,
# nvfortran, and an MPI compiler wrapper (mpicc). This script sets up none of
# that -- Stage 1 (toolchain) is the caller's job, same split as every other
# build script here (see scripts/README.md). On an NCAR HPC system, `module
# load` the toolchain first; in CI, the container image already has it on
# PATH.
#
# Usage:
#   scripts/test_protomomxx_gpu.sh [--build_dir DIR] [--parallel N] [--clean]
#
# Environment:
#   AMREX_CUDA_ARCH          CUDA architecture to target AMReX's build for
#                            (default: Auto, i.e. detect from the GPU visible
#                            to the configuring process -- there must be one).
#   CMAKE_CUDA_HOST_COMPILER Defaults to `which nvc++`. AMReX's own
#                            static_assert requires its CUDA host compiler to
#                            be the same NVHPC nvc++ used for its C++/Fortran.

set -euo pipefail

SCRIPT_DIR=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/build_dep.sh"

turbo_resolve_stack_root
turbo_require_submodule submodules/amrex AMReX AMREX_ROOT
turbo_require_submodule submodules/protoMOMxx protoMOMxx PROTOMOMXX_ROOT

BUILD_DIR="$TURBO_STACK_ROOT/deps/gpu-smoketest"
PARALLEL=""
CLEAN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build_dir)   BUILD_DIR="$2"; shift 2 ;;
        --parallel|-j) PARALLEL="$2"; shift 2 ;;
        --clean)       CLEAN=true; shift ;;
        -h|--help)     turbo_print_header_usage "$0"; exit 0 ;;
        *) echo "Error: unknown option '$1'" >&2; exit 1 ;;
    esac
done

if [[ "$CLEAN" == true ]]; then
    echo "[gpu-smoketest] --clean: wiping $BUILD_DIR"
    rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"
INSTALL_PREFIX="$BUILD_DIR/install"

for tool in cmake nvcc mpicc; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "Error: '$tool' not found on PATH -- load the CUDA-aware toolchain first" >&2
        exit 1
    }
done

NVCXX=$(command -v nvc++) || { echo "Error: nvc++ not found on PATH" >&2; exit 1; }

# nvcc does not inject the MPI wrapper's include path the way nvc++/mpicxx do,
# so a .cu-language translation unit cannot find mpi.h on its own. Extract the
# include flags straight from the MPI compiler wrapper instead of assuming a
# layout; a plain MPICH/OpenMPI wrapper exposes them via `-show`. (On NCAR's
# Cray systems this needed $MPICH_DIR/include specifically, since cray-mpich's
# wrapper magic isn't visible to `-show` the same way.)
MPI_CUDA_FLAGS=$(mpicc -show 2>/dev/null | tr ' ' '\n' | grep '^-I' | paste -sd' ' -) || true

echo "[gpu-smoketest] nvcc:  $(command -v nvcc)"
echo "[gpu-smoketest] nvc++: $NVCXX"
echo "[gpu-smoketest] mpicc: $(command -v mpicc)"
echo "[gpu-smoketest] MPI include flags for CUDA sources: ${MPI_CUDA_FLAGS:-<none found>}"
nvidia-smi || echo "[gpu-smoketest] warning: nvidia-smi failed -- is a GPU visible to this process?"

PARALLEL_ARGS=()
[[ -n "$PARALLEL" ]] && PARALLEL_ARGS=(--parallel "$PARALLEL")

echo "[gpu-smoketest] Building AMReX (CUDA backend)..."
build_dep amrex --build-dir "$BUILD_DIR/amrex" --install-prefix "$INSTALL_PREFIX" \
    "${PARALLEL_ARGS[@]}" -- \
    -DAMReX_GPU_BACKEND=CUDA \
    -DAMReX_FORTRAN=ON \
    -DAMReX_FORTRAN_INTERFACES=ON \
    -DAMReX_MPI=ON \
    -DAMReX_TINY_PROFILE=ON \
    -DAMReX_CUDA_ARCH="${AMREX_CUDA_ARCH:-Auto}" \
    -DCMAKE_CUDA_HOST_COMPILER="$NVCXX" \
    -DCMAKE_CUDA_FLAGS="$MPI_CUDA_FLAGS" \
    -DCMAKE_Fortran_FLAGS="-noacc"

echo "[gpu-smoketest] Building protoMOMxx (CUDA backend, full solo driver)..."
build_dep protomomxx --build-dir "$BUILD_DIR/protomomxx" --install-prefix "$INSTALL_PREFIX" \
    "${PARALLEL_ARGS[@]}" -- \
    -DPROTOMOM_CUDA=ON \
    -DCMAKE_PREFIX_PATH="$INSTALL_PREFIX" \
    -DCMAKE_CUDA_HOST_COMPILER="$NVCXX" \
    -DCMAKE_CUDA_FLAGS="$MPI_CUDA_FLAGS"

PROTOMOMXX_SRC="${PROTOMOMXX_ROOT:-$TURBO_STACK_ROOT/submodules/protoMOMxx}"
PROTOMOMXX_BIN="$BUILD_DIR/protomomxx/protoMOMxx"
RUN_DIR="$BUILD_DIR/double_gyre_run"

echo "[gpu-smoketest] Setting up double_gyre run directory..."
rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"
cp "$PROTOMOMXX_SRC/tests/double_gyre/MOM_input" \
   "$PROTOMOMXX_SRC/tests/double_gyre/input.nml" \
   "$PROTOMOMXX_SRC/tests/double_gyre/MOM_override" \
   "$RUN_DIR/"

echo "[gpu-smoketest] Running protoMOMxx (double_gyre)..."
( cd "$RUN_DIR" && "$PROTOMOMXX_BIN" )

echo "[gpu-smoketest] Checking output against the golden double_gyre fixture..."
cmake -DEXPECTED_DIR="$PROTOMOMXX_SRC/tests/double_gyre" \
      -DACTUAL_DIR="$RUN_DIR" \
      -P "$PROTOMOMXX_SRC/tests/double_gyre/check_regression.cmake"

echo "[gpu-smoketest] PASS: protoMOMxx CUDA build smoketest + double_gyre regression matched the golden output."
