# Build System Redesign Plan

Tracking the incremental migration from `build.sh` + mkmf to a unified CMake build system.

---

## Current System Overview

Three sequential stages orchestrated by `build.sh`:

1. **Stage 1 — Infrastructure** (`libFMS2.a` or `libTIM.a`): built with mkmf from FMS or TIM submodule
2. **Stage 2 — MOM6 Infra Wrapper** (`libinfra-FMS2.a`): ~15 hardcoded MOM6 framework files, built with mkmf
3. **Stage 3 — MOM6 executable** or **unit tests**: mkmf for the binary, CMake for the tests

---

## Pain Points in the Current System

| Problem | Severity |
|---------|----------|
| 11 near-identical `.mk` template files for compiler flags | Medium |
| Stage 2 uses a hardcoded list of 15 MOM6 source files — silently breaks if MOM6 renames anything | High |
| Stage 3 uses shell globs (`src/{*,*/*}/`) for hundreds of files — fragile | High |
| mkmf auto-discovers Fortran `MODULE`/`USE` deps; CMake needs this replicated correctly | Medium-Hard |
| NCAR module versions are hardcoded in `build.sh` | High |
| Mixed CMake + mkmf + nested Make calls — no consistency | Medium |
| No `CMakeLists.txt` for MARBL — currently just file-included via path glob | Medium |
| No config file — unwieldy CLI args to reproduce a build | Medium |

---

## Migration Effort Estimate

| Phase | Components | Difficulty | Estimated Effort |
|-------|-----------|------------|-----------------|
| 1+2 | Skeleton + compiler flags + presets + infra `find_package` | Medium | 6 hours |
| 3 | MOM6 infra wrapper (`MOM6::infra`) | Medium | 4 hours |
| 4 | MARBL, CVMix, GSW in-tree targets | Medium | 4 hours |
| 5 | MOM6 main executable | Medium-Hard | 8 hours |
| 6 | CI workflow migration | Medium | 4 hours |
| 7 | Validation, docs, retire build.sh | Medium | 6 hours |
| **Total** | | | **~32 hours core + ~15 hours unknown** |

---

## Recommended Strategy

**Incremental, stage-by-stage.** Keep `build.sh` working until each CMake stage is proven in CI.

**Architecture decision:** turbo-stack's CMake build is a **consumer**, not a builder, of external dependencies. All third-party libraries (FMS, AMReX, pFUnit, NetCDF, MPI) are pre-built and found via `find_package()`. The build system only compiles what belongs to this repo: the MOM6 infra wrapper, MOM6 itself, and embedded source packages (MARBL, CVMix, GSW). The user is responsible for configuring the environment (by hand, Lmod, Spack, or a prebuilt container) before invoking CMake — see Responsibility Boundary below.

**Minimum CMake version: 3.24** (matches pFUnit — the most restrictive dependency).

---

## Responsibility Boundary

**CMake's job:** compile turbo-stack's own code with the correct flags for the active compiler.

**Not CMake's job:** setting up the environment before compilation starts. This means:
- Setting `CC`/`CXX`/`FC` to the desired compiler
- Making dependencies findable (i.e. setting `CMAKE_PREFIX_PATH`)

The user is responsible for configuring the environment before invoking CMake. Any of these approaches work:

| Method | Example |
|--------|---------|
| **By hand** | `export FC=mpif90; export CMAKE_PREFIX_PATH=/path/to/fms:/path/to/netcdf` |
| **Lmod / environment modules** | `module load gcc netcdf-mpi fms` |
| **Spack** | `spack env activate turbo_stack` |
| **Prebuilt container** | `docker run --rm ncarcisl/cisldev-...; source /container/config_env.sh` |

If a required dependency is not found, CMake will **fail with a clear error** (`find_package(... REQUIRED)`) — it will not attempt to locate or build missing dependencies itself.

```bash
# Example workflow — environment first, then CMake:
spack env activate turbo_stack
scripts/build_turbo_stack.sh
```

---

## Modern CMake Principles (apply throughout)

1. **No global state** — never use `include_directories()`, `link_libraries()`, or `add_definitions()`; only `target_*()` variants
2. **Namespaced targets everywhere** — all reusable targets use `Namespace::Target` form (e.g. `FMS::fms_r8`, `MOM6::infra`, `Turbo::cesm_share`)
3. **Explicit `PUBLIC`/`PRIVATE`/`INTERFACE`** on every `target_link_libraries()` and `target_include_directories()`
4. **No runtime source globs** — `file(GLOB...)` is forbidden; use explicit `target_sources()` lists to avoid silent breakage when submodules rename files
5. **`BUILD_INTERFACE`/`INSTALL_INTERFACE` generator expressions** for all include paths on installed targets
6. **Per-target Fortran module directories** — set via `set_target_properties(... PROPERTIES Fortran_MODULE_DIRECTORY ...)` on each target; never a shared global directory
7. **`CMakePresets.json`** replaces the 11 `.mk` template files and all CLI flag combinations
8. **Build types** (`Release`, `Debug`, `Coverage`) drive optimization/debug flags via `CMAKE_BUILD_TYPE`; no custom flags outside of presets or `TurboCompilerFlags.cmake`

### Dependency strategy

| Dependency | How obtained | How consumed in CMake | Notes |
|------------|-------------|----------------------|-------|
| FMS | User-configured environment | `find_package(FMS REQUIRED)` → `FMS::fms_r8` | Has `FMSConfig.cmake` ✅ |
| AMReX | User-configured environment | `find_package(AMReX REQUIRED COMPONENTS FORTRAN)` → `AMReX::amrex` | Has `AMReXConfig.cmake` ✅ |
| pFUnit | User-configured environment | `find_package(PFUNIT REQUIRED)` → `PFUNIT::pfunit` | Has `PFUNITConfig.cmake` ✅ |
| NetCDF | User-configured environment | `find_package(NetCDF REQUIRED COMPONENTS Fortran)` → `NetCDF::NetCDF_Fortran` | |
| MPI | User-configured environment | `find_package(MPI REQUIRED)` → `MPI::MPI_Fortran` | |
| TIM | **Built in-tree** (submodule) | `add_subdirectory(submodules/infra/TIM tim_build)`; exports `FMS::fms_r8` — same alias as Spack FMS | Phase 6 |
| CESM_share | Not needed (not used by MOM6 solo driver) | — | Investigated; only needed by mkmf TIM build |
| CVMix | **Built in-tree** (MOM6 repo `pkg/`) | Static lib target `MOM6::CVMix` | Built inline in `MOM6/pkg/CMakeLists.txt` |
| MARBL | **Built in turbo-stack** (`marbl_build/`) | Static lib target `MOM6::MARBL` | turbo-stack owns and builds it; MOM6 repo consumes it as a pre-defined target — same pattern as `FMS::fms_r8` |
| GSW | **Built in-tree** (MOM6 repo `pkg/`) | Static lib target `MOM6::GSW` | Built inline in `MOM6/pkg/CMakeLists.txt` |

`CMAKE_PREFIX_PATH` must be set before invoking CMake — by hand, via Lmod modules, Spack, or a prebuilt container. turbo-stack's CMake never sets it directly.

---

## Migration Phases

### Phase 1+2 — Skeleton + Compiler Flags + Infrastructure [✅ COMPLETE]

**Implementation steps:**
1. ✅ Bare skeleton — `cmake_minimum_required` + `project()`, verify configures
2. ✅ Add `find_package` calls — MPI, FMS, NetCDF, pFUnit; verify each resolves with Spack active
3. ✅ Add `cmake/TurboOptions.cmake` — all `option()` / cache variable declarations
4. ✅ Add `cmake/TurboCompilerFlags.cmake` — `CMAKE_Fortran_COMPILER_ID`-based flag logic

**Files created:**
- `CMakeLists.txt` (repo root)
- `cmake/TurboOptions.cmake`
- `cmake/TurboCompilerFlags.cmake`

**Key notes:**
- Spack FMS must be built with `precision=64` to provide `FMS::fms_r8`; `spack.yaml` updated accordingly
- FMS ships its own `FindNetCDF.cmake` in `lib/cmake/fms/` — used via `list(APPEND CMAKE_MODULE_PATH)`
- `TURBO_OFFLOAD` dropped — no OpenMP GPU offload directives exist in MOM6 code
- Unknown compiler is a `FATAL_ERROR` (not a warning) — fail loudly rather than build with wrong flags

---

### Phase 3 — MOM6 Infrastructure Wrapper [🔄 IN PROGRESS] ← NEXT

Replace Stage 2 of `build.sh`. Shadow build tree at `mom6_build/` mirrors MOM6 source tree structure.

**Completed:**
- ✅ `mom6_build/` shadow tree: `src/framework/`, `config_src/infra/` with intermediate `CMakeLists.txt` at each level
- ✅ `mom6_framework_base` (`MOM6::framework_base`) — leaf utilities with no project deps: `MOM_string_functions`, `MOM_array_transform`, `MOM_intrinsic_functions`, `MOM_murmur_hash`, `MOM_safe_alloc`, `posix`, `numerical_testing_type`
- ✅ `mom6_infra` (`MOM6::infra`) — all 12 `config_src/infra/FMS2/` files (excluding `MOM_interp_infra.F90` which needs `MOM_io`); links `FMS::fms_r8`, `MPI::MPI_Fortran`, `NetCDF::NetCDF_Fortran`, `MOM6::framework_base`
- ✅ `mom6_framework` (`MOM6::framework`) — higher-level framework files that depend on infra; currently contains `MOM_error_handler`
- ✅ All three targets build cleanly via `scripts/build.sh`

**Key design note — why three layers:**
`mom6_infra` needs string utilities from `src/framework/`, but higher-level framework files need `mom6_infra`. Split avoids circular dependency:
`mom6_framework_base` → `mom6_infra` → `mom6_framework`

**Completed:**
- ✅ `mom6_framework` (18 files, Tiers A-E), `mom6_grid` (`MOM_grid`, `MOM_verticalGrid`),
  `mom6_io` (`MOM_io`, `MOM_interp_infra`, `MOM_get_input`, `MOM_write_cputime`,
  `MOM_interpolate`, `MOM_restart`)
- ✅ `config_src/infra/FMS2/` 100% complete (13/13 files)
- ✅ `src/framework/` 30/33 files built

**Deferred to Phase 5 (need deep `src/` deps not yet built):**
- [ ] `MOM_diag_mediator` -- needs `MOM_EOS`, `MOM_interface_heights`, `MOM_variables`
- [ ] `MOM_diag_remap` -- needs `MOM_EOS`, `MOM_regridding`, `MOM_remapping`, `coord_*` modules
- [ ] `MOM_horizontal_regridding` -- needs `MOM_debugging` (in `src/diagnostics/`)

---

### Phase 3.5 — Wire Unit Tests [✅ COMPLETE]

- ✅ `add_subdirectory(tests)` in root `CMakeLists.txt`, gated on `TURBO_BUILD_UNIT_TESTS`
- ✅ Tests use `FMS::fms_r8` and `MOM6::infra` directly (no `find_mom_dependencies.cmake`)
- ✅ 40/40 tests pass via `ctest`

---

### Phase 4a — CVMix and GSW Targets [✅ COMPLETE]

Both live in `submodules/MOM6/pkg/` — vendored inside the MOM6 submodule.

- ✅ Shadow tree mirrors `submodules/MOM6/pkg/`: `mom6_build/pkg/CVMix-src/src/shared/` and `mom6_build/pkg/GSW-Fortran/modules/`
- ✅ `MOM6::CVMix` — 10 `.F90` files, no external deps
- ✅ `MOM6::GSW` — 11 `.f90` files; `gsw_mod_netcdf.f90` links `NetCDF::NetCDF_Fortran` + `NetCDF::NetCDF_C` (C lib needed explicitly because `nf-config --flibs` omits its `-L` path)
- ✅ `cvmix_gsw_link_test` in `mom6_build/pkg/` links both and passes

---

### Phase 4b — MARBL and Other In-Tree Submodules [✅ COMPLETE]

- ✅ `marbl_build/` shadow tree mirrors `submodules/MARBL/`: `marbl_build/CMakeLists.txt` + `marbl_build/src/CMakeLists.txt`
- ✅ `MOM6::MARBL` — all 34 `.F90` files in `submodules/MARBL/src/`; no external deps (perf_mod only used under `#if MARBL_TIMING_OPT == CIME`, which we don't define)
- ✅ CMake Fortran dependency scanner handles internal module ordering automatically
- ✅ 40/40 tests still pass

---

### Phase 5 — MOM6 Main Executable [✅ COMPLETE]

**Shadow tree structure:**
- `mom6_build/src/` — `mom6_ocean` static library (all remaining src/ + external stubs + 3 deferred framework files), defined in parent then populated via `target_sources()` from subdirectories
- `mom6_build/exec/` — `MOM6` executable (solo_driver files only), links `MOM6::ocean`

**Targets created:**
- ✅ `mom6_ocean` / `MOM6::ocean` — 241 src/ files (ALE, core, diagnostics, EOS, ice_shelf, initialization, ODA, parameterizations, tracer, user) + 3 deferred framework files + 14 external stubs; no circular dep issues — CMake Fortran dyndep scanner handled ordering automatically
- ✅ `MOM6` executable — 5 solo_driver files, links `MOM6::ocean`
- ✅ `double_gyre` 10-day run completes cleanly; reference output saved at `examples/double_gyre/ocean.stats.cmake_reference`

**Key discoveries during build:**
- `config_src/external/ODA_hooks/kdtree.f90` is a lowercase `.f90` file not matched by a `*.F90` glob — must be listed explicitly
- `MOM6::GSW` needed the `toolbox/` subdirectory (179 files) in addition to `modules/` (11 files); the toolbox files provide the actual GSW implementations called by `MOM_EOS_TEOS10` and `MOM_TFreeze`
- mkmf reference build was not feasible (builds FMS from source vs Spack FMS; different versions mean non-identical output); CMake first-run output used as baseline instead

**Why no bit-for-bit mkmf comparison:**
The old `build.sh` builds FMS2 from source while our CMake build uses Spack FMS 2025.3.0. Different FMS versions would produce non-identical output independent of flag differences, making the comparison meaningless. The CMake baseline run is the reference going forward.

---

### Phase 6 — TIM CMake Build [✅ COMPLETE]

Add a CMake build for TIM (TURBO Infrastructure for MOM6) so it is hot-swappable with the Spack-installed FMS2.
Both paths export the same `FMS::fms_r8` target; nothing downstream of `mom6_infra` needs to change.

**Completed:**
- ✅ `amrex +fortran` added to `spack/spack.yaml` (AMReX Fortran API required by `array_mod.F90`)
- ✅ TIM modifications live in standalone `/home/lalo/projects/turbo/TIM/` (not the submodule):
  - `find_package(AMReX REQUIRED)` + `tim` C++ static lib + `tim_coms_infra_interface.F90` already added
  - `tim_r8` now links `PUBLIC NetCDF::NetCDF_C NetCDF::NetCDF_Fortran` (mirrors FMS install; fixes bare `-lnetcdf` from nf-config)
  - `MOM_coms_helpers.F90` (TIM-only infra file) added conditionally in `mom6_build/config_src/infra/CMakeLists.txt`
- ✅ Root `CMakeLists.txt`: `TURBO_INFRA=FMS2|TIM` branch — TIM path reads `$TIM_ROOT` env var (or `-DTIM_SOURCE_DIR=`), creates `FMS::fms_r8 ALIAS tim_r8`
- ✅ `scripts/build.sh` and `scripts/build_turbo_stack.sh` accept `--infra FMS2|TIM`
- ✅ `TIM_ROOT=/home/lalo/projects/turbo/TIM` added to `~/.bashrc`
- ✅ FMS2 build: 40/40 tests pass
- ✅ TIM build: 40/40 tests pass

**`double_gyre` with TIM:** ✅ bit-for-bit identical to cmake reference (`ocean.stats.cmake_reference`) — same as FMS2.

**Key design note — hot-swap mechanism:**
TIM exports `TIM::tim_r8`; root `CMakeLists.txt` aliases it to `FMS::fms_r8`.
Everything downstream (`mom6_infra`, `mom6_ocean`, `MOM6` executable, tests) is infra-agnostic.

**Key discovery — NetCDF::NetCDF_C must be PUBLIC on tim_r8:**
`nf-config --flibs` embeds bare `-lnetcdf` without the netcdf-C library search path.
Spack's `FMS::fms_r8` lists `NetCDF::NetCDF_C` explicitly in its `INTERFACE_LINK_LIBRARIES` (see `fms-targets.cmake`),
so the full-path libnetcdf.so appears in downstream link commands. TIM's `tim_r8` must do the same.

---

### Phase 7 — Migrate MOM6 CMake Build into Standalone MOM6 Repo [✅ COMPLETE]

Move the CMake build system from turbo-stack's `mom6_build/` shadow tree into the
standalone MOM6 repository (`../MOM6`, branch `192-feature-cmake-build-system-for-MOM6`,
based on `dev/turbo`). turbo-stack consumes MOM6 via `add_subdirectory` pointed at
that repo.

**Why:** The CMakeLists.txt files logically belong in the MOM6 repository. Moving them
upstream makes the MOM6 repo self-contained and lets other consumers use it directly.
Files placed directly inside the source directories they describe eliminate the artificial
path-variable indirection that the shadow tree required.

**Completed:**

- ✅ Root `MOM6/CMakeLists.txt` — sets `MOM6_SOURCE_DIR`, includes `MOM6Options.cmake`,
  calls `add_subdirectory(pkg)`, `add_subdirectory(src)`, `add_subdirectory(config_src)`
- ✅ `cmake/MOM6Options.cmake` — `TURBO_INFRA` and `TURBO_MEMORY_MODE` cache variables
- ✅ `pkg/CMakeLists.txt` — `MOM6::CVMix` and `MOM6::GSW` built inline (no nested shadow
  subdirs); `pkg/CVMix-src` and `pkg/GSW-Fortran` submodules initialized
- ✅ All `src/*/CMakeLists.txt` — bare filenames throughout (no path variables needed
  since each file lives next to its sources); `parameterizations/` uses relative subdir
  paths (`lateral/`, `vertical/`, `stochastic/`)
- ✅ `src/framework/CMakeLists.txt` — five-layer stack (`framework_base` → `infra` →
  `framework` → `grid` → `io`); only cross-tree reference is
  `${MOM6_SOURCE_DIR}/config_src/infra/${TURBO_INFRA}/MOM_interp_infra.F90` in `mom6_io`
- ✅ `config_src/infra/CMakeLists.txt` — `mom6_infra` uses `${TURBO_INFRA}/filename.F90`
  relative paths; TIM-only `MOM_coms_helpers.F90` still conditional
- ✅ `config_src/drivers/solo_driver/CMakeLists.txt` — `MOM6` executable (replaces
  turbo-stack's `mom6_build/exec/`)
- ✅ turbo-stack `CMakeLists.txt` updated:
  - `MOM6_SOURCE_DIR` cache variable reads `$MOM6_ROOT` (fails loudly if unset)
  - `add_subdirectory(marbl_build)` runs **before** MOM6 so `MOM6::MARBL` is defined
  - `add_subdirectory("${MOM6_SOURCE_DIR}" mom6_build)` replaces `add_subdirectory(mom6_build)`
- ✅ `MOM6_ROOT=/home/lalo/projects/turbo/MOM6` added to `~/.bashrc`
- ✅ `mom6_build/` shadow tree removed from turbo-stack
- ✅ 40/40 tests pass; `MOM6` executable builds cleanly

**MARBL placement — Option B (turbo-stack owns it):**
MARBL is biogeochemistry infrastructure specific to the TURBO project. Rather than
adding it as a submodule inside the MOM6 repo, turbo-stack builds it in `marbl_build/`
and exposes it as a pre-defined `MOM6::MARBL` target before calling `add_subdirectory`
on the MOM6 repo — the same pattern used for `FMS::fms_r8`. The MOM6 repo's
`pkg/CMakeLists.txt` documents this with a comment; MOM6's `.gitignore` already excludes
`pkg/MARBL`.

**Submodule vs local path:** Currently using `MOM6_ROOT=../MOM6` (local clone on the
feature branch). Once the MOM6 PR is merged to `dev/turbo`, update the turbo-stack
submodule (`submodules/MOM6`) to that commit and switch to
`add_subdirectory(submodules/MOM6 mom6_build)`.

---

### Phase 8 — CI Workflow Migration [ ] ← NEXT

Update `.github/workflows/` to invoke CMake instead of the legacy `build.sh` (mkmf-era).

- [ ] Update `build-tests.yaml` — replace `./build.sh --infra TIM/FMS2` with `scripts/build_turbo_stack.sh --infra TIM/FMS2`
- [ ] Update `unit-tests.yaml` — replace `./build.sh --unit-tests-only` with CMake+ctest invocation
- [ ] Update `matrix-compiler-smoketest.yaml` — full compiler matrix (nvhpc, oneapi, gcc14, clang × openmpi, mpich) using CMake; update `double_gyre` executable path
- [ ] Confirm code coverage still works (`TURBO_CODECOV=ON`)
- [ ] Keep the mkmf build path functional until all workflows pass

---

### Phase 9 — Validate, Document, Retire build.sh [ ]

- [ ] All CI workflows passing with CMake
- [ ] `double_gyre` and `benchmark` examples produce matching output
- [ ] All 40 unit tests pass
- [ ] Update `README.md` build instructions
- [ ] Archive or remove `build-utils/makefile-templates/`
- [ ] Archive or remove `build-utils/mkmf/`

---

### Phase 10 — CMakePresets.json (Optional) [ ]

Add when managing multiple environments becomes necessary (CI matrix, NCAR, containers). Not needed for local single-environment development.

- [ ] Create `CMakePresets.json` with inheritance-based structure: hidden base presets (`base`, `infra-fms2`, `infra-tim`, `build-unittests`, `build-mom6`, `type-release`, `type-debug`) composed into concrete presets
- [ ] Add `--preset` support to `scripts/build_turbo_stack.sh`
- [ ] One concrete preset per CI matrix entry; compiler detected from environment — no version hardcoded in preset
- [ ] Update CI workflows to use `cmake --preset ${{ matrix.preset }}`

---

## Key Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| CMake Fortran module dep ordering breaks MOM6 build | Medium | Test early in Phase 5; validate with small subset first |
| Numerical output differs between mkmf and CMake builds (compiler flag mismatch) | Medium | Run `double_gyre`, diff output against reference |
| MARBL internal module structure is complex | Low-Medium | Investigate before Phase 4; may need its own `CMakeLists.txt` |
| NCAR module system incompatible with CMake toolchain approach | Low | Keep `build.sh` wrapper for NCAR env setup if needed |
| `find_package(FMS)` path not set correctly in a new environment | Medium | `CMAKE_PREFIX_PATH` must be set by the environment (Spack/modules) before invoking CMake; `find_package(... REQUIRED)` will fail loudly if not set |
| No `FindNetCDF.cmake` in stock CMake | Medium | Check for one bundled with FMS install; otherwise add `cmake/FindNetCDF.cmake` to this repo |
| TIM doesn't install a CMake config file | Medium | In-tree `add_subdirectory` is the interim solution; open upstream TIM issue to add install config |

---

## Progress Log

| Phase | Notes |
|-------|-------|
| Analysis | Initial analysis complete; plan written |
| Plan | Updated with modern CMake specifics: submodule readiness table, target naming convention, no-glob rule, per-target Fortran module dirs, CMakePresets.json merged into Phase 1, phases condensed from 9 to 7 |
| Strategy | Adopted "consumer not builder" approach: FMS, AMReX, pFUnit, NetCDF, MPI found via `find_package()` from Spack/container installs; only CESM_share (2 files) and TIM (no install config yet) built in-tree |
| Plan | Made plan self-consistent: updated effort table to match 7-phase structure, merged phases 1+2 (unit tests depend on infra), added NetCDF find module note, added TIM upstream issue task, added CLAUDE.md/README update to Phase 7 |
| Env | Spack environment `turbo_stack` created; `spack.yaml` updated with `fms precision=64` to provide `FMS::fms_r8`; `create_spack_environment.sh` written with proper error handling |
| Phase 1+2 | Starting implementation; broken into 6 incremental steps (see above); on step 1 |
| Phase 1+2 | Steps 1+2 complete: `CMakeLists.txt` skeleton + all `find_package()` calls verified with `turbo_stack` Spack env active |
| Tooling | `scripts/build.sh` (Spack wrapper) and `scripts/build_turbo_stack.sh` (CMake orchestrator) written; design decisions: `--debug` flag for clean rebuild; `TURBO_STACK_ROOT` validated in build script; bash script validates `SPACK_ROOT`; `--preset` deferred to Phase 8 |
| Phase 1+2 | Steps 3+4 complete: `cmake/TurboOptions.cmake` and `cmake/TurboCompilerFlags.cmake` added; `TURBO_OFFLOAD` dropped (no GPU offload in MOM6 code); unknown compiler is `FATAL_ERROR` |
| Plan | Reordered phases: unit test wiring (Phase 3.5) moved after Phase 3 since tests require `MOM6::infra`; `CMakePresets.json` moved to optional Phase 8 |
| Phase 3 | Shadow build tree `mom6_build/` established; `mom6_framework_base`, `mom6_infra`, `mom6_framework` (MOM_error_handler) all build; circular dependency resolved by three-layer split |
| Phase 3 | Five-layer stack complete: `mom6_framework_base` -> `mom6_infra` -> `mom6_framework` -> `mom6_grid` -> `mom6_io`; infra 100%, framework 30/33 (3 deferred to Phase 5 pending deep src/ deps) |
| Phase 3.5 | Unit tests wired; `find_mom_dependencies.cmake` replaced by direct target refs; 40/40 tests pass |
| Phase 4a | `MOM6::CVMix` and `MOM6::GSW` built; shadow tree mirrors `submodules/MOM6/pkg/`; `dep_link_test` passes; 40/40 tests still pass |
| Phase 4b | `MOM6::MARBL` built; `marbl_build/` shadow tree mirrors `submodules/MARBL/`; all 34 files compile; 40/40 tests still pass |
| Merge | Merged main → branch; MOM6 updated (added `MOM_string_infra.F90` to `mom6_infra`); FMS/TIM submodules relocated to `submodules/infra/`; pFUnit updated to v4.18 |
| Phase 5 | `MOM6::ocean` + `MOM6` executable built; `double_gyre` 10-day run completes; reference output saved; GSW toolbox (179 files) and ODA kdtree.f90 discovered and added |
| Review | Full CMakeLists review: removed `TURBO_BUILD_MOM6` (unused option), gated `find_package(PFUNIT)` on `TURBO_BUILD_UNIT_TESTS`, reverted mom6_ocean PUBLIC→PRIVATE (PRIVATE breaks static lib propagation), added `Fortran_MODULE_DIRECTORY` to exec, removed `cvmix_gsw_link_test`, fixed compiler flags genex, cleaned stale comments |
| Phase 6 | TIM CMake build complete: TURBO_INFRA=FMS2|TIM hot-swap wired; amrex +fortran in spack.yaml; TIM_ROOT env var; NetCDF::NetCDF_C PUBLIC on tim_r8; 40/40 tests pass with both backends |
| Phase 7 | CMakeLists.txt hierarchy added directly to MOM6 repo (branch `192-feature-cmake-build-system-for-MOM6`); files use bare filenames since they live next to their sources; CVMix/GSW submodules initialized; MARBL stays in turbo-stack as Option B (pre-defined `MOM6::MARBL` target); `mom6_build/` shadow tree removed from turbo-stack; MOM6_ROOT env var wired; 40/40 tests pass |
