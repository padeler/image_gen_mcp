#!/usr/bin/env bash
# Download a checkpoint into the ComfyUI models volume.
# Runs inside the comfyui container to avoid host permission issues
# (the models/ bind mount is owned by root).
#
# Usage: ./scripts/download_models.sh [url]
# Default: SDXL Base 1.0 (~6.9 GB, fits comfortably on a 12 GB RTX 3060).
set -euo pipefail

URL="${1:-https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors}"

echo "Downloading into comfyui:/root/ComfyUI/models/checkpoints"
echo "URL: ${URL}"
docker compose exec comfyui bash -c \
  "cd /root/ComfyUI/models/checkpoints && wget --continue --content-disposition '${URL}'"
echo "Done. Files present:"
docker compose exec comfyui ls -lh /root/ComfyUI/models/checkpoints
