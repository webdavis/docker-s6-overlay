#!/usr/bin/env bash

IMAGE_IGNORE_LIST='moby/buildkit\|none\|tonistiigi/binfmt'

function parse_command_line_arguments() {
  local short='lr'
  local long='local,remote'

  local='false'
  remote='false'

  OPTIONS="$(getopt -o "$short" --long "$long" -- "$@")"

  eval set -- "$OPTIONS"

  while true; do
    case "$1" in
      -l | --local)
        local='true'
        shift
        ;;
      -r | --remote)
        remote='true'
        shift
        ;;
      --)
        shift
        break
        ;;
    esac
  done

  if [[ "$local" == 'false' && "$remote" == 'false' ]]; then
    list_local_architectures
    return
  fi

  if [[ "$local" == 'true' ]]; then
    list_local_architectures
  fi

  if [[ "$remote" == 'true' ]]; then
    list_remote_architectures
  fi
}

get_images() {
  # Get a list of all image names on the system in repo:tag format.
  IMAGES="$(docker image ls -a --format '{{.Repository}}:{{.Tag}}' | grep -v "$IMAGE_IGNORE_LIST")"

  if [[ $IMAGES == '' ]]; then
    echo 'No images have been created.'
    exit 1
  fi
}

list_local_architectures() {
  local image architecture

  for image in $IMAGES; do
    # Get image details and extract architecture.
    architecture="$(docker image inspect -f '{{ .Architecture }}{{ .Variant }}' "$image")"

    echo "${image}: ${architecture}"
  done
}

list_remote_architectures() {
  local image manifest architectures os arch variant formatted_architectures

  for image in $IMAGES; do

    # Get manifest details and extract architectures.
    manifest="$(docker manifest inspect "$image")"

    if [[ $? -ne 0 ]]; then
      continue
    fi

    architectures=""
    while IFS= read -r entry; do
      os="$(echo "$entry" | jq -r '.platform.os')"
      arch="$(echo "$entry" | jq -r '.platform.architecture')"
      variant="$(echo "$entry" | jq -r '.platform.variant // empty')"

      if [[ -n $variant ]]; then
        architectures+="${os}/${arch}/${variant} "
      else
        architectures+="${os}/${arch} "
      fi
    done <<< "$(echo "$manifest" | jq -c '.manifests[]')"

    formatted_architectures="$(echo "$architectures" | grep -v 'unknown' | tr '\n' ' ')"

    output+="$image\t$formatted_architectures\n"
  done
  echo -e "$output" | column -t -s $'\t'
}

main() {
  get_images
  parse_command_line_arguments "$@"
}

main "$@"
