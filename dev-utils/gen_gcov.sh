#!/usr/bin/env bash

# This script generates gcov files for a given MOM6-TURBO experiment run.
# The experiment must be run with an executable built with coverage enabled
# e.g., ./build.sh --compiler gnu --codecov . Doing so will generate the
# necessary .gcno files under the build directory. Running the experiment
# with this executable will generate the .gcda files under the codecov/
# directory of the experiment, e.g., double_gyre/codecov/. After the
# experiment is complete, this script can be run to generate the gcov
# files. You can then run gcovlens to generate html reports.

# Usage: ./gen_gcov.sh <experiment_directory>

if [ $# -ne 1 ]; then
  echo "Usage: $0 <experiment_directory>"
  exit 1
fi

EXPERIMENT_DIR=$1
CODECOV_DIR="${EXPERIMENT_DIR}/codecov"

if [ ! -d "${CODECOV_DIR}" ]; then
  echo ""
  echo "Error: Codecov directory does not exist: ${CODECOV_DIR}"
  echo "       Please make sure to run the experiment with a MOM6 executable "
  echo "       built with coverage enabled: ./build.sh --compiler gnu --codecov"
  echo ""
  exit 1
fi

cd "${CODECOV_DIR}" || {
  echo "Error: Could not change to directory ${CODECOV_DIR}"
  exit 1
}

# Find all .gcda files in the codecov directory
find ./ -name "*.gcda" | while read -r gcda_file_path; do
echo "--------------------------------------"
    gcda_file_name=$(basename "${gcda_file_path}")
    gcda_file_default="${gcda_file_name//\#/\/}" # The default path of gcda if it were not in codecov/
    gcda_file_name_default=$(basename "${gcda_file_default}")  # The default name of the gcda file
    obj_dir="${gcda_file_default%/*}"  # The directory of the object file
    gcno_file_name="${gcda_file_name_default/.gcda/.gcno}"  # The corresponding gcno file name
    gcno_file_path="${obj_dir}/${gcno_file_name}"  # The full path of the corresponding gcno file

    # Copy the gcda file to the object directory (Otherwise gcov reports 0.0 line coverage for some reason)
    cp "${gcda_file_path}" "${obj_dir}/${gcda_file_name_default}"  # Copy the gcda file to the object directory

    # Execute gcov command
    if [ -f "${gcno_file_path}" ]; then
        cmd="gcov -o ${obj_dir} ${gcda_file_name_default}"
        echo "Command: ${cmd}"
        eval "${cmd}"
    else
        echo "WARNING: Corresponding gcno file does not exist: ${gcno_file_path}"
        continue
    fi
done

# Print a message indicating completion
echo "Generated gcov files in ${CODECOV_DIR}."
echo "You can now run gcovlens to generate html reports."
