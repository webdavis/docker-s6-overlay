#!/usr/bin/env bash

# Exit immediately if a command fails.
set -eo pipefail

DOCKER_CMD='sudo docker'
REPO_ADDRESS="webdavis/docker-s6-overlay"
S6_OVERLAY_VERSION_FILE='s6_overlay_version.json'
SCRIPT_NAME="${BASH_SOURCE##*/}"

help() {
    printf "%s\\n" "
${SCRIPT_NAME}: Package multi-platform Docker images with s6-overlay

All of the following flags must be specified:

    -p|--platform <platform>                                The buildx platform being used (passed to --platform)
    -i|--image <image>                                      The name of the official base image
    -v|--image-version <image_version>                      The version of the official base image
    -a|--s6-overlay-architecture <s6_overlay_architecture>  The architecture of the s6 overlay tarball. See s6_architecture_mappings.json

Example using short flags:
    ${SCRIPT_NAME} -p linux/amd64 -i alpine -v 3.19 -a 3.1.6.2

Example using long flags:
    ${SCRIPT_NAME} --platform linux/amd64 --image alpine --image-version 3.19 --s6-overlay-architecture 3.1.6.2"
}

verify_script_arguments() {
  if (( $# != 8 )); then
    printf "%s\\n" "
${SCRIPT_NAME}: Invalid usage

You must specify the following flags:

    -p <platform>                (or --platform <platform>)
    -i <image>                   (or --image <image>)
    -v <image_version>           (or --image-version <image_version>)
    -a <s6_overlay_architecture> (or --s6-overlay-architecture <s6_overlay_architecture>)

Example using short flags:
    ${SCRIPT_NAME} -p linux/amd64 -i alpine -v 3.19 -a 3.1.6.2

Example using long flags:
    ${SCRIPT_NAME} --platform linux/amd64 --image alpine --image-version 3.19 --s6-overlay-architecture 3.1.6.2
" >&2
  exit 1
  fi
}

get_repo_root_directory() {
  git rev-parse --show-toplevel
}

load_s6_overlay_version() {
  S6_OVERLAY_VERSION="$(jq -r 'values[]' "$S6_OVERLAY_VERSION_FILE")"
}

parse_command_line_arguments() {
  local short='p:i:v:a:h'
  local long='platform:,image:,image-version:,s6-overlay-architecture:,help'

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
      -h | --help)
        help
        exit 0
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

  verify_script_arguments "$@"
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
