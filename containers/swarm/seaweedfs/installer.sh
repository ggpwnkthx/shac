#!/bin/sh
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

seaweed_url=$(curl -s -L https://github.com/chrislusf/seaweedfs/releases/latest | egrep -o "chrislusf/seaweedfs/releases/download/.*/linux_$arch.tar.gz")
wget -O /tmp/weed.tar.gz https://github.com/$seaweed_url >/dev/null 2>/dev/null
tar -C /usr/bin/ -xzvf /tmp/weed.tar.gz >/dev/null
rm /tmp/weed.tar.gz
