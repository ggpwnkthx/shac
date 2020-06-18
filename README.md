# shac
Simple Highly Available Cluster

# Install

## Automatic

This will use [gitr-done](https://github.com/ggpwnkthx/gitr-done) to install prerequisites for most linux distribution and their forks.

```
sh -c "$(url=https://raw.githubusercontent.com/ggpwnkthx/gitr-done/master/run.sh; curl -sSL $url || wget $url -O -)" -s https://github.com/ggpwnkthx/shac.git install.sh
```

## Manual

### Prerequisites

#### Distributions

There are no requirements for a specific linux distribution. This project uses Docker containers in an attempt to be as distirbution agnostic as possible. So, as long as Docker works, you should be good to go. That said, the following distributions and versions have been tested:

 - Alpine 3.12, 3.11, 3.10, 3.9
 - CentOS 8, 7
 - Debian 10.4<sup>1</sup>, 9.12<sup>1</sup>
 - Ubuntu 20.04 LTS, 18.10, 16.04.6 LTS

##### Notes

Testing of distirbutions is focused on LTS versions when applicable.

<sup>1</sup> Debian minimal installs may need the ca-certificates and curl|wget package installed prior to using the automatic installer.

#### Hardware Requirements

##### CPU Architechtures

As mentioned above, as long as Docker works, you should be good. That said, only the following CPU architectures have been tested:

 - x64
 - aarm64

##### Storage

This really depends on your use case, but to get started, each node should have at least 4GB of storage. This should be enough capacity for a minimalistic OS, SHAC scripts and binaries used, and room for distributed storage. However, I'd recommend at least 16GB for elbow room.

##### RAM

More RAM is generally better, but the orginal testing environment had only 1GB. I designed this to be run on IOT devices, specifically the lowest end model PINE Rock64.

#### Software Requirements

```
sudo
git
curl
jq
fuse
docker
```

### Download

The standard/preferred location for this project is in /usr/src/shac. The following will clone this project into that directory.

```
sudo mkdir -p /usr/src
cd /usr/src
sudo git clone https://github.com/ggpwnkthx/shac.git
sudo chown $(whoami):$(whoami) shac
cd shac
chmod +x install.sh
./install.sh
```
