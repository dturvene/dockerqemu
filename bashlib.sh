#!/bin/bash
# Docker and QEMU management function library.
# These functions can be run individually from this script library
# or can be used as examples to run in a shell.
# Run this bash script with no arguments to show available functions
#
# Docker management functions
#  docker_c: create the $IMG_TAG container image
#  docker_r: launch the $IMG_TAG container with desired arguments
#  docker_d: destroy $IMG_TAG
#
# These assume inside docker container:
#  docker_t: confirm program versions in container
#  qemu_x86_bld: configure and make (wrapper for meson) a qemu_system-x86_64 image
#  qemu_x86_bld_check:
#  qemu_x86_start_cmd: start a qemu guest using commandline args
#  qemu_x86_start_cfg: start a qemu guest using (mostly) a configuration file
#
# These assume inside qemu guest:


# NOTE: A lot of this is boilerplate

dstamp=$(date +%y%m%d)
tstamp='date +%H%M%S'
default_func=usage

# script commandline options
CMD_LONG=""

usage() {

    if [ -z "$Q_TOP" ]; then
        printf "\nmust run '. ./bashlib.sh set_env' to set environment variables in this shell\n"
    fi

    printf "\nUsage: $0 [options] func [func]+"
    printf "\n Valid opts:\n"
    printf "\t-l: set CMD_LONG env var (default CMD_LONG=:${CMD_LONG}:)\n"
    printf "\n Available funcs:\n"

    # display available functions in this library
    typeset -F | sed -e 's/declare -f \(.*\)/\t\1/' | grep -v -E "usage|parseargs"
}

parseargs() {

    while getopts "l:h" Option
    do
	case $Option in
	    l ) CMD_LONG="1";;
	    h | * ) usage
		exit 1;;
	esac
    done

    shift $(($OPTIND - 1))
    
    # Remaining arguments are the functions to eval
    # If none, then call the default function
    EXECFUNCS=${@:-$default_func}
}

t_prompt() {

    printf "Continue [YN]?> " >> /dev/tty; read resp
    resp=${resp:-n}

    if ([ $resp = 'N' ] || [ $resp = 'n' ]); then 
	echo "Aborting" 
        exit 1
    fi
}

trapexit() {

    echo "Catch Ctrl-C"
    t_prompt
}

# check if inside a container
in_container()
{
    echo "Check in the docker container"
    
    grep -q docker /proc/1/cgroup
    if [ $? != 0 ]; then
	echo "NOT IN CONTAINER"
	exit -1
    fi

    if [ ! -f /.dockerenv ]; then
	echo "NOT IN CONTAINER"
	exit -1
    fi

}

###########################################
# Setup
###########################################

# set helper environment
# . ../work/bashlib.sh set_env
set_env() {

    echo "Loading additional $0 environment variables"

    export Q_P=/usr/local/bin/qemu-system-x86_64
    export Q_TOP=/home/qemu.git
    
    printenv | egrep "^Q_"
}

###########################################
# Operative functions
###########################################
init() {

    # generic initialization function, change as necessary
    echo "placeholder"

}

# Create docker image
docker_c()
{
    DFILE=qemu.Dockerfile
    if [ -z $IMG_TAG ]; then
	echo "No Docker Image Tag set"
	exit
    fi

    echo "$PWD: CREATE Docker=$DFILE with IMG_TAG=$IMG_TAG"
    t_prompt
    docker build -f $DFILE -t $IMG_TAG .

    # check images
    docker images
    
    # if desired, prune intermediate images to clean up
    # docker image prune -f

    # check running images
    docker ps -aq
}

# Launch docker image
docker_r()
{
    echo "$PWD: run IMG_TAG=$IMG_TAG using $PWD as /home/work"
    if [ -z $IMG_TAG ]; then
	export IMG_TAG="dockerqemu:latest"
	echo "No Docker IMG_TAG, setting to $IMG_TAG"
    fi

    # mount the local drive as /home/work
    #  --rm: remove container on exit
    #  -i: interactive, keep STDIN open
    #  -t: allocate a psuedo-tty
    docker run \
	   --volume="$PWD:/home/work" \
	   --volume="/opt/distros/qemu.git:/home/qemu.git" \
	   --workdir=/home/work \
	   --rm -it $IMG_TAG

}

# from host, connect to running container on a second interface
docker_conn_shell()
{
    # set desired container id and then start a bash session
    export CID=$(docker ps -q)
    echo "$CID: enter bash shell"
    docker exec -it $CID bash
}

docker_d()
{
    if [ -z $IMG_TAG ]; then
	echo "No Docker IMG_TAG"
	exit -1
    fi

    # blow away $IMG_TAG and start fresh
    docker rmi $IMG_TAG

    docker images
}

# confirm versions of necessary packages, esp. meson
docker_t()
{
    in_container

    echo "See qemu.Dockerfile for installed debian packages"

    echo "CHECK python 3.7+"
    python --version

    echo "CHECK pip 22.3+ for python 3.7"
    pip --version

    echo "CHECK meson python package, should be > 1.0"
    meson --version

    echo "CHECK qemu version, should be > 7.1"
    if [ -n "$Q_P" -a -f $Q_P ]; then
	$Q_P --version
    else
	echo "NOT FOUND: Q_P=$Q_P"
	echo "may need to run qemu_x86_bld and "
    fi
}

# https://stackoverflow.com/questions/75641274/network-backend-user-is-not-compiled-into-this-binary
# https://wiki.qemu.org/ChangeLog/7.2#Removal_of_the_%22slirp%22_submodule_(affects_%22-netdev_user%22)
qemu_x86_bld()
{
    cd $Q_TOP
    
    # if feature exists it will be automatically be enabled
    # post 7.1, slirp is a separate project so need to explicitly enable
    echo "Configuring build..."
    ./configure \
 	--prefix=/usr/local \
	--target-list=x86_64-softmmu \
	--enable-debug \
	--enable-slirp \
	| tee /home/work/LOG.CONFIG.QEMU

    # if configure fails, check the meson log
    if [ $? != 0 ]; then	
	cat build/meson-logs/meson-log.txt
    fi

    time make -j8

    # if make fails...
    if [ $? != 0 ]; then
	cat build/meson-logs/meson-log.txt
    fi
}

qemu_x86_bld_check()
{
    in_container

    cd $Q_TOP
    date
    ls -l ./build/x86_64-softmmu/qemu-system-x86_64

    ./build/x86_64-softmmu/qemu-system-x86_64 --version

    ldd build/x86_64-softmmu/qemu-system-x86_64

    if [ -n "$CMD_LONG" ]; then
	echo "running make check, long ~340 test scripts..."
	# make check
    fi
}

qemu_x86_install()
{
    in_container

    cd $Q_TOP
    sudo make install

    echo "Check installed version"
    $Q_P --version
}

# https://cloudinit.readthedocs.io/en/20.2/
# https://cloudinit.readthedocs.io/en/20.2/topics/debugging.html
d11_cloud_c()
{
    in_container
    
    cd /home/work
    
    DEB_DISTRO=debian-11-genericcloud-amd64.qcow2
    DEB_IMG=d11-test.qcow2 
    
    wget https://cloud.debian.org/images/cloud/bullseye/latest/$DEB_DISTRO

    # create snapshot
    qemu-img convert -f qcow2 -O qcow2 $DEB_DISTRO $DEB_IMG 

    qemu-img info $DEB_IMG

    # schema command not valid after 7.1
    # echo "verify config correctness"
    # cloud-init schema --config-file user-data.yaml

    echo "create seed.img for VM: user-data.yaml, metadata.yaml"
    cloud-localds seed.img user-data.yaml metadata.yaml
    
    qemu-img info seed.img
    
}

#
qemu_x86_start_cmd()
{
    echo "Starting QEMU session using cmdline..."

    NET_Q35="-netdev id=net0,type=user,hostfwd=tcp::10022-:22 -device virtio-net-pci,netdev=net0"
    # qemu-system-x86_64: -netdev id=net0,type=user,hostfwd=tcp::10022-:22:
    # slirp
    #   network backend 'user' is not compiled into this binary
    VGA="-nographic"

    $Q_P -m 1G \
	 -drive file=d11-test.qcow2,if=virtio,format=qcow2 \
	 -drive file=seed.img,if=virtio,format=raw \
	 $NET_Q35 \
	 $VGA

}

qemu_x86_start_cfg()
{
    echo "Starting QEMU session using local configuration file..."

    NET_Q35="-netdev id=net0,type=user,hostfwd=tcp::10022-:22 -device virtio-net-pci,netdev=net0"
    # qemu-system-x86_64: -netdev id=net0,type=user,hostfwd=tcp::10022-:22:
    # slirp
    #   network backend 'user' is not compiled into this binary
    VGA="-nographic"

    $Q_P -m 1G \
	 -drive file=d11-test.qcow2,if=virtio,format=qcow2 \
	 -drive file=seed.img,if=virtio,format=raw \
	 $NET_Q35 \
	 $VGA

}

qemu_x86_regtest()
{
    # login as dave:dave

    # check ssh
    ps -aux | grep ssh

    # listening on port 22
    netstat -tuln

    # enter monitor
    # mon> info usernet

}

qemu_mon_cmds()
{
    # to quickly end session
    # qemu> C-a c to toggle monitor
    # mon> quit

    echo "VM monitor"

}

# 
docker_qemu_ssh_conn()
{

    # start a second docker shell: docker_conn_shell

    # ssh to qemu cloud image
    ssh -p 10022 -i /home/work/id_rsa.dummy dturvene@localhost

}

###########################################
#  Main processing logic
###########################################
trap trapexit INT

parseargs $*

for func in $EXECFUNCS
do
    eval $func
done

