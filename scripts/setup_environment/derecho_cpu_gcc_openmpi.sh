#!/bin/bash

module purge
module load gcc cmake openmpi netcdf #pfunit

# Tempoary fix to get the right c++ standard library picked up for TIM, which is built with gcc 14.3.0 on Derecho but the default compiler is still older gcc
export LIBRARY_PATH=/glade/u/apps/common/25.10/spack/opt/spack/gcc/14.3.0/nw2m/lib64:$LIBRARY_PATH