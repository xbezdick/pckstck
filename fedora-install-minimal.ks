# Kickstart file for composing the "Fedora Cloud" spin of Fedora (rawhide)
# Maintained by the Fedora Release Engineering team:
# https://fedoraproject.org/wiki/ReleaseEngineering
# mailto:rel-eng@lists.fedoraproject.org

# Use a part of 'iso' to define how large you want your isos.
# Only used when composing to more than one iso.
# Default is 695 (megs), CD size.
# Listed below is the size of a DVD if you wanted to split higher.
#part iso --size=4998

# Add the repos you wish to use to compose here.  At least one of them needs group data.
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

# Only uncomment repo commands in one of the two following sections.
# Because the install kickstart doesn't use the updates repo and does 
# use the source repo, we can't just include fedora-repo.ks

# In the master branch the rawhide repo commands should be uncommented.
#repo --name=rawhide --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=rawhide&arch=$basearch
#repo --name=rawhide-source  --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=rawhide-source&arch=$basearch

# In non-master branches the fedora repo commands should be uncommented
#repo --name=fedora --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=fedora-$releasever&arch=$basearch
#repo --name=fedora-source  --mirrorlist=http://mirrors.fedoraproject.org/mirrorlist?repo=fedora-source-$releasever&arch=$basearch

# Package manifest for the compose.  Uses repo group metadata to translate groups.
# (default groups for the configured repos are added by --default)
# @base got renamed to @standard, but @base is still included by default by pungi.
%packages --default

# pungi is an inclusive depsolver so that multiple packages are brought 
# in to satisify dependencies and we don't always want that. So we  use
# an exclusion list to cut out things we don't want

-kernel*xen*
-kernel*debug*
-kernel-kdump*
-kernel-tools*
-syslog-ng*
-astronomy-bookmarks
# generic* would match generic-jms-ra, so don't 'simplify' this
-generic-logos*
-generic-release*
-GConf2-dbus*
-bluez-gnome
-community-mysql*
# jruby used to be in this list, but springframework-context explicitly
# requires it, not just 'any ruby implemention' - please check for things
# on the image that require mvn(org.jruby:jruby) before adding jruby to
# this list again - adamw 2014/09
#-jruby

# core
kernel*
dracut-*
bzip2*
yum
auditd

# Things needed for installation
@anaconda-tools

-gimp-help-*

# Removals
-PackageKit-zif
-zif
%end
