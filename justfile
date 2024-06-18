default:
    @just --choose

alias L := docker-image-ls
alias P := docker-ps
alias B := bootstrap-docker-builder
alias b := build-images-in-parallel
alias p := push-images-in-parallel
alias u := update-and-push-images-in-parallel
alias l := list-local-image-architectures
alias r := list-remote-image-architectures
alias c := clean

docker-image-ls:
    docker image ls -a

docker-ps:
    docker ps -a

bootstrap-docker-builder:
    docker buildx create --use --name mybuilder
    docker buildx inspect mybuilder --bootstrap

build-images-in-parallel:
    ./scripts/run_parallel_builds.sh

push-images-in-parallel:
    ./scripts/run_parallel_builds.sh --push

update-and-push-images-in-parallel:
    ./scripts/run_parallel_builds.sh --update --push

list-local-image-architectures:
    ./scripts/list_image_architectures.sh -l

list-remote-image-architectures:
    ./scripts/list_image_architectures.sh -r

clean:
    ./scripts/clean.sh
