#!/bin/sh

# Default variables
BASEPATH=$1

download_binaries() {
    mkdir -p $BASEPATH/bin
    /usr/bin/github-release-installer chrislusf/seaweedfs /usr/src/shac/bin
}

git_clean_pull() {
    cd $1
    git reset --hard HEAD
    git clean -f -d
    git pull
    chmod +x start.sh
}

# Rebuild all the docker images
build_docker_images() {
    cd $BASEPATH/docker/build/base
    docker build --no-cache . -t shac/base
    for img in $(ls -1 $BASEPATH/docker/build); do
        if [ "$img" != "base" ]; then
            if [ -d $BASEPATH/docker/build/$img ]; then
                cd $BASEPATH/docker/build/$img
                docker build --no-cache . -t shac/$img
            fi
        fi
    done
}

git_clean_pull $BASEPATH
build_docker_images
download_binaries