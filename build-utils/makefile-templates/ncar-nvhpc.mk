# Template for the PGI Compilers

############
# commands #
############

FC = ftn
CC = cc
CXX = CC
LD = ftn $(MAIN_PROGRAM)

############
#  flags   #
############

OFFLOAD =
DEBUG =
MAKEFLAGS += --jobs=8
LDFLAGS :=

FC_AUTO_R8 = -r8
FPPFLAGS := $(shell pkg-config --cflags yaml-0.1) -DHAVE_FC_DO_CONCURRENT_LOCAL
FFLAGS = $(FC_AUTO_R8) -Mnofma -i4 -gopt  -time -Mextend -byteswapio -Mflushz -Kieee -tp=zen3


CFLAGS = -gopt -time -Mnofma -DHAVE_GETTID
CPPFLAGS := $(shell pkg-config --cflags yaml-0.1)

CXXFLAGS := --std=c++20 -Mnofma -Kieee

# Get compile flags based on target macros.

ifeq ($(DEBUG),1)
  FFLAGS += -O0 -g
  CFLAGS += -O0 -g
  CXXFLAGS += -O0 -g
else
    FFLAGS += -O2
    CFLAGS += -O2
    CXXFLAGS += -O2
endif

ifeq ($(OFFLOAD),1)
  GPU_OPTS := cc80,mem:separate,nofma
  FFLAGS += -mp=gpu -gpu=$(GPU_OPTS) -stdpar=gpu -Minfo=accel
  CFLAGS += -mp=gpu -gpu=$(GPU_OPTS)
  # --fmad=false matches the Fortran -Mnofma; -Xptxas -O2 pins the device-code
  # optimization level. Exported so libamrex's nvcc compiles get it too.
  export NVCC_APPEND_FLAGS := --fmad=false -Xptxas -O2
  AMREX_GPU_FLAGS := -DAMReX_GPU_BACKEND=CUDA -DAMReX_CUDA_ARCH=8.0 -DAMReX_MPI=NO -DAMReX_DIFFERENT_COMPILER=ON
  LDFLAGS += -mp=gpu -cuda -gpu=$(GPU_OPTS) -c++libs -lmpi_gtl_cuda

  # TEMPORARY until the CMake build system lands: the AMReX TUs below must be
  # compiled by nvcc, while every other C++ TU keeps CXX = CC.
  # **NOTE:** New CUDA TUs must be added to CUDA_OBJS.
  CUDA_OBJS := mom_continuity_ppm.o mom_interface_heights.o \
               turbotmp_mom_continuity_ppm_bridge.o turbotmp_mom_interface_heights_bridge.o \
               turbotmp_helper.o tim_profile.o tim_coms_infra.o
  ifeq ($(DEBUG),1)
    NVCC_OPT := -O0 -g
  else
    NVCC_OPT := -O2
  endif
  $(CUDA_OBJS): CXX := nvcc
  $(CUDA_OBJS): CXXFLAGS := -x cu -arch=sm_80 --extended-lambda --expt-relaxed-constexpr \
                            -std=c++17 -ccbin CC -lineinfo $(NVCC_OPT) \
                            -Xcompiler -Mnofma -Xcompiler -Kieee
endif

CXXFLAGS += -Mnofma -Kieee

# NetCDF Flags
FFLAGS += $(shell nf-config --fflags)
CFLAGS += $(shell nc-config --cflags)

ifneq ($(findstring -Duse_netCDF,$(CPPDEFS)),)
  # add the use_LARGEFILE cppdef
  CPPDEFS += -Duse_LARGEFILE
endif

# Linking Flags
LDFLAGS += $(shell nc-config --libs) $(shell nf-config --flibs) -llapack -lblas -time -Wl,--allow-multiple-definition

#---------------------------------------------------------------------------
# you should never need to change any lines below.

# see the MIPSPro F90 manual for more details on some of the file extensions
# discussed here.
# this makefile template recognizes fortran sourcefiles with extensions
# .f, .f90, .F, .F90. Given a sourcefile <file>.<ext>, where <ext> is one of
# the above, this provides a number of default actions:

# make <file>.opt	create an optimization report
# make <file>.o		create an object file
# make <file>.s		create an assembly listing
# make <file>.x		create an executable file, assuming standalone
#			source
# make <file>.i		create a preprocessed file (for .F)
# make <file>.i90	create a preprocessed file (for .F90)

# The macro TMPFILES is provided to slate files like the above for removal.

RM = rm -f
TMPFILES = .*.m *.B *.L *.i *.i90 *.l *.s *.mod *.opt

.SUFFIXES: .F .F90 .H .L .T .f .f90 .h .i .i90 .l .o .s .opt .x

.f.L:
	$(FC) $(FFLAGS) -c -listing $*.f
.f.opt:
	$(FC) $(FFLAGS) -c -opt_report_level max -opt_report_phase all -opt_report_file $*.opt $*.f
.f.l:
	$(FC) $(FFLAGS) -c $(LIST) $*.f
.f.T:
	$(FC) $(FFLAGS) -c -cif $*.f
.f.o:
	$(FC) $(FFLAGS) -c $*.f
.f.s:
	$(FC) $(FFLAGS) -S $*.f
.f.x:
	$(FC) $(FFLAGS) -o $*.x $*.f *.o $(LDFLAGS)
.f90.L:
	$(FC) $(FFLAGS) -c -listing $*.f90
.f90.opt:
	$(FC) $(FFLAGS) -c -opt_report_level max -opt_report_phase all -opt_report_file $*.opt $*.f90
.f90.l:
	$(FC) $(FFLAGS) -c $(LIST) $*.f90
.f90.T:
	$(FC) $(FFLAGS) -c -cif $*.f90
.f90.o:
	$(FC) $(FFLAGS) -c $*.f90
.f90.s:
	$(FC) $(FFLAGS) -c -S $*.f90
.f90.x:
	$(FC) $(FFLAGS) -o $*.x $*.f90 *.o $(LDFLAGS)
.F.L:
	$(FC) $(CPPDEFS) $(FPPFLAGS) $(FFLAGS) -c -listing $*.F
.F.opt:
	$(FC) $(CPPDEFS) $(FPPFLAGS) $(FFLAGS) -c -opt_report_level max -opt_report_phase all -opt_report_file $*.opt $*.F
.F.l:
	$(FC) $(CPPDEFS) $(FPPFLAGS) $(FFLAGS) -c $(LIST) $*.F
.F.T:
	$(FC) $(CPPDEFS) $(FPPFLAGS) $(FFLAGS) -c -cif $*.F
.F.f:
	$(FC) $(CPPDEFS) $(FPPFLAGS) -EP $*.F > $*.f
.F.i:
	$(FC) $(CPPDEFS) $(FPPFLAGS) -P $*.F
.F.o:
	$(FC) $(CPPDEFS) $(FPPFLAGS) $(FFLAGS) -c $*.F
.F.s:
	$(FC) $(CPPDEFS) $(FPPFLAGS) $(FFLAGS) -c -S $*.F
.F.x:
	$(FC) $(CPPDEFS) $(FPPFLAGS) $(FFLAGS) -o $*.x $*.F *.o $(LDFLAGS)
.F90.L:
	$(FC) $(CPPDEFS) $(FPPFLAGS) $(FFLAGS) -c -listing $*.F90
.F90.opt:
	$(FC) $(CPPDEFS) $(FPPFLAGS) $(FFLAGS) -c -opt_report_level max -opt_report_phase all -opt_report_file $*.opt $*.F90
.F90.l:
	$(FC) $(CPPDEFS) $(FPPFLAGS) $(FFLAGS) -c $(LIST) $*.F90
.F90.T:
	$(FC) $(CPPDEFS) $(FPPFLAGS) $(FFLAGS) -c -cif $*.F90
.F90.f90:
	$(FC) $(CPPDEFS) $(FPPFLAGS) -EP $*.F90 > $*.f90
.F90.i90:
	$(FC) $(CPPDEFS) $(FPPFLAGS) -P $*.F90
.F90.o:
	$(FC) $(CPPDEFS) $(FPPFLAGS) $(FFLAGS) -c $*.F90
.F90.s:
	$(FC) $(CPPDEFS) $(FPPFLAGS) $(FFLAGS) -c -S $*.F90
.F90.x:
	$(FC) $(CPPDEFS) $(FPPFLAGS) $(FFLAGS) -o $*.x $*.F90 *.o $(LDFLAGS)