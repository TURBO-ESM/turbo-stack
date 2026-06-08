#!/bin/bash
# CXX dispatch for the TIM GPU (offload) build.
#
# Any C++ TU that includes AMReX headers must be compiled by nvcc: nvc++ (the
# Cray `CC` wrapper) reports "CUDA C++ compilation is unsupported in nvc++" and
# leaves AMReX's __host__/__device__ undefined. We drive those with
# `nvcc -ccbin CC` so nvcc handles the CUDA/device side while the Cray `CC`
# wrapper remains the host compiler (keeping its automatic MPI/netCDF includes,
# which tim_coms_infra.cpp needs). All non-AMReX C++ stays on plain CC.
#
# The AMReX-including TUs on dev/turbo-debug (keep in sync if more are ported):
#   mom/cpp/mom_continuity_ppm.cpp, mom/cpp/turbotmp_mom_continuity_ppm_bridge.cpp,
#   turbotmp/turbotmp_helper.cpp, tim/cpp/tim_profile.cpp, tim/cpp/tim_coms_infra.cpp
#
# mkmf invokes this as: <wrap> <CPPDEFS> <CPPFLAGS> <CXXFLAGS> <includes> -c -I.. file.cpp

is_amrex=0
for a in "$@"; do
  case "$a" in
    *mom_continuity_ppm.cpp|*turbotmp_mom_continuity_ppm_bridge.cpp|\
*turbotmp_helper.cpp|*tim_profile.cpp|*tim_coms_infra.cpp)
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
