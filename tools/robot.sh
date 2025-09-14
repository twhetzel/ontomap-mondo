#!/usr/bin/env bash
# tools/robot.sh — run OBO ROBOT via Docker
# Requires Docker installed locally.
set -euo pipefail
IMAGE="obolibrary/robot:latest"
docker run --rm -v "$PWD":/work -w /work "$IMAGE" robot "$@"