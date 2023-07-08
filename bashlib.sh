#!/bin/bash
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2023 David Turvene <dturvene at gmail>
# 
# Docker and QEMU management function library.
# These functions can be run individually from this script library
# or can be used as examples to run in a shell.
# 
# Run this bash script with no arguments to show available functions
#
# Docker management functions
#  docker_c: create the $D_IMG container image
#  docker_r: launch the $D_IMG container with desired arguments
#  docker_d: destroy $D_IMG
#
# These assume inside docker container:
#  docker_check: confirm program versions in container
#  q_p_bld: configure and make (wrapper for meson) a qemu_system-x86_64 image
#  q_p_bld_check: verify qemu support, option to run unit test suite
#  q_p_install: install qemu (location in q_p_bld)
#  get_debian_cloud: wget a Debian distro cloud image and create the
#  create_seed: cloud-init seed.img from yaml files
#  qemu_run_args: launch a qemu guest OS using commandline args
#  qemu_run_cfg: launch a qemu guest OS using (mostly) a device configuration file
#  qemu_run_virtiofsd: launch virtio filesystem deamon
#  qemu_run_vfs_args: same a qemu_run_args but adds virtiofsd mapping
#  qemu_run_vfs_cfg: same a qemu_run_cfg but adds virtiofsd mapping
#
# These assume inside qemu guest OS:
#  qemu_guest_check: verify functionality of the QEMU guest OS
#
# Procedures:
#  bld_all: all steps to build and run qemu in docker
#  restart_all: once docker image and qemu exec are built, steps to restart
#  restart_all_virtiofs: same as restart all but launches virtiofsd

# library function to run if none on command line
default_func=usage

# q_p_bld_check argument to run QEMU runtime tests
CMD_LONG=""

usage() {

    if [ -z "$Q_TOP" ]; then
        printf "\nmust run '. ./env_vars' to set environment variables in this shell\n"
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
    echo "Verify in the docker container"
    
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
	echo "No Docker D_IMG, use env_vars"
    fi
    t_prompt

    KVM_GROUP=130

    # mount
    #  * local git repo
    #  * QEMU artifacts
    #  * host qemu source git clone
    #  --device: map the host /dev/kvm device
    #  --group-add: add the host KVM group to user
    #  --workdir: the current directory with this script
    #  --rm: remove container on exit
    #  -i: interactive, keep STDIN open
    #  -t: allocate a psuedo-tty
    #  --device=/dev/shm must have --privileged
    docker run \
	   --volume="$PWD:/home/work" \
	   --volume="$HOME/Stage/QEMU:$Q_ARTIFACTS" \
	   --volume="/opt/distros/qemu.git:/home/qemu.git" \
	   --volume="/dev/shm:/dev/shm"	\
	   --shm-size=1g \
	   --workdir=/home/work \
	   --device=/dev/kvm \
	   --group-add $KVM_GROUP \
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

# pattern to update docker image after changes in container
# this is a shortcut to avoid running bld_all
# NOTE: update qemu.Dockerfile with local changes
docker_u()
{

    echo "example, run manually with desired CID"
    exit -2

    # process status of all running containers
    docker ps
    # set the container id to create the new image
    CID=4d573b1640b0

    # create a new image from the container id using YYMMDD as the image tag
    # update set_env to use new container tag
    docker commit -m "update image w changes" $CID dockerqemu:$dstamp

    # display all images, including the new one
    docker images
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
docker_check()
{
    in_container

    if [ -z "$Q_TOP" ]; then
        printf "\nmust run '. ./env_vars' to set environment variables in this shell\n"
	exit -1
    fi

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
	echo "may need to run q_p_bld and/or q_p_install"
    fi

    echo "CHECK shared memory"
    df -h /dev/shm
    ipcs -pm
    # sudo mount -o remount,size=512m /dev/shm
    # df -h /dev/shm
}

# https://www.qemu.org/download/
#  instructions to clone qemu gitlab repo
# https://wiki.qemu.org/ChangeLog/7.2#Removal_of_the_%22slirp%22_submodule_(affects_%22-netdev_user%22)
#  new instructions for slirp interface
q_p_bld()
{
    cd $Q_TOP

    # checkout desired tag
    # git checkout v8.0.2 -b tag8.0.2
    #git branch
    #echo "Desired qemu branch to configure and make?"
    #t_prompt

    QEMU_CONFIG_LOG=/home/work/LOG.CONFIG.QEMU
    # if feature exists it will be automatically be enabled
    # post 7.1, slirp is a separate project so need to explicitly enable
    echo "Configuring build, see $QEMU_CONFIG_LOG"
    ./configure \
 	--prefix=/usr/local \
	--target-list=x86_64-softmmu \
	--enable-debug \
	--enable-slirp \
	| tee $QEMU_CONFIG_LOG

    # if configure fails, check the meson log
    if [ $? != 0 ]; then	
	cat build/meson-logs/meson-log.txt
    fi

    echo "build $Q_P using 'make -j8'"
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

    Q_P_BLD=./build/x86_64-softmmu/qemu-system-x86_64

    if [ ! -f $Q_P_BLD ]; then
	echo "No $Q_P executable"
	exit -1
    fi

    echo "Check qemu version"
    $Q_P_BLD --version

    echo "check shared libraries"
    ldd $Q_P_BLD

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

# Get a Debian generic cloud image built for QEMU from
#  https://cloud.debian.org/images/cloud/
# 
# Use canonical cloud-init to provision the generic image on
# first boot:
#  https://cloudinit.readthedocs.io/en/20.2/
#  https://cloudinit.readthedocs.io/en/20.2/topics/debugging.html
#
# See user-data.yaml, metadata.yaml to customize the
# debian guest image.  Any changes to these files
# will need to be run on an original cloud image ($DEB_DISTRO)
get_debian_cloud()
{
    in_container

    if [ ! -d $Q_ARTIFACTS ]; then
	echo "run . ./set_env]"
	exit -1
    fi
    
    cd $Q_ARTIFACTS
    echo "$PWD: get $DEB_DISTRO"
    t_prompt 
    
    if [ ! -f $DEB_DISTRO ]; then
	echo "get $DEB_DISTRO"
	wget https://cloud.debian.org/images/cloud/bullseye/latest/$DEB_DISTRO
    else
	echo "local $DEB_DISTRO exists"
    fi

    echo "create a local copy that will be modified when a qemu_run function is called"
    qemu-img convert -f qcow2 -O qcow2 $DEB_DISTRO $Q_IMG 

    qemu-img info $Q_IMG

}

create_seed()
{
    cd $Q_ARTIFACTS
    
    echo "create $Q_SEED for VM: user-data.yaml, metadata.yaml"
    cloud-localds -v $Q_SEED $D_WORK/user-data.yaml $D_WORK/metadata.yaml
    
    qemu-img info $Q_SEED

}

qemu_run_args()
{
    echo "$Q_IMG: Starting QEMU session using commandline args..."

    NET_Q35="-netdev id=net0,type=user,hostfwd=tcp::10022-:22 -device virtio-net-pci,netdev=net0"
    VGA="-nographic"
    MEM="-m 1G"

    MACH="-machine q35,accel=kvm,usb=off"
    CPU="-cpu host -smp 4,sockets=2,cores=2,threads=1"
    #MACH="-machine q35,usb=off"
    # -cpu host requires accel=kvm
    #CPU="-cpu Broadwell-v4 -smp 4,sockets=2,cores=2,threads=1"
    
    $Q_P $MACH $CPU $MEM \
	 -drive file=$Q_IMG,if=virtio,format=qcow2 \
	 -drive file=$Q_SEED,if=virtio,format=raw \
	 $NET_Q35 \
	 $VGA

}

qemu_run_cfg()
{
    echo "Starting QEMU session from configuration file..."
    CFG=d11-guest.cfg

    # $CFG has a [device "video"] section to create a QXL window

    # default connects to x11 server, disable this
    DISP="-display none"

    # write console to a log file
    # DBG_LOG="-serial file:${D_WORK}/d11_readcfg.log"

    # console starts as bash shell
    # C-a c toggles between bash and monitor
    MON="-serial mon:stdio -monitor"

    # shell on console
    # CONSOLE="-serial stdio"

    $Q_P -nodefaults -readconfig ${CFG} \
	 $DBG_LOG $DISP -serial mon:stdio

}

# https://gitlab.com/virtio-fs/virtiofsd#examples
qemu_run_virtiofsd()
{
    in_container

    cd $D_WORK
    
    # --inode-file-handles : Filesystem does not support file handles
    sudo $Q_ARTIFACTS/$Q_VIRTIOFSD --socket-path=/tmp/vfsd.sock --shared-dir . --sandbox chroot &

    sleep 0.2
    echo "Checking $Q_VIRTIOFSD pid"
    pidof $Q_VIRTIOFSD
}

qemu_run_vfs_args()
{

    echo "Starting QEMU session using commandline args..."

    NET_Q35="-netdev id=net0,type=user,hostfwd=tcp::10022-:22 -device virtio-net-pci,netdev=net0"
    VGA="-nographic"
    MEM="-m 4G"
    MACH="-machine q35,accel=kvm,usb=off"
    # -cpu host requires accel=kvm
    CPU="-cpu host -smp 4,sockets=2,cores=2,threads=1"	
    #MACH="-machine q35"
    #CPU="-cpu Broadwell-v4 -smp 4,sockets=2,cores=2,threads=1"

    # host directory mapped in qemu_run_virtiofsd
    VIRTSOCK="-chardev socket,id=char0,path=/tmp/vfsd.sock"
    VIRTDEV="-device vhost-user-fs-pci,queue-size=1024,chardev=char0,tag=hostdir"
    MSHARE="-object memory-backend-file,id=mem,size=4G,mem-path=/dev/shm,share=on -numa node,memdev=mem"
    # qemu-system-x86_64: total memory for NUMA nodes (0x20000000) should equal RAM size (0x100000000)

    # need to use sudo for VIRTSOCK permission
    sudo $Q_P $MACH $CPU $MEM \
	 -drive file=$Q_IMG,if=virtio,format=qcow2 \
	 -drive file=$Q_SEED,if=virtio,format=raw \
	 $VIRTSOCK $VIRTDEV $MSHARE \
	 $NET_Q35 \
	 $VGA

}

qemu_run_vfs_cfg()
{

    echo "Starting QEMU session from configuration file..."
    CFG=d11-guest.cfg

    # $CFG has a [device "video"] section to create a QXL window

    # default connects to x11 server, disable this
    DISP="-display none"
    
    # host directory mapped in qemu_run_virtiofsd
    VIRTSOCK="-chardev socket,id=char0,path=/tmp/vfsd.sock"
    VIRTDEV="-device vhost-user-fs-pci,queue-size=1024,chardev=char0,tag=hostdir"
    MSHARE="-object memory-backend-file,id=mem,size=4G,mem-path=/dev/shm,share=on -numa node,memdev=mem"

    sudo $Q_P -nodefaults -readconfig ${CFG} \
	 $VIRTSOCK $VIRTDEV $MSHARE \
	 $DISP -serial mon:stdio
    
}

qemu_guest_check()
{
    # login as dave:dave

    # check sshd is running
    ps -aux | grep ssh

    # listening on port 22
    netstat -tuln

    # ^A-c toggle to monitor and check TCP 10022->22 port fwd
    # (qemu) info usernet

    # check external internet
    curl www.qemu.org
    curl https://www.qemu.org

    # mount host directory
    #sudo mount -t virtiofs hostdir /mnt
    #ls -l /mnt
}

qemu_ssh()
{
    # from host: second docker term and ssh to qemu VM
    ./bashlib.sh docker_conn_shell

    ./bashlib.sh docker_qemu_ssh_conn

}

qemu_mon_cmds()
{
    echo "VM monitor toggle using C-a c"

    # See block devices
    info block

    # See network connectivity
    info network

    # exit QEMU, or C-a x
    quit
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
    . ./set_env

    # create docker image
    ./bashlib.sh docker_c

    # enter docker container
    ./bashlib.sh docker_r

    ########### docker container #########

    # set env for building/running qemu
    . ./set_env

    # verify necessary execs in container
    ./bashlib.sh docker_check

    # build qemu
    ./bashlib.sh q_p_bld

    # check qemu
    # -l runs all the unit tests, LONG recommended on initial qemu build and upgrades
    # ./bashlib -l q_p_bld_check
    ./bashlib.sh q_p_bld_check

    ./bashlib.sh q_p_install

    # recreate debian cloud VM from scratch
    ./bashlib.sh qemu_get_debian_cloud

    # create and enter qemu guest
    # ./bashlib.sh qemu_run_args
    ./bashlib.sh qemu_run_cfg

    ########### QEMU guest image #########
    ./bashlib.sh qemu_guest_check
}

restart_all()
{
    ################## host shell #########################

    # set env for building docker container
    . ./set_env

    # make sure set the desired docker image
    echo $D_IMG
    docker images

    # start container
    ./bashlib.sh docker_r

    ##### $D_IMG container #############
    . ./set_env

    ./bashlib.sh docker_check

    # boot QEMU guest
    ./bashlib.sh qemu_run_cfg

    ######### QEMU guest ################
    echo "login dave:dave"

    echo "steps from qemu_guest_check"
}

restart_all_virtiofs()
{
    ################## host shell #########################

    # set env for building docker container
    . ./set_env

    # make sure set the desired docker image
    echo $D_IMG
    docker images

    # start container
    ./bashlib.sh docker_r

    ##### $D_IMG container #############
    . ./set_env

    ./bashlib.sh docker_check

    # start virtio file system daemon
    ./bashlib.sh qemu_run_virtiofsd

    # qemu using config file and mapping virtio filesystem
    ./bashlib.sh qemu_run_vfs_cfg

    ######### QEMU guest ################
    echo "login dave:dave"

    echo "steps from qemu_guest_check"
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

