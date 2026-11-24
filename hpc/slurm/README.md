# Running WAVES on a SLURM cluster

This kit runs the [WAVES pipeline](https://github.com/WAVES-Collaborative/WAVES) as SLURM jobs, without RStudio. We tested it on the Oxford BMRC cluster (Rocky Linux 8.10, x86_64) in November 2026, with WAVES commit `bde0f1d` and R 4.5.3. For questions about this kit, contact Alyona Tsvetkova (University of Oxford). For questions about WAVES itself, use the [WAVES issues](https://github.com/WAVES-Collaborative/WAVES/issues).

## What you need

- A Linux cluster with SLURM.
- The `conda` command, from a cluster module or from your own installation.
- About 20 GB of disk space outside `$HOME`.
- Internet access on the login node and on the compute nodes for steps 1 and 2.

If the compute nodes have no internet access, ask your cluster support where you can run downloads.

## Files

| File | What it does |
|---|---|
| `config.env` | Paths and cluster settings. This is the only file that you edit. |
| `env.sh` | Sets up the environment for each step. The other scripts read it. |
| `00_install.sh` | Makes the conda environment for R and installs Miniforge for the WAVES Python environments. |
| `01_renv_restore.sbatch` | Installs the R packages of WAVES. |
| `02_config.sbatch` | Runs the WAVES configuration pipeline. |
| `03_main.sbatch` | Runs the WAVES main pipeline on your data. |
| `logs/` | The job logs. |

## Before you start

1. Clone this branch: `git clone -b hpc-slurm https://github.com/nihaoalena/WAVES.git`. The kit is in `hpc/slurm/`, and `WAVES_DIR` already points to the clone.
2. In `config.env`, set `WORK_DIR` and `CONDA_MODULE`. Use absolute paths without spaces, because WAVES builds shell commands from these paths.
3. In the WAVES folder, edit `_waves.yml` for your data. The [YAML instructions](https://waves-collaborative.github.io/WAVES/articles/instructions-yaml.html) give each setting.

Submit all jobs from the kit folder (`hpc/slurm/`). To use a different partition or account, add the SLURM options to the command, for example `sbatch -p long -A myaccount 03_main.sbatch`. Options on the command line replace the `#SBATCH` lines in the files.

## Step 0: install R and Miniforge

From the kit folder, run `bash 00_install.sh` on a login node. To run it as a job instead, use this command from the kit folder:

```
sbatch --cpus-per-task=2 --mem=8G --time=01:00:00 --output=logs/%x_%j.out --wrap="bash 00_install.sh"
```

The script downloads and unpacks packages. It installs a pinned Miniforge release (`MINIFORGE_VERSION`) and stops if the SHA-256 checksum of the installer does not match. It took about 2 minutes on our cluster. At the end, it shows the R version and the conda version.

## Step 1: install the R packages

Run `sbatch 01_renv_restore.sbatch`.

The job builds about 210 R packages from source. It took about 1.5 hours on our cluster, with 8 CPUs. The job fails if the installation or the loading of the packages fails. The log in `logs/` then shows `RESTORE_EXIT` or `LOAD_EXIT` with a value that is not 0.

renv reports that the WAVES lockfile uses R 4.6.1. This warning is expected. WAVES works with R 4.4 or later.

## Step 2: run the configuration pipeline

Run `sbatch 02_config.sbatch`.

The job makes the five Python environments (stepcount, accelerometer, actinet and two for Oak). Then it runs all methods on the WAVES test files. It took about 50 minutes on our cluster.

The job fails if `tar_make()` fails or if one or more WAVES targets failed. Some WAVES targets continue after an error, so the job also lists the failed targets at the end of the log. If only the target `pipeline_summary` failed, the HTML report did not build. The environments are then still correct, and you can submit step 3.

## Step 3: run the main pipeline

1. In the WAVES file `_targets.R`, set `trial_run <- TRUE`. The pipeline then uses only the first file.
2. Run `sbatch 03_main.sbatch`.
3. Read the log in `logs/` and the report in the WAVES folder `reports/`. As in step 2, the job fails if a target failed, and the log lists the failed targets.
4. If the trial run is correct, set `trial_run <- FALSE` and run `sbatch 03_main.sbatch` again.

The default in WAVES is `trial_run <- FALSE`. With this value, the pipeline processes all files at once.

## Resources

| Step | CPUs | Memory | Time limit | What we measured |
|---|---|---|---|---|
| 1 | 8 | 16 GB | 4 hours | About 1.5 hours |
| 2 | 4 | 64 GB | 4 hours | About 50 minutes and 20 GB. With 16 GB, SLURM stopped the job (out of memory). |
| 3 | 4 | 64 GB | 24 hours | About 30 minutes and 18 to 22 GB for one 8-day file at 100 Hz |

To get the peak memory of a finished job, run `sacct -j <job id> --format=MaxRSS,Elapsed`. Use this value to set `--mem` for your own data.

## Parallel processing

WAVES processes files in parallel only inside one job. The number of parallel processes is `n_workers` in the WAVES file `_targets.R`. Do not set it higher than the number of CPUs minus one. Each process uses one thread for the math libraries (`env.sh` sets this). WAVES does not divide the work into many SLURM jobs. For a large dataset, request more CPUs and more memory for step 3.

## Known problems and their fixes

The scripts already contain these fixes. The table helps you if you see one of the errors.

| Error or symptom | Cause | Fix in the kit |
|---|---|---|
| The R module on the cluster is older than 4.4. | WAVES needs R 4.4 or later. | `00_install.sh` makes a conda environment with R 4.5 (`R_VERSION`) from conda-forge. |
| `arrow` does not load: `undefined symbol: __libc_single_threaded` | The prebuilt arrow library needs glibc 2.32 or later. RHEL and Rocky 8 have 2.28. | `r-arrow` comes from conda-forge, and step 1 does not install `arrow` again. |
| R packages from Posit Package Manager do not load in conda R. | These binaries link to the libraries of a system R. | `RENV_CONFIG_PPM_ENABLED=FALSE` makes renv build from source. |
| Builds fail with missing ICU or OpenSSL symbols. | The conda module also loads other modules. | `PURGE_MODULES_AFTER_CONDA=1` runs `module purge` after conda is set up. |
| Step 2 stops with `cannot branch over empty target (vct_basic_files)` or `argument 'df_start_tz' is missing`, or the report fails with `parse error: premature EOF`. | Three known bugs on WAVES main (bde0f1d) that stop a fresh install on Linux. | This branch already contains fixes for these bugs. We sent them to WAVES as [pull request #40](https://github.com/WAVES-Collaborative/WAVES/pull/40). |
| Step 1 stops at `RcppParallel` and uses no CPU. | With `MAKEFLAGS=-jN`, the gcc link step waits for make job slots that it never gets. | `01_renv_restore.sbatch` does not set `MAKEFLAGS`. |
| `ft2build.h: No such file or directory` | `pkg-config` gives empty flags for freetype. | `env.sh` adds the freetype headers to `CPATH`. |
| `stepcount: command not found` in step 2 or 3 | reticulate used a different conda (a module or your own Anaconda). The environments went to a different folder. | `env.sh` sets `RETICULATE_CONDA` and `CONDA_ENVS_DIRS`. |
| `pandoc version 1.12.3 or higher is required` | The HTML report needs pandoc. RStudio usually supplies it. | Pandoc is in the R environment, and `env.sh` sets `RSTUDIO_PANDOC`. |
| SLURM stopped step 2 (out of memory). | One test file needs more than 16 GB. | Step 2 requests 64 GB. |

## Disk space

All environments, caches and temporary files go to `WORK_DIR`. This includes the conda packages, the renv cache, the pip cache and the torch model weights. Nothing large goes to `$HOME`.
