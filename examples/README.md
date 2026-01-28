This directory contains example standalone MOM6 experiments for development, testing, and benchmarking purposes. 
To run these experiments:
    1. Build the MOM6 executable using the provided `build.sh` script.
    2. Modify the `job-derecho.sh` script to set your project code and compiler as needed (the default project code is the one assigned to TURBO and the default compiler is intel).
    3. Submit the `job-derecho.sh` script to your job scheduler.
    4. If the job completes successfully, you will find the output files in the example directory.
After the job completes, you can archive the output files using the `Makefile`:
    1. Run `make archive` to create an archive of the output files.
       The archived files will be stored in the `archive/` directory with a timestamp.
    2. You can also clean up output files using `make clean`, which will remove untracked files from the repository.
