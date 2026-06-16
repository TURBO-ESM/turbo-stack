#!/bin/bash
# TEMPORARY: per-file CXX dispatch for the TIM GPU (offload) build, to be
# removed by the build-system overhaul. AMReX TUs need nvcc (nvc++/Cray `CC`
# can't compile CUDA); everything else stays on plain `CC`. This file will be
# removed once the CMake build system is fully implemented.

is_amrex=0
for a in "$@"; do
  case "$a" in
    */mom/cpp/*.cpp|*turbotmp_helper.cpp|*tim_profile.cpp|*tim_coms_infra.cpp)
      is_amrex=1 ;;
  esac
done

if [ "${is_amrex}" -eq 1 ]; then
  # Drop nvc++-only flags nvcc would reject; keep -D, -I, -c, the source.
  args=()
  for x in "$@"; do
    case "$x" in
      --std=*|-cuda|-gpu=*|-mp=*|-Minfo=*|-Mnofma|-gopt|-time|-tp=*) ;;
      *) args+=("$x") ;;
    esac
  done
  exec nvcc -x cu -arch=sm_80 --extended-lambda --expt-relaxed-constexpr \
       -std=c++17 -ccbin CC "${args[@]}"
fi

exec CC "$@"
