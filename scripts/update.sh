#!/bin/sh

# Default variables
BASEPATH=$1

git_clean_pull() {
    cd $BASEPATH
    git reset --hard HEAD
    git clean -f -d
    git pull
    chmod +x start.sh
    chmod +x update.sh
}

# Rebuild all the docker images
build_docker_images() {
    cd $BASEPATH/docker/build/base
    docker build . -t shac/base
    for img in $(ls -1 $BASEPATH/docker/build); do
        if [ "$img" != "base" ]; then
            if [ -d $BASEPATH/docker/build/$img ]; then
                cd $BASEPATH/docker/build/$img
                docker build . -t shac/$img
            fi
        fi
    done
}