# shac
 Simple Highly Available Cluster

# Install

## Quick Start

This will use gitr-done to install prerequisites for most linux distribution and their forks.

```
sh -c "$(url=https://raw.githubusercontent.com/ggpwnkthx/gitr-done/master/run.sh; curl -sSL $url || wget $url -O -)" -s https://github.com/ggpwnkthx/shac.git install.sh
```

## Manual Install

### Prerequisites

#### Distribution

There are no requirements for a specific linux distribution. This project uses Docker containers in an attempt to be as distirbution agnostic as possible.

#### Software Packages

```
sudo
git
curl
jq
fuse
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
