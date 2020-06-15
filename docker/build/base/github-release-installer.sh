#!/bin/bash
arch=$(uname -m)
case "$arch" in
    arm) 
        arch="arm"
        ;;
    aarch64_be | aarch64 | armv8b | armv8l)
        arch="arm64"
        ;;
    i386 | i686)
        arch="386"
        ;;
    x86_64 )
        arch="amd64"
        ;;
    * )
        echo "While I can certainly appreciate the desire to run this on anything and everything,"
        echo "the $(uname -m) architechture is not currently supported. This system is largly dependant"
        echo "on Docker. So if your platform can run Docker and you are still seeing this message"
        echo "we should be able to get it working."
        exit 1
        ;;
esac
echo $arch
repo=$(echo $1 | awk -F/ '{print $2}')
echo $repo
kname=$(uname -s | tr '[:upper:]' '[:lower:]')
echo $kname
url=($(curl -s -L https://github.com/$1/releases/latest | egrep -o "$1/releases/download/.*/.*$kname.*$arch.*.tar.gz"))
echo "$url"
wget -O /tmp/$repo.tar.gz https://github.com/${url[0]}
tar -C $2/ -xzvf /tmp/$repo.tar.gz
rm /tmp/$repo.tar.gz

echo "Finished installing $1"