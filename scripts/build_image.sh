#!/usr/bin/env bash

# Exit immediately if a command fails.
set -eo pipefail

DOCKER_CMD='sudo docker'
REPO_ADDRESS="webdavis/docker-s6-overlay"
S6_OVERLAY_VERSION_FILE='s6_overlay_version.json'

get_repo_root_directory() {
  git rev-parse --show-toplevel
}

load_s6_overlay_version() {
  S6_OVERLAY_VERSION="$(jq -r 'values[]' "$S6_OVERLAY_VERSION_FILE")"
}

parse_command_line_arguments() {
  local short='p:i:v:a:'
  local long='platform:,image:,image-version:,s6-overlay-architecture:'

  OPTIONS="$(getopt -o "$short" --long "$long" -- "$@")"
  eval set -- "$OPTIONS"

  while true; do
    case "$1" in
      -p | --platform)
        DOCKER_PLATFORM="$2"
        shift 2
        ;;
      -i | --image)
        IMAGE="$2"
        shift 2
        ;;
      -v | --image-version)
        IMAGE_VERSION="$2"
        shift 2
        ;;
      -a | --s6-overlay-architecture)
        S6_OVERLAY_ARCHITECTURE="$2"
        shift 2
        ;;
      --)
        shift
        break
        ;;
      *)
        echo "Invalid option: $1"
        exit 1
        ;;
    esac
  done
}

build_image() {
  # Image tag example: webdavis/docker-s6-overlay:ubuntu-24.04-aarch64-3.1.6.2
  ${DOCKER_CMD} buildx build \
    --load \
    --platform "${DOCKER_PLATFORM}" \
    --build-arg IMAGE_VERSION="${IMAGE_VERSION}" \
    --build-arg S6_OVERLAY_VERSION="${S6_OVERLAY_VERSION}" \
    --build-arg S6_OVERLAY_ARCHITECTURE="${S6_OVERLAY_ARCHITECTURE}" \
    --tag "${REPO_ADDRESS}:${IMAGE}-${IMAGE_VERSION}-${S6_OVERLAY_ARCHITECTURE}-${S6_OVERLAY_VERSION}" \
    -f "Dockerfile.$IMAGE" .
}

main() {
  cd "$(get_repo_root_directory)" || exit 1
  load_s6_overlay_version
  parse_command_line_arguments "$@"
  build_image
}

main "$@"
