install
bootloader --location=mbr
rootpw --plaintext testpasswd
timezone --utc America/New_York
text
poweroff
lang en_US.UTF-8
keyboard us
network --bootproto dhcp
firewall --enabled --ssh
firstboot --disable
selinux --permissive
zerombr
shutdown
clearpart --all --initlabel
autopart
auth --enableshadow --passalgo=sha512

%packages --default

kernel*
dracut-*
bzip2*
yum
@anaconda-tools
%end
