#!/bin/bash
# Step 3: WAVES main pipeline on your data (set in WAVES _waves.yml).
# Submit from the kit folder: sbatch 03_main.sbatch
# After the job, get the peak memory with: sacct -j <job id> --format=MaxRSS,Elapsed
#SBATCH --job-name=waves-main
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=logs/%x_%j.out
source "$SLURM_SUBMIT_DIR/env.sh" || exit 1
require_r_env || exit 1
export TAR_PROJECT=main

Rscript -e "targets::tar_make()"
rc_make=$?
# Some WAVES targets continue after an error, so list the failed targets too.
Rscript -e "m <- targets::tar_meta(fields = error, complete_only = TRUE); if (nrow(m) > 0) { cat('Failed targets:\n'); cat(paste0('  ', m\$name, ': ', substr(m\$error, 1, 300)), sep = '\n'); quit(status = 1) }"
rc_targets=$?
echo "MAKE_EXIT=$rc_make FAILED_TARGETS_EXIT=$rc_targets"
exit $(( rc_make || rc_targets ))
