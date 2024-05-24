#!/usr/bin/env bash

# Exit immediately if a command fails.
set -eo pipefail

OFFICIAL_IMAGE_METADATA='official_image_metadata.json'
S6_ARCHITECTURE_MAPPINGS_FILE='s6_architecture_mappings.json'
SCRIPT_NAME="${BASH_SOURCE##*/}"

help() {
    printf "%s\\n" "
${SCRIPT_NAME}: A utility script that executes build_image.sh in parallel

All of the following flags must be specified:

    -u|--push   Push the built docker image upstream

Example using short flags:
    ${SCRIPT_NAME} -u

Example using long flags:
    ${SCRIPT_NAME} --push"
}

get_repo_root_directory() {
  git rev-parse --show-toplevel
}

load_s6_architecture_mappings() {
  declare -gA S6_ARCHITECTURE_MAPPINGS
  declare -gA PLATFORM_MAPPINGS

  while IFS="=" read -r key s6_overlay_architecture platform; do
    S6_ARCHITECTURE_MAPPINGS["$key"]="$s6_overlay_architecture"
    PLATFORM_MAPPINGS["$key"]="$platform"
  done < <(jq -r 'to_entries | .[] | "\(.key)=\(.value.s6_architecture)=\(.value.platform)"' "$S6_ARCHITECTURE_MAPPINGS_FILE")
}

parse_command_line_arguments() {
  local short='uh'
  local long='push,help'

  PUSH='false'

  OPTIONS="$(getopt -o "$short" --long "$long" -- "$@")"
  eval set -- "$OPTIONS"

  while true; do
    case "$1" in
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
}

process_images() {
  jq -r '
  . as $all |
    keys[] as $image |
    $all[$image][] |
    [ $image, .version, (.architectures | join(" ")) ] |
    @csv' "$OFFICIAL_IMAGE_METADATA" | while IFS=, read -r image image_version architectures; do
      image=$(tr -d '"' <<< "$image")
      image_version=$(tr -d '"' <<< "$image_version")
      for arch in $architectures; do
        arch=$(tr -d '"' <<< "$arch")
        platform=${PLATFORM_MAPPINGS[$arch]}
        s6_overlay_architecture=${S6_ARCHITECTURE_MAPPINGS[$arch]}
        echo "$platform $image $image_version $s6_overlay_architecture"
      done
    done
}

build_images_in_parallel() {
  if [[ $PUSH == 'true' ]]; then
    process_images | parallel --colsep ' ' ./scripts/build_image.sh -p "{1}" -i "{2}" -v "{3}" -a "{4}" -u
    return 0
  fi

  process_images | parallel --colsep ' ' ./scripts/build_image.sh -p "{1}" -i "{2}" -v "{3}" -a "{4}"
}

main() {
  cd "$(get_repo_root_directory)" || exit 1
  load_s6_architecture_mappings
  parse_command_line_arguments "$@"
  build_images_in_parallel
}

main "$@"
