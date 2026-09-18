This directory contains example standalone MOM6 experiments for development, testing, and benchmarking purposes.

To run these experiments:

1. Build the MOM6 executable -- see the [top-level README](../README.md) for the CMake build,
   or [`docs/legacy_build_system.md`](../docs/legacy_build_system.md) for the legacy `build.sh` build.
2. Modify the `job-derecho.sh` script to set your project code and compiler as needed (the default project code is the one assigned to TURBO and the default compiler is intel).
3. Submit the `job-derecho.sh` script to your job scheduler.
4. If the job completes successfully, you will find the output files in the example directory.

> [!IMPORTANT]
> The `job-*.sh` scripts run the **legacy** build's executable,
> `../../bin/${COMPILER}/MOM6_using_${INFRA}/MOM6/MOM6`, which a CMake build does
> not produce. To submit a CMake build, edit that path in the job script to the
> CMake executable, e.g.
> `../../build/default/mom6_build/config_src/drivers/solo_driver/MOM6`.

After the job completes, you can archive the output files using the `Makefile`:

1. Run `make archive` to create an archive of the output files.
   The archived files will be stored in the `archive/` directory with a timestamp.
2. You can also clean up output files using `make clean`, which will remove untracked files from the repository.
