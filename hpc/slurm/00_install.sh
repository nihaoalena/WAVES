#!/bin/bash
# Step 0: make the R environment and the Miniforge for the WAVES Python environments.
# Run it from this folder, on a login node or as a small job:
#   bash 00_install.sh
#   sbatch --cpus-per-task=2 --mem=8G --time=01:00:00 --output=logs/%x_%j.out --wrap="bash 00_install.sh"
set -eo pipefail
if [ -f "$(dirname "${BASH_SOURCE[0]}")/env.sh" ]; then
  KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  KIT_DIR="${SLURM_SUBMIT_DIR:?Run this script from this folder}"
fi
source "$KIT_DIR/env.sh"
set -u

# 1. R, build tools and system libraries, from conda-forge only.
#    r-arrow comes from conda-forge because the prebuilt arrow library
#    needs glibc 2.32 or later (RHEL/Rocky 8 has 2.28).
if [ -d "$R_ENV" ] && [ ! -x "$R_ENV/bin/Rscript" ]; then
  echo "$R_ENV exists but has no Rscript. Delete this folder and run step 0 again." >&2
  exit 1
fi
if [ ! -d "$R_ENV" ]; then
  conda create -y -p "$R_ENV" --override-channels -c conda-forge \
    "r-base=$R_VERSION" "r-arrow=$ARROW_VERSION" pandoc \
    compilers make cmake pkg-config libcurl openssl libxml2 libxml2-devel libgit2 \
    harfbuzz fribidi freetype libpng libtiff libjpeg-turbo libwebp fontconfig \
    zlib xz icu gettext zstd glpk gmp rust git curl
fi

# 2. Miniforge for the five WAVES Python environments, conda-forge only.
#    The installer is a pinned release, and its SHA-256 checksum must match.
if [ ! -x "$RETICULATE_MINICONDA_PATH/bin/conda" ]; then
  installer_name="Miniforge3-$MINIFORGE_VERSION-Linux-$(uname -m).sh"
  base_url="https://github.com/conda-forge/miniforge/releases/download/$MINIFORGE_VERSION"
  download_dir="$(mktemp -d "$TMPDIR/miniforge.XXXXXX")"
  trap 'rm -rf "$download_dir"' EXIT
  curl -fsSL -o "$download_dir/$installer_name" "$base_url/$installer_name"
  curl -fsSL -o "$download_dir/$installer_name.sha256" "$base_url/$installer_name.sha256"
  (cd "$download_dir" && sha256sum -c "$installer_name.sha256")
  bash "$download_dir/$installer_name" -b -p "$RETICULATE_MINICONDA_PATH"
fi
printf "channels:\n  - conda-forge\nchannel_priority: strict\n" > "$RETICULATE_MINICONDA_PATH/.condarc"

conda run -p "$R_ENV" R --version | head -1
"$RETICULATE_CONDA" --version
echo "Step 0 done. Next: sbatch 01_renv_restore.sbatch"
