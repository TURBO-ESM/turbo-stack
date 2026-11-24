This directory contains example standalone MOM6 experiments for development, testing, and benchmarking purposes.

To run these experiments:

1. Build the MOM6 executable -- see the [top-level README](../README.md) for the CMake build,
   or [`docs/legacy_build_system.md`](../docs/legacy_build_system.md) for the legacy `build.sh` build.
2. Modify the `job-derecho.sh` script to set your project code, and the `COMPILER` and `INFRA` of the build you want to run, as needed (the default project code is the one assigned to TURBO, the default compiler is intel and the default backend is FMS2).
3. Submit the `job-derecho.sh` script to your job scheduler.
4. If the job completes successfully, you will find the output files in the example directory.

> [!IMPORTANT]
> `job-derecho.sh` runs the executable that `scripts/build_on_derecho.sh --compiler ${COMPILER} --infra ${INFRA}`
> builds, `../../build/${COMPILER}-${INFRA}/mom6_build/config_src/drivers/solo_driver/MOM6`,
> and stops with that command if it isn't there. To run a **legacy** `build.sh` build instead,
> set `MOM6` in the job script to `../../bin/${COMPILER}/MOM6_using_${INFRA}/MOM6/MOM6`.
> `double_gyre/job-gpu.sh` still runs the legacy build.

After the job completes, you can archive the output files using the `Makefile`:

1. Run `make archive` to create an archive of the output files.
   The archived files will be stored in the `archive/` directory with a timestamp.
2. You can also clean up output files using `make clean`, which will remove untracked files from the repository.
