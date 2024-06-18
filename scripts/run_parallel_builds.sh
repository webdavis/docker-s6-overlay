#!/usr/bin/env bash

# Exit immediately if a command fails.
set -eo pipefail

OFFICIAL_IMAGE_METADATA_FILE='official_image_metadata.json'
S6_ARCHITECTURE_MAPPINGS_FILE='s6_architecture_mappings.json'
SCRIPT_NAME="${BASH_SOURCE##*/}"

# Global arrays to track build jobs and a temporary file to track successful jobs.
declare -a BUILD_JOBS

help() {
  printf "%s\\n" "
${SCRIPT_NAME}: A utility script that executes build_image.sh in parallel

All of the following flags must be specified:

    -p|--push   Push the built docker image upstream
    -u|--update Update out of date images (checks against the baseimage's lastest SHA)

Example using short flags:
    ${SCRIPT_NAME} -p

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
  local short='puh'
  local long='push,update,help'

  local options
  options="$(getopt -o "$short" --long "$long" -- "$@")"
  eval set -- "$options"

  local push='false'
  local update='false'

  while true; do
    case "$1" in
      -p | --push)
        push='true'
        shift 1
        ;;
      -u | --update)
        update='true'
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

  echo "$push $update"
}

get_latest_digest_from_registry() {
  local image="$1"
  local image_version="$2"
  curl -s "https://hub.docker.com/v2/repositories/library/${image}/tags/${image_version}/" \
    | jq -r '.images[0].digest'
}

update_digest() {
  local image="$1"
  local image_version="$2"
  local new_sha_value="$3"

  jq \
    --arg image "$image" \
    --arg image_version "$image_version" \
    --arg new_sha_value "$new_sha_value" \
    ' (.[$image][] | select(.version == $image_version) | .latest_local_digest) = $new_sha_value ' \
    official_image_metadata.json > tmp.json && mv tmp.json official_image_metadata.json
}

queue_build_jobs() {
  local official_image_metadata_file="$1"
  local s6_architecture_mappings_str="$2"
  local platform_mappings_str="$3"
  local update="$4"

  # Evaluate the serialized associative arrays to deserialize them.
  eval "$s6_architecture_mappings_str"
  eval "$platform_mappings_str"

  local json_data
  json_data="$(jq -r '. as $all |
    keys[] as $image |
    $all[$image][] |
    [ $image, .version, .latest_local_digest, (.architectures | join(" ")) ] |
    @csv' "$official_image_metadata_file")"

  local image image_version architectures arch platform s6_overlay_architecture
  local latest_local_digest latest_registry_digest

  while IFS=, read -r image image_version latest_local_digest architectures; do
    image=$(tr -d '"' <<< "$image")
    image_version=$(tr -d '"' <<< "$image_version")
    latest_local_digest=$(tr -d '"' <<< "$latest_local_digest")

    if [[ $update == 'true' ]]; then
      latest_registry_digest="$(get_latest_digest_from_registry "$image" "$image_version")"

      if [[ "$latest_registry_digest" == "$latest_local_digest" ]]; then
        # If the locally tracked digest is up-to-date then skip this build_job.
        continue
      fi
    fi

    for arch in $architectures; do
      arch=$(tr -d '"' <<< "$arch")

      platform=${platform_mappings[$arch]}
      s6_overlay_architecture=${s6_architecture_mappings[$arch]}

      BUILD_JOBS+=("$platform,$image,$image_version,$s6_overlay_architecture,$latest_registry_digest")
    done
  done <<< "$json_data"

  if (( ${#BUILD_JOBS[@]} == 0 )); then
    echo "No updates available."
    exit 0
  fi
}

build_image() {
  local job="$1"
  local push_option="$2"

  IFS=',' read -r platform image image_version s6_overlay_architecture latest_registry_digest <<< "$job"

  ./scripts/build_image.sh \
      -p "$platform" \
      -i "$image" \
      -v "$image_version" \
      -a "$s6_overlay_architecture" "$push_option" \
    && echo "$image $image_version $latest_registry_digest" >> "$SUCCESSFUL_BUILDS_TMP_FILE"
}

create_successful_builds_tmp_file() {
  local file_basename='successful_builds'
  local tmpfile
  tmpfile="$(mktemp -qp . -t "$file_basename")" || {
    echo "Error: couldn't create $tmpfile" >&2;
    exit 1;
  }
  echo "$tmpfile"
}

job_builder() {
  local official_image_metadata_file="$1"
  local s6_architecture_mappings_str="$2"
  local platform_mappings_str="$3"
  local push="$4"
  local update="$5"

  PUSH_OPTION=""
  if [[ $push == 'true' ]]; then
    PUSH_OPTION="--push"
  fi

  queue_build_jobs "$official_image_metadata_file" "$s6_architecture_mappings_str" "$platform_mappings_str" "$update"

  SUCCESSFUL_BUILDS_TMP_FILE="$(create_successful_builds_tmp_file)"

  # Export identifiers for use in subshells created by parallel.
  export PUSH_OPTION
  export SUCCESSFUL_BUILDS_TMP_FILE
  export -f build_image
  export -f setup_signal_handling
  export -f cleanup
  export -a BUILD_JOBS
  export -a SUCCESSFUL_BUILDS

  printf "%s\n" "${BUILD_JOBS[@]}" | parallel --colsep ' ' \
      --group \
      --tagstring 'CORE #{%}﹕{2}-{3}-{4}' \
      build_image {} "$PUSH_OPTION"

  if [[ $update == 'true' ]]; then
    while IFS=' ' read -r image image_version latest_registry_digest; do
      update_digest "$image" "$image_version" "$latest_registry_digest"
    done < "$SUCCESSFUL_BUILDS_TMP_FILE"
  fi
}

main() {
  setup_signal_handling

  cd "$(get_repo_root_directory)" || exit 1

  local mappings
  mappings="$(load_s6_architecture_mappings "$S6_ARCHITECTURE_MAPPINGS_FILE")"
  s6_architecture_mappings_str="$(echo "$mappings" | head -n 1)"
  platform_mappings_str="$(echo "$mappings" | tail -n 1)"

  local args
  args="$(parse_command_line_arguments "$@")"

  local push update
  IFS=' ' read -r push update <<< "$args"

  job_builder "$OFFICIAL_IMAGE_METADATA_FILE" "$s6_architecture_mappings_str" "$platform_mappings_str" "$push" "$update"
}

function setup_signal_handling() {
    # Handle process interruption signals.
    trap cleanup SIGINT SIGTERM

    # Handle the EXIT signal for any script termination.
    trap cleanup EXIT
}

function cleanup() {
    # Capture the exit status of the last command before trap was triggered.
    local exit_status=$?

    echo 'Performing cleanup tasks...'

    [[ -f "$SUCCESSFUL_BUILDS_TMP_FILE" ]] && rm "$SUCCESSFUL_BUILDS_TMP_FILE"

    echo 'Cleanup complete. Exiting.'

    exit $exit_status
}

main "$@"
