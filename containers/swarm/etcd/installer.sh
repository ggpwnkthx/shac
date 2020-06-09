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

etcd_url=$(curl -s -L https://github.com/etcd-io/etcd/releases/latest | egrep -o "etcd-io/etcd/releases/download/.*/.*linux_$arch.tar.gz")
wget -P /tmp -O etcd.tar.gz https://github.com/$etcd_url >/dev/null 2>/dev/null
tar -C /bin/ -xzvf /tmp/etcd.gz >/dev/null
rm /tmp/etcd.tar.gz