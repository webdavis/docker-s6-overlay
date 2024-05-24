default:
    @just --choose

alias L := docker-image-ls
alias P := docker-ps
alias b := build-images-in-parallel
alias l := list-local-image-architectures
alias r := list-remote-image-architectures
alias c := clean

docker-image-ls:
    sudo docker image ls -a

docker-ps:
    sudo docker ps -a

build-images-in-parallel:
    ./scripts/run_parallel_builds.sh

list-local-image-architectures:
    ./scripts/list-image-architectures.sh -l

list-remote-image-architectures:
    ./scripts/list-image-architectures.sh -r

clean:
    ./scripts/clean.sh
