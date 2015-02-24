#!/bin/bash -x

# ensure system libvirt connection is used,
# if this is continually asking for pass create libvirt polkit rule for your self
# see for example /etc/polkit-1/rules.d/50-nova.rules and /etc/polkit-1/localauthority/50-local.d/50-nova.pkla
export LIBVIRT_DEFAULT_URI="qemu:///system"

# requires:
# NAME - vm name
# LOCATION - netinstall url
function prepare_vm()
{
  NAME=${1}
  LOCATION=${2}
  virsh desc ${NAME} || virt-install \
	--initrd-inject=./fedora-install-minimal.ks \
        -x "ks=file:/fedora-install-minimal.ks console=tty0 console=ttyS0,115200" \
	--name ${NAME} \
	--ram 2048 \
	--disk size=10 \
	--location ${LOCATION} \
	--nographics \
	--noreboot \
        || exit 1
  virt-customize -d ${NAME} --update \
        --run-command 'sed -i -e "s/enforcing/permissive/" /etc/sysconfig/selinux' \
        --run-command 'dracut --force /boot/initramfs-$(uname -r).img $(uname -r)'
  virt-sysprep \
	--hostname ${NAME} \
	--enable "customize,logfiles,net-hostname,net-hwaddr,puppet-data-log,udev-persistent-net" \
	-d ${NAME}
}

prepare_vm "f22" "http://ftp-stud.hs-esslingen.de/pub/fedora/linux/development/22/x86_64/os/"
prepare_vm "f21" "http://mirror.karneval.cz/pub/linux/fedora/linux/releases/21/Server/x86_64/os/"
prepare_vm "f20" "http://mirror.karneval.cz/pub/linux/fedora/linux/releases/20/Fedora/x86_64/os/"
prepare_vm "c7" "http://merlin.fit.vutbr.cz/mirrors/centos/7.0.1406/os/x86_64/"
