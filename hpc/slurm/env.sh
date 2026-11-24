# Environment for every WAVES step. Source it, do not run it:
#   source env.sh
# Each failed setup step stops with `return 1`, because `set -e` does not
# apply inside a file that is sourced with `source env.sh || exit 1`.
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$KIT_DIR/config.env" || return 1

for dir_value in "$WAVES_DIR" "$WORK_DIR"; do
  case "$dir_value" in
    ""|*/path/to/*) echo "Edit WAVES_DIR and WORK_DIR in $KIT_DIR/config.env first." >&2; return 1 ;;
    *[[:space:]]*) echo "Paths in config.env must not contain spaces: $dir_value" >&2; return 1 ;;
    /*) ;;
    *) echo "Paths in config.env must be absolute: $dir_value" >&2; return 1 ;;
  esac
done

# conda: from a module if given, then the shell functions from its base folder.
# Sourcing conda.sh again after `module purge` keeps conda when the purge
# removes the variables that the module set.
if [ -n "$CONDA_MODULE" ]; then
  command -v module >/dev/null || { echo "CONDA_MODULE is set, but the module command is not available." >&2; return 1; }
  module load "$CONDA_MODULE" || return 1
fi
command -v conda >/dev/null || { echo "conda not found. Set CONDA_MODULE in config.env." >&2; return 1; }
CONDA_BASE="$(conda info --base)" || return 1
if [ "$PURGE_MODULES_AFTER_CONDA" = "1" ] && command -v module >/dev/null; then module purge; fi
source "$CONDA_BASE/etc/profile.d/conda.sh" || return 1

# Everything large lives under WORK_DIR, not $HOME.
export CONDA_PKGS_DIRS="$WORK_DIR/conda-pkgs"
export TMPDIR="$WORK_DIR/tmp"
export XDG_CACHE_HOME="$WORK_DIR/cache"
export PIP_CACHE_DIR="$WORK_DIR/cache/pip"
export TORCH_HOME="$WORK_DIR/cache/torch"
export R_USER_CACHE_DIR="$WORK_DIR/cache/R"
export R_LIBS_USER="$WORK_DIR/R-libs-user"
export CARGO_HOME="$WORK_DIR/cargo"
mkdir -p "$CONDA_PKGS_DIRS" "$TMPDIR" "$PIP_CACHE_DIR" "$TORCH_HOME" "$R_USER_CACHE_DIR" "$R_LIBS_USER" "$CARGO_HOME" || return 1

# R comes from its own conda environment (made by 00_install.sh).
R_ENV="$WORK_DIR/conda-envs/waves-r"
if [ -d "$R_ENV" ]; then conda activate "$R_ENV" || return 1; fi

# Steps 1 to 3 call this to make sure that step 0 completed.
require_r_env() {
  if [ ! -x "$R_ENV/bin/Rscript" ]; then
    echo "The R environment is missing or incomplete: $R_ENV. Run 00_install.sh first." >&2
    return 1
  fi
}

# renv: keep the library and cache under WORK_DIR.
export RENV_PATHS_ROOT="$WORK_DIR/renv"
# Prebuilt Linux binaries from Posit Package Manager link against a system R
# and do not load in conda R, so renv builds packages from source.
export RENV_CONFIG_PPM_ENABLED=FALSE
# The renv sandbox hides R packages installed by conda (r-arrow).
export RENV_CONFIG_SANDBOX_ENABLED=FALSE
export NOT_CRAN=true
export DOWNLOAD_STATIC_LIBV8=1
if [ -n "${CONDA_PREFIX:-}" ]; then
  # pkg-config can give empty flags for freetype inside renv builds.
  export CPATH="$CONDA_PREFIX/include/freetype2:$CONDA_PREFIX/include${CPATH:+:$CPATH}"
  # rmarkdown finds pandoc here when it is not on its search path.
  export RSTUDIO_PANDOC="$CONDA_PREFIX/bin"
fi

# Python environments for WAVES come from a separate conda-forge Miniforge.
# Point reticulate at that conda, not at a cluster module or a personal Anaconda.
export RETICULATE_MINICONDA_PATH="$WORK_DIR/waves-miniforge"
export RETICULATE_CONDA="$RETICULATE_MINICONDA_PATH/bin/conda"
export CONDA_ENVS_DIRS="$RETICULATE_MINICONDA_PATH/envs"
unset CONDA_ENVS_PATH

# One thread per process for the math libraries. WAVES runs n_workers
# processes at the same time, each in its own process.
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1

cd "$WAVES_DIR" || { echo "WAVES_DIR not found: $WAVES_DIR" >&2; return 1; }
