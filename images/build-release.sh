#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "${SCRIPT_DIR}"
source "_versions.source"

if [[ $# -eq 0 ]] ; then
    echo "Syntax: $0 <tag>"
    exit 1
fi

TAG=$1

cd "${SCRIPT_DIR}"
docker build \
 -t "kkos2display/admin-release:${TAG}" \
 -t "kkos2display/admin-release:latest" \
 --no-cache \
 -f admin-release/Dockerfile \
 --build-arg os2display_image_repository="${KKOS_IMAGE_REPOSITORY}" \
 --build-arg revision="${TAG}" \
 --build-arg repository="${ADMIN_REPOSITORY}" \
 admin-release

