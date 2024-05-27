#!/usr/bin/env bash

# Constant.
IMAGE_IGNORE_LIST='moby/buildkit\|none\|tonistiigi/binfmt'

function parse_command_line_arguments() {
  local short='lr'
  local long='local,remote'

  local options
  options="$(getopt -o "$short" --long "$long" -- "$@")"
  eval set -- "$options"

  local local_images='false'
  local remote_images='false'

  while true; do
    case "$1" in
      -l | --local)
        local_images='true'
        shift
        ;;
      -r | --remote)
        remote_images='true'
        shift
        ;;
      --)
        shift
        break
        ;;
    esac
  done

  echo "$local_images" "$remote_images"
}

get_images() {
  # Get a list of all image names on the system in repo:tag format.
  local images
  images="$(docker image ls -a --format '{{.Repository}}:{{.Tag}}' | grep -v "$IMAGE_IGNORE_LIST")"
  IFS=$'\n' read -r -d '' -a images < <(docker image ls -a --format '{{.Repository}}:{{.Tag}}' | grep -v "$IMAGE_IGNORE_LIST" && printf '\0')

  if [[ $images == '' ]]; then
    echo 'No images have been created.'
    exit 1
  fi

  echo "${images[@]}"
}

list_local_architectures() {
  local images="$1"

  local image architecture

  echo "Local Image Architectures"
  echo "=========================="
  echo

  for image in $images; do
    # Get image details and extract architecture.
    architecture="$(docker image inspect -f '{{ .Architecture }}{{ .Variant }}' "$image")"

    echo "${image}: ${architecture}"
  done
}

list_remote_architectures() {
  local images="$1"

  local image manifest architectures os arch variant output

  for image in $images; do

    # Get manifest details and extract architectures.
    manifest="$(docker manifest inspect "$image")"
    if [[ $? -ne 0 ]]; then
      continue
    fi

    architectures=""
    while IFS= read -r entry; do
      os="$(echo "$entry" | jq -r '.platform.os')"
      [[ $os == 'unknown' ]] && continue
      arch="$(echo "$entry" | jq -r '.platform.architecture')"
      variant="$(echo "$entry" | jq -r '.platform.variant // empty')"

      if [[ -n $variant ]]; then
        architectures+="${os}/${arch}/${variant} "
      else
        architectures+="${os}/${arch} "
      fi
    done <<< "$(echo "$manifest" | jq -c '.manifests[]')"

    output+="$image\t$architectures\n"
  done

  echo "Remote Image Architectures"
  echo "=========================="
  echo -e "$output" | column -t -s $'\t'
  echo
}

main() {
  local images
  images="$(get_images)"

  local local_images remote_images
  read -r local_images remote_images <<< "$(parse_command_line_arguments "$@")"

  if [[ "$remote_images" == 'true' ]]; then
    list_remote_architectures "$images"
  fi

  if [[ "$local_images" == 'true' || ($local_images == 'false' && $remote_images == 'false') ]]; then
    list_local_architectures "$images"
  fi
}

main "$@"
