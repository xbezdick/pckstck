#!/bin/bash
export LIBVIRT_DEFAULT_URI="qemu:///system"
export VM_TYPES="controller,compute1,compute2,network1"
. $(dirname $0)/include/tmppath.rc
. $(dirname $0)/include/virtpwn.rc
. $(dirname $0)/include/pckstck.sh

function usage()
{
  cat << EOF
  Usage:
    -h|--help
    -k|--keep                      Keep the created VMS, don't stop and delete them.
    -b|--packstack-branch <branch> Sets specific packstack branch to clone. Default: master
    -g|--packstack-git <url>       Sets packstack git url to clone.
                                   Default: https://github.com/stackforge/packstack.git
    -m|--opm-branch <branch>       Sets specific opm branch to clone. Default: branch set in packstack setup.py
    -o|--opm-git <url>             Sets opm git url to clone in setup.py. Default: url set in packstack setup.py
    -r|--repo <url>                Installs repo rpm from specified url. If unspecified no repo is used.
                                   Default: https://repos.fedorapeople.org/repos/openstack/openstack-juno/rdo-release-juno-1.noarch.rpm
    -n|--source-vms <vms>          Comma separated list of VMs to use for clonning.
                                   All tests run for each source VM.
    -d|--deploy <allinone,multi>   Comma separated list of deployment types to use. Multi node deployment will do
                                   Controller Network and 2*Compute. Default: allinone
    -p|--packstack-options <o=v;.> Semicollon separated packstack config options which will be set to packstack
                                   config file with sed.
    -x|--extra-node                Adds extra node to multinode deployment, if
                                   you need to pass config option with IP of
                                   this node use 'CONFIG=MAGIC_NODE'.
EOF
}

function echoerr()
{
cat <<< "$@" 1>&2
}

SHORTOPTS="htz6kxb::g::m::o::r::n:d::p:"
LONGOPTS="help,extra-node,packstack-branch::,packstack-git::,opm-branch::,opm-git::,repo::,source-vms:,keep,dns,test,ipv6,deploy::,packstack-options:"
PROGNAME=${0##*/}

ARGS=$(getopt -s bash --options $SHORTOPTS  \
  --longoptions $LONGOPTS -n $PROGNAME -- "$@" )


# default options
PACKSTACK_BRANCH='master'
PACKSTACK_GIT='https://github.com/stackforge/packstack.git'
KEEP_VMS=false
RALLY=false
TEST=false
USE_DNS=false
DEPLOY='allinone'
export IPV6=false

# options that can be empty
REPO=""
PACKSTACK_OPTIONS=""
OPM_BRANCH=""
OPM_GIT=""
# required options
VMS=""

# eval breaks parsing spaces before optional args
#eval set -- "$ARGS"
echo
while true; do
  case "${1}" in
    -h|--help)
      usage
      exit 0
      ;;
    -b|--packstack-branch)
      case "${2}" in
        ""|-*)
          echoerr "No branch specified. Using branch ${PACKSTACK_BRANCH}!" 
          ;;
        *) PACKSTACK_BRANCH="${2}" ; shift ;;
      esac
      ;;
    -g|--packstack-git)
      case "${2}" in
        ""|-*)
          echoerr "No packstack git url specified. Using ${PACKSTACK_GIT}!" 
          ;;
        *) PACKSTACK_GIT="${2}" ; shift ;;
      esac
      ;;
    -m|--opm-branch)
      case "${2}" in
        ""|-*)
          echoerr "No branch specified. Using branch from setup.py!" 
          ;;
        *) OPM_BRANCH="${2}" ; shift ;;
      esac
      ;;
    -o|--opm-git)
      case "${2}" in
        ""|-*)
          echoerr "No omp git url specified. Using url from setup.py!"
          ;;
        *) OPM_GIT="${2}" ; shift ;;
      esac
      ;;
    -r|--repo)
      case "${2}" in
        ""|-*)
          REPO='https://repos.fedorapeople.org/repos/openstack/openstack-juno/rdo-release-juno-1.noarch.rpm'
          echoerr "No repo rpm url specified. Using ${REPO}!" 
          ;;
        *) REPO="${2}" ; shift ;;
      esac
      ;;
    -x|--extra-node)
      VM_TYPES="${VM_TYPES},magic"
      ;;
    -6|--ipv6)
      export IPV6=true
      ;;
    -R|--rally)
      export RALLY=true
      ;;
    -t|--test)
      export TEST=true
      ;;
    -z|--dns)
      export USE_DNS=true
      ;;
    -k|--keep)
      export KEEP_VMS=true
      ;;
    -d|--deploy)
      case "${2}" in
        ""|-*)
          DEPLOY='allinone'
          echoerr "No deployment selected. Using ${REPO}!" 
          ;;
        *) DEPLOY="${2}" ; shift ;;
      esac
      ;;
    -p|--packstack-options)
      PACKSTACK_OPTIONS="$( echo ${2} | sed -E 's/[[:space:]]+/\;/g')"
      shift
      ;;
    -n|--source-vms)
      VMS="${2}"
      shift
      ;;
    --)
      break
      ;;
    *)
      break
      ;;
   esac
   shift
done

prepare_tmp_path || exit 1

if [ "${VMS}" == "" ]
then
  echoerr "No source VMs were specified, see README about preparing VMs"
  exit 1
else
  ALLINONE=false
  MULTI=false
  for deployment in ${DEPLOY//,/ }; do
    if [ "${deployment}" == "allinone" ]; then
      ALLINONE=true
    elif [ "${deployment}" == "multi" ]; then
      MULTI=true
    else
      echoerr "No such deployment ${deployment} possible."
      exit 1
    fi
  done

  if $TEST; then
    PACKSTACK_OPTIONS="${PACKSTACK_OPTIONS};CONFIG_PROVISION_TEMPEST=y"
    PACKSTACK_OPTIONS="${PACKSTACK_OPTIONS};CONFIG_PROVISION_TEMPEST_REPO_URI=https://github.com/redhat-openstack/tempest.git"
  fi

  if $ALLINONE; then
    for VM in ${VMS//,/ }; do
      prepare_allinone_vms "${VM}" && run_allinone "${VM}" "${PACKSTACK_GIT}" "${PACKSTACK_BRANCH}" "${OPM_GIT}" "${OPM_BRANCH}" "${REPO}" "${PACKSTACK_OPTIONS}" &
    done
  fi
  if $MULTI; then
    for VM in ${VMS//,/ }; do
      prepare_multinode_vms "${VM}" && run_multinode "${VM}" "${PACKSTACK_GIT}" "${PACKSTACK_BRANCH}" "${OPM_GIT}" "${OPM_BRANCH}" "${REPO}" "${PACKSTACK_OPTIONS}" &
    done
  fi
  wait

  if $TEST; then
    for VM in ${VMS//,/ }; do
      if $MULTI; then
        RUN setup_tempest_test "controller-${VM}" && RUN run_tempest_test "controller-${VM}" &
      fi
      if $ALLINONE; then
        RUN setup_tempest_test "allinone-${VM}" && RUN run_tempest_test "allinone-${VM}" &
      fi
    done
    wait
  fi

  if $RALLY; then
    if $MULTI; then
       for VM in ${VMS//,/ }; do
         if [[ ${VM_TYPES} == *"magic"* ]]; then
           RUN run_rally "magic-${VM}" "controller-${VM}" &
         else
           RUN run_rally "controller-${VM}" "controller-${VM}" &
         fi
       done
    fi
    wait
  fi

  # ensure we have local stored logs
  if $ALLINONE; then
    for VM in ${VMS//,/ }; do
      RUN collect_logs "allinone-${VM}" &
    done
  fi
  if $MULTI; then
    for VM in ${VMS//,/ }; do
      for vm_type in ${VM_TYPES//,/ }; do
        NAME="${vm_type}-${VM}"
        RUN collect_logs "${NAME}" &
      done
    done
  fi
  wait

  if $KEEP_VMS;
  then
   exit 0
  fi
  if $ALLINONE; then delete_allinone_vms "${VMS}"; fi
  if $MULTI; then delete_multinode_vms "${VMS}"; fi
fi

