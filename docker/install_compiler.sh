#!/bin/bash
# docker/install_compiler.sh FAMILY [VERSION]
#
# Installs one compiler toolchain into the turbo-ci image and makes it the one
# everything uses. Run by docker/Dockerfile.turbo-ci (step 3), after Spack is
# cloned and before the turbo_stack env is baked. It:
#
#   1. installs the compiler from apt packages (no compiler is ever built from
#      source);
#   2. points /opt/turbo-compiler/bin/{cc,c++,fc} at it. The Dockerfile sets
#      CC/CXX/FC to those fixed paths, so the ENV is the same for every flavor;
#   3. registers it with Spack, searching only that compiler's directory.
#
# FAMILY is the Spack package name of the compiler, since the Dockerfile also
# passes it to create_spack_environment.sh as TURBO_SPACK_COMPILER.
#
# Supported:
#   gcc    the distribution's default gcc/g++/gfortran; VERSION must be empty
#   llvm   clang/clang++/flang from apt.llvm.org; VERSION is the LLVM major
#          version (required). apt.llvm.org has one repository per major
#          version, so that is what VERSION pins; the point release floats.
#
# Adding a family is one case below: install it, then set cc/cxx/fc/bindir and
# the string its Fortran `--version` output must contain.

set -euo pipefail

family=${1:?usage: install_compiler.sh FAMILY [VERSION]}
version=${2:-}

die() { echo "install_compiler.sh: $*" >&2; exit 1; }

case "$family" in
    gcc)
        [[ -z "$version" ]] || die "gcc: only the distribution default is supported (got VERSION='$version')"
        apt-get update
        apt-get install -y --no-install-recommends gcc g++ gfortran
        rm -rf /var/lib/apt/lists/*
        bindir=/usr/bin
        cc=$bindir/gcc cxx=$bindir/g++ fc=$bindir/gfortran
        fc_banner="GNU Fortran"
        ;;
    llvm)
        [[ -n "$version" ]] || die "llvm: VERSION (the LLVM major version, e.g. 21) is required"
        # shellcheck source=/dev/null
        codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
        install -d -m 0755 /etc/apt/keyrings
        curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key -o /etc/apt/keyrings/apt.llvm.org.asc
        echo "deb [signed-by=/etc/apt/keyrings/apt.llvm.org.asc] https://apt.llvm.org/$codename/ llvm-toolchain-$codename-$version main" \
            > /etc/apt/sources.list.d/apt.llvm.org.list
        apt-get update
        # libclang-rt is compiler-rt. Spack's m4 recipe links with
        # -rtlib=compiler-rt under clang; without it m4 fails with "C compiler
        # cannot create executables" and takes all of MPI and NetCDF down with it.
        apt-get install -y --no-install-recommends \
            "clang-$version" "flang-$version" "lld-$version" \
            "libomp-$version-dev" "libclang-rt-$version-dev"
        rm -rf /var/lib/apt/lists/*
        bindir=/usr/lib/llvm-$version/bin
        cc=$bindir/clang cxx=$bindir/clang++ fc=$bindir/flang
        fc_banner="flang version"
        ;;
    *)
        die "unsupported compiler family '$family' (supported: gcc, llvm)"
        ;;
esac

mkdir -p /opt/turbo-compiler/bin
ln -sfn "$cc"  /opt/turbo-compiler/bin/cc
ln -sfn "$cxx" /opt/turbo-compiler/bin/c++
ln -sfn "$fc"  /opt/turbo-compiler/bin/fc

# Catch a wrong symlink here rather than as a confusing CMake failure later.
# A here-string, not a pipe: under pipefail, `grep -q` exiting at its first match
# can SIGPIPE the writer and fail the check even though it matched.
grep -q "$fc_banner" <<< "$(/opt/turbo-compiler/bin/fc --version)" \
    || die "/opt/turbo-compiler/bin/fc -> $fc does not report '$fc_banner'"

# shellcheck source=/dev/null
. "$SPACK_ROOT/share/spack/setup-env.sh"
spack compiler find "$bindir"
spack compiler list
