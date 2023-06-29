[com1]: # Create a local html for proof, format and hyperlink review
[com2]: # host> pandoc --metadata pagetitle=docker-qemu -f markdown -s README.md -o README.html

Abstract
========
I work on [QEMU](https://www.qemu.org/) a good bit, mostly full system
emulation but, at times, also user space (for example,
cross-compiling). Why QEMU?  As I have said in previous articles, the big
advantages of using QEMU over physical hardware (including prototype boards)
are:

* a guest OS can be spun-up and provisioned quickly, allowing for rapid
  prototyping,
* a lot of runtime and state information can be gleaned from the 
  [QEMU Monitor](https://qemu-project.gitlab.io/qemu/system/monitor.html),
* there are a number of debugging and analysis options including 
  [GDB](https://www.sourceware.org/gdb/).
  
See my past QEMU articles for some uses of QEMU:

* [Linux Kernel Analysis using QEMU and GDB](https://medium.com/@dturvene/linux-kernel-analysis-using-qemu-and-gdb-d57357a215eb)
* [QEMU HW Interrupt Simulation](https://medium.com/@dturvene/qemu-hardware-interrupt-simulation-77140922a336)

However, QEMU has evolved quickly and now requires specific
versions of the [meson](https://mesonbuild.com/) build system, python-3 and
python-3 packages along with a compiler toolchain and linker shared objects.
The problem I increasingly encounter is keeping all the dependency
packages consistent and up-to-date without breaking utilities on my host
system - a Dell Intel laptop running [Ubuntu Linux](https://ubuntu.com/).

The solution I have come to embrace is to create a 
[docker](https://www.docker.com/) container with all the packages
I need to manage QEMU.  Included in these are those packages necessary to
build and install QEMU from source.  I could clone the QEMU git repo in the
container but do this on the host and map all the directories I need as docker
volumes. I also map the host
[KVM](https://www.linux-kvm.org/page/Main_Page) device for hypervisor access.
This provides me all the capabilititie of QEMU/KVM for speed.  Alternatively, I
can disable KVM hypervisor and use the 
[TCG](https://wiki.qemu.org/Documentation/TCG) for kernel debugging or
heterogeneous CPU architectures.

The list of advantages of the docker QEMU framework over a host running QEMU
include:

* the docker container has one mission: QEMU support. All packages are
  groomed to that mission,
* QEMU and a guest OS can be created, updated, run and destroyed fairly quickly,
* the docker container can be easily modified and re-created to incorporate new 
  QEMU and guest OS features.
  
Essentially I am working in a QEMU-specific sandbox.  If something goes wrong
(e.g. OS panic or image corruption) I can quickly recover.  In the worst case,
I destroy the docker image and rebuild everything from scratch.  This process
takes roughly fifteen minutes, mostly watching docker image creation or the
QEMU source build.

Functional Overview
===================
This document and [github repo](https://github.com/dturvene/dockerqemu) 
demonstrate booting, provisioning and managing:

* a [docker](https://www.docker.com/) container running 
  [Debian Linux](https://www.debian.org/) with all
  the necessary support packages for QEMU,
* a [QEMU](https://www.qemu.org/) executable build from source and install
  inside the container, 
* a [Debian Linux Cloud](https://cloud.debian.org/images/cloud/) cloud image
  downloaded and running in the QEMU full emulator.  This could be any `rootfs`
  including MS Windows but for this demonstration I chose a recent Debian cloud
  image for simplicity.

There are several operational features to note:

* On first boot, the Debian Linux Cloud image is provisioned with
  [Cloud Init](https://cloudinit.readthedocs.io/en/20.2/)
  yaml files combined into an image file.  This is a well documented and
  simpler alternative to the 
  [Debian preseed](https://wiki.debian.org/DebianInstaller/Preseed) framework. 
* QEMU can be run using the [KVM](https://www.linux-kvm.org/page/Main_Page)
  hypervisor (also known as a VM accelerator) or the 
  [TCG](https://wiki.qemu.org/Documentation/TCG) internal tiny code generator.
* QEMU can launch a guest OS using all command line arguments or with a 
  `QEMU device configuration file`.  There is very little documentation on
  the QEMU device configure files other than some examples in the QEMU source
  tree and the source code itself (start with `qemu-options.def`)
  
File Descriptions
=================
All files are in this [Docker QEMU](https://github.com/dturvene/dockerqemu)
github repo.

* `README.md`: this file
* `bashlib.sh`: library of bash functions for managing the docker container and
  qemu image. This should be used as an *example* of the necessary steps for
  each component: docker, QEMU and the guest OS image.
* `env_vars`: bash source file to set environment variables used in `bashlib.sh`
* `qemu.Dockerfile`: dockerfile to create the docker image
* `bashrc.docker`: custom `.bashrc` copied to docker image (see `qemu.Dockerfile`)
* `metadata.yaml`: Cloud Init system file defining the guest id and hostname
* `user-data.yaml`: Cloud Init user file defining user groups, users, debian
  packages and ancillary initialization commands
* `id_qemu_dummy.key`: example RSA PKE file for ssh access to QEMU guest VM

Additionally some files and directories are dynamically created:
* The QEMU executable, `$Q_P`, is generated by `bashlib.sh:q_p_bld`. The
  `qemu.git` repo is assumed to be cloned and a the desired tag is branched
  on the host (outside the scope of this doc).  The `qemu.git` repo is mounted
  as docker volume by  `bashlib.sh:docker_r`.
* The desired debian generic cloud image will be pulled from the official
  debian site by `bashlib.sh:qemu_get_debian_cloud` and converted to a local
  copy.
* See `bashlib.sh` for the use and location of progress log files including
  `LOG.CONFIG.QEMU` and `$Q_TOP/build/meson-logs/meson-log.txt`

Functional Details
==================
In `bashlib.sh:bld_all` there is a rough template for the necessary steps to
create a docker/QEMU/Debian guest OS platform. It will need to be modified
depending on your host platform, capabilities, and directory locations.

The template assumes this directory has been man:git-clone on the host and a
recent qemu source tree has been `man:git-clone` locally on the host, branched
and cleaned of prior builds.  Since the QEMU build steps are performed in the
container, any build artifacts should be removed first.

Briefly, here are the steps using a `man:bash` shell *for a first time run*

Host
----
Create a docker image and then launch a running container using the image.  See
`env_vars`, `qemu.Dockerfile` and `bashrc.docker` to customize the docker
container.

Docker Container
----------------
First test the docker container for the necessary packages 
(see `bashlib.sh:docker_check`). 

A docker container *can* access the host X11 window manager for
creating windows in the container.  I have found this to be more trouble than
worth. However, I enjoy having multiple shells connected to the container
(see`bashlib.sh:docker_conn_shell`.) 

The first major step in the container is to configure and build QEMU in the
mapped docker volume. See `bashlib.sh:q_p_bld` for configuring and making the
QEMU executable. Check that QEMU is built correctly using 
`bashlib.sh:q_p_bld_check`. This function has a command line option `CMD_LONG`
to run the QEMU test scripts which takes about 15 minutes to run.

If the QEMU executable is fully functional then use `bashlib.sh:q_p_install` to
install the components in the container. I used the `/usr/local` prefix to
install under (which requires `sudo`).

QEMU Guest OS
-------------
One of the simplest guest OS images is a Debian Linux Cloud image. See
`bashlib.sh:qemu_get_debian_cloud` for steps to create a run image, and
build the `seed.img` provisioning file from the Cloud Init yaml files. 

Now we are ready to launch the Debian guest OS in the QEMU emulator. I
demonstate two similar ways to do this:

1. `bashlib.sh:qemu_run_args`: all the configuration options are passed on the
   commandline.  This is the most common way to start QEMU.
   
2. `bashlib.sh:qemu_run_cfg`: most of the configuration is defined in a QEMU
   device configuration file and read using the `-readconfig` option.  This is
   the "new" way but is not well documented.

These functions work identically but I like the device configuration file
because it is easier to maintain and can be commented.

Both launch functions currently enable KVM for the performance benefit. To
disable KVM, and use the default TCG just switch the `kvm` keyword to
`tcg`.

QEMU emulator
-------------
Once QEMU is launched it will "boot" the Debian Linux Cloud guest OS. 

On first boot the Debian cloud image will read the Cloud Init
provisioning information built in `seed.img`. 
Once provisioned the `seed.img` drive is ignored.  The `seed.img` drive can
safely be removed in subsequent runs but for simplicity I keep it.

When the Debian login prompt comes up, login with the user creds in
`user-data.yaml`. Use `bashlib.sh:qemu_guest_check` to verify some basic
functionality.

From there one possible step is entering the 
[QEMU Monitor](https://qemu-project.gitlab.io/qemu/system/monitor.html) and
query information about the block devices `(qemu) info block`.  You should see
two block devices: the guest OS formatted as `qcow2` device and the `seed.img`
formatted as a `raw` device.

The guest OS has an SSH server and a pubkey authentication configured in
`user-data.yaml` `ssh_authorized_keys` for `dave`.  Guest OS ssh access cannot
be performed from the host yet, only the docker container.

Summary
=======
This document describes a safe and clean methodology to set up and run the
QEMU emulator with an example guest OS.  It can serve as a template for
building more complex QEMU frameworks using heterogenous hardware or prototype
development on the guest OS.

Two features that I will investigate in the future are:

1. QEMU host volume mapping using
   [virtiofsd](https://gitlab.com/virtio-fs/virtiofsd) 
   (which appears to be moving to rust at the moment) or 
   [QEMU 9pfs](https://wiki.qemu.org/Documentation/9psetup).
   
2. SSH connection from the host directly into the QEMU guest OS.  Currently,
   SSH access must be from the docker container to the QEMU guest.
   
