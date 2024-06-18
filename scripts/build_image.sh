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

The following flags are required:

    -f|--platform <platform>                                The buildx platform being used (passed to --platform)
    -i|--image <image>                                      The name of the official base image
    -v|--image-version <image_version>                      The version of the official base image
    -a|--s6-overlay-architecture <s6_overlay_architecture>  The architecture of the s6 overlay tarball. See s6_architecture_mappings.json

Optional flags:

    -s|--save                                               Save the built docker image as a tarball
    -p|--push                                               Push the built docker image and manifest upstream

Example using short flags:
    ${SCRIPT_NAME} -f linux/amd64 -i alpine -v 3.19 -a x86_64 -s -u

Example using long flags:
    ${SCRIPT_NAME} --platform linux/amd64 --image alpine --image-version 3.19 --s6-overlay-architecture x86_64 --save --push"
}

get_repo_root_directory() {
  git rev-parse --show-toplevel
}

fetch_s6_overlay_version() {
  local s6_overlay_version_file="$1"
  jq -r 'values[]' "$s6_overlay_version_file"
}

verify_script_arguments() {
  local docker_platform="$1"
  local image="$2"
  local image_version="$3"
  local s6_overlay_architecture="$4"

  if [[ -z "$docker_platform" || -z "$image" || -z "$image_version" || -z "$s6_overlay_architecture" ]]; then
    printf "%s\\n" "
${SCRIPT_NAME}: Invalid usage

The following flags are required:

    -f <platform>                (or --platform <platform>)
    -i <image>                   (or --image <image>)
    -v <image_version>           (or --image-version <image_version>)
    -a <s6_overlay_architecture> (or --s6-overlay-architecture <s6_overlay_architecture>)

Example using short flags:
    ${SCRIPT_NAME} -f linux/amd64 -i alpine -v 3.19 -a x86_64

Example using long flags:
    ${SCRIPT_NAME} --platform linux/amd64 --image alpine --image-version 3.19 --s6-overlay-architecture x86_64
" >&2
  exit 1
  fi
}

parse_command_line_arguments() {
  local short='f:i:v:a:suh'
  local long='platform:,image:,image-version:,s6-overlay-architecture:,save,push,help'

  local options
  options="$(getopt -o "$short" --long "$long" -- "$@")"
  eval set -- "$options"

  local docker_platform=""
  local image=""
  local image_version=""
  local s6_overlay_architecture=""

  local save='false'
  local push='false'

  while true; do
    case "$1" in
      -f | --platform)
        docker_platform="$2"
        shift 2
        ;;
      -i | --image)
        image="$2"
        shift 2
        ;;
      -v | --image-version)
        image_version="$2"
        shift 2
        ;;
      -a | --s6-overlay-architecture)
        s6_overlay_architecture="$2"
        shift 2
        ;;
      -s | --save)
        save='true'
        shift 1
        ;;
      -p | --push)
        push='true'
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

  verify_script_arguments "$docker_platform" "$image" "$image_version" "$s6_overlay_architecture"
  echo "$docker_platform" "$image" "$image_version" "$s6_overlay_architecture" "$save" "$push"
}

build_image() {
  local docker_platform="$1"
  local image="$2"
  local image_version="$3"
  local s6_overlay_architecture="$4"
  local s6_overlay_version="$5"
  local image_tag="$6"
  local push="$7"

  local build_cmd=(
    "${DOCKER_CMD}" buildx build \
      --platform "${docker_platform}" \
      --build-arg IMAGE_VERSION="${image_version}" \
      --build-arg S6_OVERLAY_VERSION="${s6_overlay_version}" \
      --build-arg S6_OVERLAY_ARCHITECTURE="${s6_overlay_architecture}" \
      --tag "$image_tag" \
      -f "Dockerfile.$image" .)

  if [[ $push == 'true' ]]; then
    build_cmd+=(--provenance=mode=max --push --attest type=sbom)
  else
    build_cmd+=(--load)
  fi

  "${build_cmd[@]}"
}

save_image() {
  local image_tag="$1"
  local tarball="$2"

  ${DOCKER_CMD} save "$image_tag" -o "$tarball"
  chmod -R 755 "$tarball"
}

main() {
  cd "$(get_repo_root_directory)" || exit 1

  local s6_overlay_version
  s6_overlay_version="$(fetch_s6_overlay_version "$S6_OVERLAY_VERSION_FILE")"

  local docker_platform image image_version s6_overlay_architecture save push
  read -r docker_platform image image_version s6_overlay_architecture save push <<< "$(parse_command_line_arguments "$@")"

  # Image tag example: webdavis/docker-s6-overlay:ubuntu-24.04-aarch64-3.1.6.2
  local image_tag
  image_tag="${REPO_ADDRESS}:${image}-${image_version}-${s6_overlay_architecture}-${s6_overlay_version}"

  build_image "$docker_platform" "$image" "$image_version" "$s6_overlay_architecture" "$s6_overlay_version" "$image_tag" "$push"

  if [[ $save == 'true' ]]; then
    local tarball="${image}_${image_version}_${s6_overlay_architecture}.tar"
    save_image "$image_tag" "$tarball"
  fi
}

main "$@"
