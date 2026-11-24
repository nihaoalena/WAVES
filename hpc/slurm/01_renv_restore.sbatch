#!/bin/bash
# Step 1: install the R packages of WAVES (renv.lock), built from source.
# Submit from this folder: sbatch 01_renv_restore.sbatch
#SBATCH --job-name=waves-renv
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --output=logs/%x_%j.out
source "$SLURM_SUBMIT_DIR/env.sh" || exit 1
require_r_env || exit 1
set -uo pipefail
# Build 4 packages at a time. Do not set MAKEFLAGS: with -jN, the link step of
# RcppParallel (gcc LTO) waits for make job slots that it never gets.
unset MAKEFLAGS

# arrow is already in the conda R environment (see 00_install.sh).
Rscript -e "options(Ncpus = 4); renv::restore(prompt = FALSE, exclude = 'arrow')"
rc_restore=$?
echo "RESTORE_EXIT=$rc_restore"
Rscript -e "source('packages.R'); cat(R.version.string, '\n')"
rc_load=$?
echo "LOAD_EXIT=$rc_load"
exit $(( rc_restore || rc_load ))
