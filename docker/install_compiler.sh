#!/bin/bash
# docker/install_compiler.sh FAMILY
#
# Installs one compiler toolchain into the turbo-ci image and makes it the one
# everything uses. Run by docker/Dockerfile.turbo-ci (step 3), after Spack is
# cloned and before the turbo_stack env is baked. It:
#
#   1. installs the compiler from the distribution's packages (no compiler is
#      ever built from source);
#   2. points /opt/turbo-compiler/bin/{cc,c++,fc} at it. The Dockerfile sets
#      CC/CXX/FC to those fixed paths, so the ENV is the same for every flavor;
#   3. registers it with Spack, searching only that compiler's directory, and
#      writes its exact Spack spec (e.g. gcc@13.3.0) to
#      /opt/turbo-compiler/spack-spec, which the Dockerfile requires for every
#      package.
#
# FAMILY is the Spack package name of the compiler.
#
# Supported:
#   gcc    the distribution's default gcc/g++/gfortran
#
# Adding a family is one case below: install it, then set cc/cxx/fc/bindir, the
# string its Fortran `--version` output must contain, and the flag that prints its
# version the way Spack reports it.

set -euo pipefail

family=${1:?usage: install_compiler.sh FAMILY}

die() { echo "install_compiler.sh: $*" >&2; exit 1; }

case "$family" in
    gcc)
        apt-get update
        apt-get install -y --no-install-recommends gcc g++ gfortran
        rm -rf /var/lib/apt/lists/*
        bindir=/usr/bin
        cc=$bindir/gcc cxx=$bindir/g++ fc=$bindir/gfortran
        fc_banner="GNU Fortran"
        version_flag=-dumpfullversion   # how Spack reads a GCC's version
        ;;
    *)
        die "unsupported compiler family '$family' (supported: gcc)"
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

# All three drivers must be one version, the one recorded for Spack below.
# Otherwise CMake could compile C/C++ with a different version than Spack used.
version=$("$fc" "$version_flag")
for drv in "$cc" "$cxx"; do
    [[ $("$drv" "$version_flag") == "$version" ]] \
        || die "$drv is not version $version, like $fc"
done

# shellcheck source=/dev/null
. "$SPACK_ROOT/share/spack/setup-env.sh"
spack compiler find "$bindir"
spack compiler list

# The family alone is not enough: `spack compiler find` registers every compiler
# in $bindir, and Spack prefers the newest, so with a second GCC in /usr/bin it
# would build the stack with that one while CC/CXX/FC point here.
spec="$family@$version"
# Spack v1.2.2's `spack compiler list`, piped, prints one bare spec per line (e.g.
# gcc@13.3.0), with no header or marker, and -x matches the whole line. A SPACK_REF
# bump that decorates those lines makes this die even though the compiler registered.
grep -qx "$spec" <<< "$(spack compiler list)" || die "Spack did not register $spec"
echo "$spec" > /opt/turbo-compiler/spack-spec
