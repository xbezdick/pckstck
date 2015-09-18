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
	--ram 4096 \
	--disk size=25 \
	--location ${LOCATION} \
	--nographics \
	--noreboot \
        || exit 1
  virt-customize -d ${NAME} \
        --run-command 'sed -i -e "s/enforcing/permissive/" /etc/sysconfig/selinux' \
        --run-command 'dracut --force /boot/initramfs-$(uname -r).img $(uname -r)' \
        --update
  virt-sysprep \
	--hostname ${NAME} \
	--enable "customize,logfiles,net-hostname,net-hwaddr,puppet-data-log,udev-persistent-net" \
	-d ${NAME}
}

#prepare_vm "rawhide" "http://ftp.upjs.sk/pub/fedora/linux/development/rawhide/x86_64/os/"
#prepare_vm "f23" "http://ftp.upjs.sk/pub/fedora/linux/development/23/x86_64/os/"
prepare_vm "c7" "http://merlin.fit.vutbr.cz/mirrors/centos/7/os/x86_64/"
#prepare_vm "rhel7" "http://download.eng.rdu2.redhat.com/rel-eng/RHEL-7.1-20150219.1/compose/Server/x86_64/os/"
prepare_vm "f22" "http://ftp.upjs.sk/pub/fedora/linux/releases/22/Server/x86_64/os/"
