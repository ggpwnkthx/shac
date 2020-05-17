#!/bin/sh
check_environment() {
	user="$(id -un 2>/dev/null || true)"

	lsb_dist=""
	# Every system that we officially support has /etc/os-release
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	# Returning an empty string here should be alright since the
	# case statements don't act unless you provide an actual value
	
	# Check distribution
	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"
	# Determin if forked
	case "$lsb_dist" in
		"elementary os"|neon|linuxmint|ubuntu|kubuntu|manjaro|raspian)
			fork_of="debian"
			;;
		arch|centos|fedora)
			fork_of="rhel"
			;;
		*)
			fork_of=$lsb_dist
			;;
	esac

	# Check which package manager should be used
	pkgmgrs="apt apt-get yum dnf apk pacman zypper"
	for mgr in $pkgmgrs; do
		if command_exists $mgr; then pkgmgr=$mgr; fi
	done
}

do_install() {
	# Run setup for each distro accordingly
	case "$pkgmgr" in
		# Alpine
		apk)
			$pkgmgr update
			for pkg in $@; do 
				if ! $pkgmgr search -v $pkg; then
					$pkgmgr add $pkg
				fi
			done
			;;
		# Debian
		apt|apt-get)
			if [ $(date +%s --date '-10 min') -gt $(stat -c %Y /var/cache/apt/) ]; then
				$pkgmgr update -qq
			fi
			for pkg in $@; do 
				DEBIAN_FRONTEND=noninteractive $pkgmgr install -y $pkg
			done
			;;
		# RHEL
		dnf|yum)
			for pkg in $@; do
				if ! $pkgmgr list installed $pkg; then
					$pkgmgr install -y $pkg
					if $pkg -eq epel-release; then
						$pkgmgr update
					fi
				fi
			done
			;;
		# Arch
		pacman)
			for pkg in $@; do
				$pkgmgr -Sy $pkg
			done
			;;
		# openSUSE
		zypper)
			for pkg in $@; do
				$pkgmgr --non-interactive --auto-agree-with-licenses install $pkg
			done
			;;
		*)
			echo
			echo "ERROR: Unsupported distribution '$lsb_dist'"
			echo
			exit 1
			;;
	esac
}

check_environment
do_install $@