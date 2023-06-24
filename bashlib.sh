#!/bin/bash
# Docker and QEMU management function library.
# These functions can be run individually from this script library
# or can be used as examples to run in a shell.
# Run this bash script with no arguments to show available functions
#
# Docker management functions
#  docker_c: create the $D_IMG container image
#  docker_r: launch the $D_IMG container with desired arguments
#  docker_d: destroy $D_IMG
#
# These assume inside docker container:
#  docker_t: confirm program versions in container
#  q_p_bld: configure and make (wrapper for meson) a qemu_system-x86_64 image
#  q_p_bld_check: verify qemu support, option to run unit test suite
#  q_p_install: install qemu (location in q_p_bld)
#  qemu_run_args: launch a qemu VM using commandline args
#  qemu_run_cfg: launc a qemu VM using (mostly) a configuration file
#
# These assume inside qemu guest VM:
#  qemu_check: verify tools in VM


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

    # make sure the string of options is accurate, otherwise weirdness
    while getopts ":lh" Option
    do
	case $Option in
	    l ) echo "setting"; CMD_LONG="1";;
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

    # qemu inside container
    export Q_P=/usr/local/bin/qemu-system-x86_64
    export Q_TOP=/home/qemu.git

    # container image on host
    export D_IMG=dockerqemu
    
    printenv | egrep "^Q_|^D_"
}

###########################################
# Operative functions
###########################################

# Create docker image
docker_c()
{
    DFILE=qemu.Dockerfile
    if [ -z $D_IMG ]; then
	echo "No Docker Image Tag set"
	exit
    fi

    echo "$PWD: CREATE Docker=$DFILE with D_IMG=$D_IMG"
    t_prompt
    docker build -f $DFILE -t $D_IMG .

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
    echo "$PWD: run D_IMG=$D_IMG using $PWD as /home/work"
    if [ -z $D_IMG ]; then
	export D_IMG="dockerqemu:latest"
	echo "No Docker D_IMG, setting to $D_IMG"
    fi

    # mount the local drive as /home/work
    #  --rm: remove container on exit
    #  -i: interactive, keep STDIN open
    #  -t: allocate a psuedo-tty
    docker run \
	   --volume="$PWD:/home/work" \
	   --volume="/opt/distros/qemu.git:/home/qemu.git" \
	   --workdir=/home/work \
	   --rm -it $D_IMG

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
    if [ -z $D_IMG ]; then
	echo "No Docker D_IMG"
	exit -1
    fi

    echo "blow away docker image D_IMG=$D_IMG ?"
    t_prompt
    docker rmi $D_IMG

    echo "current docker images"
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
	echo "may need to run q_p_bld "
    fi
}

# https://stackoverflow.com/questions/75641274/network-backend-user-is-not-compiled-into-this-binary
# https://wiki.qemu.org/ChangeLog/7.2#Removal_of_the_%22slirp%22_submodule_(affects_%22-netdev_user%22)
q_p_bld()
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

q_p_bld_check()
{
    in_container

    cd $Q_TOP
    date
    ls -l ./build/x86_64-softmmu/qemu-system-x86_64

    ./build/x86_64-softmmu/qemu-system-x86_64 --version

    ldd build/x86_64-softmmu/qemu-system-x86_64

    if [ -n "$CMD_LONG" ]; then
	echo "START qemu unit tests, ~350 test scripts..."
	t_prompt
	make check
    fi
}

q_p_install()
{
    in_container

    cd $Q_TOP
    sudo make install

    echo "Check installed version"
    $Q_P --version
}

# https://cloudinit.readthedocs.io/en/20.2/
# https://cloudinit.readthedocs.io/en/20.2/topics/debugging.html
qemu_get_debian_cloud()
{
    in_container
    
    cd /home/work
    
    DEB_DISTRO=debian-11-genericcloud-amd64.qcow2
    DEB_IMG=d11-test.qcow2 

    if [ ! -f $DEB_DISTRO ]; then
	echo "get $DEB_DISTRO"
	wget https://cloud.debian.org/images/cloud/bullseye/latest/$DEB_DISTRO
    fi

    echo "create a local copy that will be modified when a qemu_run function is called"
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
qemu_run_args()
{
    echo "Starting QEMU session using commandline args..."

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

qemu_run_cfg()
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

qemu_check()
{
    # login as dave:dave

    # check sshd is running
    ps -aux | grep ssh

    # listening on port 22
    netstat -tuln

    # ^A-c toggle to monitor and check TCP 10022->22 port fwd
    # (qemu) info usernet

    # from host: second docker term and ssh to qemu VM
    ./bashlib.sh docker_conn_shell

}

qemu_mon_cmds()
{
    # to quickly end session
    # qemu> C-a c to toggle monitor
    # mon> quit

    echo "VM monitor"

}

# create a dummy SSH keypair
gen_sshkey()
{
    SSH_KEY=id_qemu_dummy.key

    # enter github repo

    # -f file: output keyfile name
    # -v: verbose mode
    # -t rsa: type of key to create
    ssh-keygen -f ./$SSH_KEY -v -t rsa
    # no passphrase
    # creates files: $SSH_KEY and $SSH_KEY.pub

    ls -l $SSH_KEY*
    
    # paste $SSH_KEY.pub into user-data.yaml users:dave ssh_authorization_keys
    # NOTE: need to rebuild
    # quick fix in VM: overwrite /home/dave/.ssh/authorized_keys with new pub key
    # qemu> echo ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCu8+8x4Ujk4J+syoJqN+ye7quLZeHZmi5DVialS99Lqi7BfSrPzOmJtPnYu0pkEVLsFvCfiMvkGgZkqqj+80mByO0Dos+H2UB0zHWgZI5nd1WQhb4AY8SOaGOpE1lY3KyhNCsbHBNSGUrBhan0SFJ8MQuZ3FqPGOG9qXv8CbLlmOpDxmLPCSupFod7HdfodNOgUrlwoSlyKA0pbgFuqEP9uTwyhpaOazfKQbZGOuUhO5wwM8GFBWuyWarqv9YyYJpf8akNfeiZ9rBttC8XT8wrmiElRqr5XHvMFNpzt7fR0BLCcg4qiuFttuNJiyxQPq3dCHvY+pYu7LP0tzelW/Mr > /home/dave/.ssh/authorized_keys
    
}

# 
docker_qemu_ssh_conn()
{

    # start a second docker shell: docker_conn_shell

    # ssh to qemu cloud image
    ssh -p 10022 -i /home/work/id_qemu_dummy.key dave@localhost
    # if connect fails:
    #  in docker check id_qemu_dummy.key.pub
    #  in qemu console confirm /home/dave/.ssh/authentication matches the pubkey

}

####################################################################
bld_all()
{

    ########### host bash #########

    # set env for building docker container
    . ./bashlib.sh set_env

    # create docker image
    ./bashlib.sh docker_c

    # enter docker container
    ./bashlib.sh docker_r

    ########### docker container #########

    # set env for building/running qemu
    . ./bashlib.sh set_env

    # verify necessary execs in container
    ./bashlib.sh docker_t

    # build qemu
    ./bashlib.sh q_p_bld

    # check qemu
    # -l runs all the unit tests, LONG recommended on initial qemu build and upgrades
    # ./bashlib -l q_p_bld_check
    ./bashlib.sh q_p_bld_check

    ./bashlib.sh q_p_install

    # recreate debian cloud VM from scratch
    ./bashlib.sh qemu_get_debian_cloud

    ########### container: enter qemu guest ################
    ./bashlib.sh qemu_run_args

    ./bashlib.sh qemu_check
    
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

