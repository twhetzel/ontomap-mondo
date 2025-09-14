#!/usr/bin/env bash
# tools/robot_local.sh — run OBO ROBOT via local Java (OpenJDK 17 in the conda env)
# If robot.jar is not present, this will download it from GitHub releases.
set -euo pipefail
VERSION="${ROBOT_VERSION:-v1.9.7}"
JAR="tools/robot.jar"
if [[ ! -f "$JAR" ]]; then
  echo "Downloading ROBOT ${VERSION}..."
  curl -L -o "$JAR" "https://github.com/ontodev/robot/releases/download/${VERSION}/robot.jar"
fi
exec java -Xmx4G -jar "$JAR" "$@"