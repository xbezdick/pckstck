#!/bin/bash

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
  virt-customize -d ${NAME} --update --selinux-relabel --run-command 'sed -i -e "s/enforcing/permissive/" /etc/sysconfig/selinux'
  virt-sysprep \
	--hostname ${NAME} \
	--enable "customize,logfiles,net-hostname,net-hwaddr,puppet-data-log,udev-persistent-net" \
	-d ${NAME}
}

prepare_vm "f21" "https://dl.fedoraproject.org/pub/fedora/linux/releases/test/21-Alpha/Server/x86_64/os/" 
prepare_vm "f20" "https://dl.fedoraproject.org/pub/fedora/linux/releases/20/Fedora/x86_64/os/"
prepare_vm "c7" "http://merlin.fit.vutbr.cz/mirrors/centos/7.0.1406/os/x86_64/"
