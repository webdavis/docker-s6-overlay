#!/usr/bin/env bash

# Exit immediately if a command fails.
set -eo pipefail

DOCKER_CMD='docker'
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
    -s|--save                                               Save the built docker image as a tarball
    -u|--push                                               Push the built docker image and manifest upstream

Example using short flags:
    ${SCRIPT_NAME} -p linux/amd64 -i alpine -v 3.19 -a x86_64 -s -u

Example using long flags:
    ${SCRIPT_NAME} --platform linux/amd64 --image alpine --image-version 3.19 --s6-overlay-architecture x86_64 --save --push"
}

get_repo_root_directory() {
  git rev-parse --show-toplevel
}

load_s6_overlay_version() {
  S6_OVERLAY_VERSION="$(jq -r 'values[]' "$S6_OVERLAY_VERSION_FILE")"
}

verify_script_arguments() {
  if [[ -z "$DOCKER_PLATFORM" || -z "$IMAGE" || -z "$IMAGE_VERSION" || -z "$S6_OVERLAY_ARCHITECTURE" ]]; then
    printf "%s\\n" "
${SCRIPT_NAME}: Invalid usage

You must specify the following flags:

    -p <platform>                (or --platform <platform>)
    -i <image>                   (or --image <image>)
    -v <image_version>           (or --image-version <image_version>)
    -a <s6_overlay_architecture> (or --s6-overlay-architecture <s6_overlay_architecture>)

Example using short flags:
    ${SCRIPT_NAME} -p linux/amd64 -i alpine -v 3.19 -a x86_64

Example using long flags:
    ${SCRIPT_NAME} --platform linux/amd64 --image alpine --image-version 3.19 --s6-overlay-architecture x86_64
" >&2
  exit 1
  fi
}

parse_command_line_arguments() {
  local short='p:i:v:a:such'
  local long='platform:,image:,image-version:,s6-overlay-architecture:,save,push,help'

  SAVE='false'
  PUSH='false'

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
      -s | --save)
        SAVE='true'
        shift 1
        ;;
      -u | --push)
        PUSH='true'
        shift 1
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
        echo "Invalid option: $1" >&2
        exit 1
        ;;
    esac
  done

  verify_script_arguments "$@"
}

build_image() {
  ${DOCKER_CMD} buildx build \
      --load \
      --platform "${DOCKER_PLATFORM}" \
      --build-arg IMAGE_VERSION="${IMAGE_VERSION}" \
      --build-arg S6_OVERLAY_VERSION="${S6_OVERLAY_VERSION}" \
      --build-arg S6_OVERLAY_ARCHITECTURE="${S6_OVERLAY_ARCHITECTURE}" \
      --tag "$IMAGE_TAG" \
      -f "Dockerfile.$IMAGE" .
}

save_image() {
  local tarball="${IMAGE}_${IMAGE_VERSION}_${S6_OVERLAY_ARCHITECTURE}.tar"

  ${DOCKER_CMD} save "$IMAGE_TAG" -o "$tarball"
  chmod -R 755 "$tarball"
}

build_and_push_image() {
  ${DOCKER_CMD} buildx build \
      --provenance=mode=max \
      --push \
      --attest type=sbom \
      --platform "${DOCKER_PLATFORM}" \
      --build-arg IMAGE_VERSION="${IMAGE_VERSION}" \
      --build-arg S6_OVERLAY_VERSION="${S6_OVERLAY_VERSION}" \
      --build-arg S6_OVERLAY_ARCHITECTURE="${S6_OVERLAY_ARCHITECTURE}" \
      --tag "$IMAGE_TAG" \
      -f "Dockerfile.$IMAGE" .
}

push_manifest() {
  ${DOCKER_CMD} manifest create "$IMAGE_TAG" "$IMAGE_TAG"

  IFS="/" read -r os arch variant <<< "$DOCKER_PLATFORM"

  if [[ -n $variant ]]; then
    ${DOCKER_CMD} manifest annotate "$IMAGE_TAG" "$IMAGE_TAG" --os "$os" --arch "$arch" --variant "$variant"
  else
    ${DOCKER_CMD} manifest annotate "$IMAGE_TAG" "$IMAGE_TAG" --os "$os" --arch "$arch"
  fi

  ${DOCKER_CMD} manifest push "$IMAGE_TAG"
}

main() {
  cd "$(get_repo_root_directory)" || exit 1
  load_s6_overlay_version
  parse_command_line_arguments "$@"

  # Image tag example: webdavis/docker-s6-overlay:ubuntu-24.04-aarch64-3.1.6.2
  IMAGE_TAG="${REPO_ADDRESS}:${IMAGE}-${IMAGE_VERSION}-${S6_OVERLAY_ARCHITECTURE}-${S6_OVERLAY_VERSION}"

  if [[ $PUSH == 'true' ]]; then
    build_and_push_image
    # push_manifest
  else
    build_image

    if [[ $SAVE == 'true' ]]; then
      save_image
    fi
  fi
}

main "$@"
