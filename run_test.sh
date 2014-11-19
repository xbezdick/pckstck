#!/bin/bash
export LIBVIRT_DEFAULT_URI="qemu:///system"
export VM_TYPES="controller,compute1,compute2,network"
. $(dirname $0)/include/tmppath.rc
. $(dirname $0)/include/virtpwn.rc
. $(dirname $0)/include/pckstck.rc

# function logging wrapper expecting human readable function name and instance name as $1 and $2
function RUN()
{
  COMMAND=${1}
  NAME=${2}
  mkdir -p ${PCKSTCK_DIR}/${NAME}
  echo "Runnning ${COMMAND} on ${NAME} ..."
  "$@" >> ${PCKSTCK_DIR}/${NAME}/${COMMAND}.log 2>&1
  ret=$?
  if [[ $ret -eq 0 ]]
  then
    echo "Success - ${COMMAND} on ${NAME}."
  else
    echo "FAIL - ${COMMAND} on ${NAME}."
  fi
  return $ret
}

function delete_multinode_vms()
{
  SOURCE_VMS=${1}
  for vm in ${SOURCE_VMS//,/ }; do
    for vm_type in ${VM_TYPES//,/ }; do
      RUN stop_virtpwn_vm "${vm_type}-${vm}"
      RUN drop_virtpwn_vm "${vm_type}-${vm}"
    done
  done
}

function prepare_multinode_vms()
{
  SOURCE_VMS=${1}
  for vm in ${SOURCE_VMS//,/ }; do
    for vm_type in ${VM_TYPES//,/ }; do
      RUN prepare_virtpwn_vm "${vm_type}-${vm}" "${vm}" || return 1
      RUN run_virtpwn_vm "${vm_type}-${vm}" || return 1
    done
  done
}

function delete_allinone_vms()
{
  SOURCE_VMS=${1}
  for vm in ${SOURCE_VMS//,/ }; do
    RUN stop_virtpwn_vm "allinone-${vm}"
    RUN drop_virtpwn_vm "allinone-${vm}"
  done
}

function prepare_allinone_vms()
{
  SOURCE_VMS=${1}
  for vm in ${SOURCE_VMS//,/ }; do
    RUN prepare_virtpwn_vm "allinone-${vm}" "${vm}" && \
    RUN run_virtpwn_vm "allinone-${vm}"
  done
}

function usage()
{
  cat << EOF
  Usage:
    -h|--help
    -k|--keep                      Keep the created VMS, don't stop and delete them.
    -b|--packstack-branch <branch> Sets specific packstack branch to clone. Default: master
    -g|--packstack-git <url>       Sets packstack git url to clone.
                                   Default: https://github.com/stackforge/packstack.git
    -m|--opm-branch <branch>       Sets specific opm branch to clone. Default: master-patches
    -o|--opm-git <url>             Sets opm git url to clone in setup.py.
                                   Default: https://github.com/redhat-openstack/openstack-puppet-modules.git
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

SHORTOPTS="hkxb::g::m::o::r::n:d::p:"
LONGOPTS="help,extra-node,packstack-branch::,packstack-git::,opm-branch::,opm-git::,repo::,source-vms:,keep,deploy::,packstack-options:"
PROGNAME=${0##*/}

ARGS=$(getopt -s bash --options $SHORTOPTS  \
  --longoptions $LONGOPTS -n $PROGNAME -- "$@" )


# default options
PACKSTACK_BRANCH='master'
PACKSTACK_GIT='https://github.com/stackforge/packstack.git'
OPM_BRANCH='master-patches'
OPM_GIT='https://github.com/redhat-openstack/openstack-puppet-modules.git'
KEEP_VMS=false
DEPLOY='allinone'

# options that can be empty
REPO=""
PACKSTACK_OPTIONS=""
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
          echoerr "No branch specified. Using branch ${OPM_BRANCH}!" 
          ;;
        *) OPM_BRANCH="${2}" ; shift ;;
      esac
      ;;
    -o|--opm-git)
      case "${2}" in
        ""|-*)
          echoerr "No omp git url specified. Using ${OPM_GIT}!"
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
      PACKSTACK_OPTIONS="${2}"
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
  if $ALLINONE; then prepare_allinone_vms "${VMS}"; fi && \
  if $MULTI; then prepare_multinode_vms "${VMS}"; fi && \
  if $ALLINONE; then run_allinone "${VMS}" "${PACKSTACK_GIT}" "${PACKSTACK_BRANCH}" "${OPM_GIT}" "${OPM_BRANCH}" "${REPO}" "%{PACKSTACK_OPTIONS}" & fi
  if $MULTI; then prepare_multinode_vms "${VMS}" && run_multinode "${VMS}" "${PACKSTACK_GIT}" "${PACKSTACK_BRANCH}" "${OPM_GIT}" "${OPM_BRANCH}" "${REPO}" "${PACKSTACK_OPTIONS}" & fi
  wait
  if $KEEP_VMS;
  then
   exit 0
  fi
  if $ALLINONE; then delete_allinone_vms "${VMS}"; fi
  if $MULTI; then delete_multinode_vms "${VMS}"; fi
fi

