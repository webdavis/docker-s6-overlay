#!/usr/bin/env bash

# Exit immediately if a command fails.
set -eo pipefail

OFFICIAL_IMAGE_METADATA_FILE='official_image_metadata.json'
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
  local s6_architecture_mappings_file="$1"

  declare -A s6_architecture_mappings
  declare -A platform_mappings

  local key s6_overlay_architecture platform
  while IFS="=" read -r key s6_overlay_architecture platform; do
    s6_architecture_mappings["$key"]="$s6_overlay_architecture"
    platform_mappings["$key"]="$platform"
  done < <(jq -r 'to_entries | .[] | "\(.key)=\(.value.s6_architecture)=\(.value.platform)"' "$s6_architecture_mappings_file")

  # Serialize associative arrays to strings that can be evaluated to recreate the array.
  declare -p s6_architecture_mappings
  declare -p platform_mappings
}

parse_command_line_arguments() {
  local short='uh'
  local long='push,help'

  local options
  options="$(getopt -o "$short" --long "$long" -- "$@")"
  eval set -- "$options"

  local push='false'

  while true; do
    case "$1" in
      -u | --push)
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

  echo "$push"
}

process_images() {
  local official_image_metadata_file="$1"
  local s6_architecture_mappings_str="$2"
  local platform_mappings_str="$3"

  # Evaluate the serialized associative arrays to deserialize them.
  eval "$s6_architecture_mappings_str"
  eval "$platform_mappings_str"

  local image image_version architectures arch platform s6_overlay_architecture

  jq -r '
  . as $all |
    keys[] as $image |
    $all[$image][] |
    [ $image, .version, (.architectures | join(" ")) ] |
    @csv' "$official_image_metadata_file" | while IFS=, read -r image image_version architectures; do
      image=$(tr -d '"' <<< "$image")
      image_version=$(tr -d '"' <<< "$image_version")
      for arch in $architectures; do
        arch=$(tr -d '"' <<< "$arch")
        platform=${platform_mappings[$arch]}
        s6_overlay_architecture=${s6_architecture_mappings[$arch]}
        echo "$platform $image $image_version $s6_overlay_architecture"
      done
    done
}

build_images() {
  local official_image_metadata_file="$1"
  local s6_architecture_mappings_str="$2"
  local platform_mappings_str="$3"
  local push="$4"

  local push_option=""
  if [[ $push == 'true' ]]; then
    push_option="--push"
  fi

  process_images \
    "$official_image_metadata_file" \
    "$s6_architecture_mappings_str" \
    "$platform_mappings_str" \
    | parallel --colsep ' ' \
      --group \
      --tagstring 'CORE #{%}﹕{2}-{3}-{4}' \
      ./scripts/build_image.sh -p "{1}" -i "{2}" -v "{3}" -a "{4}" "$push_option"
}

main() {
  cd "$(get_repo_root_directory)" || exit 1

  local mappings
  mappings="$(load_s6_architecture_mappings "$S6_ARCHITECTURE_MAPPINGS_FILE")"
  s6_architecture_mappings_str="$(echo "$mappings" | head -n 1)"
  platform_mappings_str="$(echo "$mappings" | tail -n 1)"

  local push
  push="$(parse_command_line_arguments "$@")"

  build_images "$OFFICIAL_IMAGE_METADATA_FILE" "$s6_architecture_mappings_str" "$platform_mappings_str" "$push"
}

main "$@"
