#!/usr/bin/env bash

# Exit immediately if a command fails.
set -e

DOCKER_CMD='sudo docker'

cleanup_containers() {
  echo "Checking for running docker containers..."
  declare -a containers
  while IFS= read -r container; do
    containers+=("$container")
  done < <($DOCKER_CMD ps -aq)

  if (( ${#containers[@]} > 0 )); then
    for container in "${containers[@]}"; do
      echo "Stopping running docker containers..."
      ${DOCKER_CMD} stop "$container"
    done

    echo "Removing stopped docker containers..."
    for container in "${containers[@]}"; do
      ${DOCKER_CMD} rm "$container"
    done
  else
    echo "No docker containers are running."
  fi
}

cleanup_images() {
  echo "Checking for existing docker images..."

  declare -a images
  while IFS= read -r image; do
    images+=("$image")
  done < <(${DOCKER_CMD} image ls -aq)

  if (( ${#images[@]} > 0 )); then
    echo "Removing docker images..."
    for image in "${images[@]}"; do
      ${DOCKER_CMD} rmi -f "$image"
    done
  else
    echo "No docker images exist."
  fi
}

main() {
  cleanup_containers
  cleanup_images
}

main
