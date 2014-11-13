#!/bin/bash
export LIBVIRT_DEFAULT_URI="qemu:///system"

. $(dirname $0)/include/tmppath.rc
. $(dirname $0)/include/virtpwn.rc

# function logging wrapper expecting human readable function name and instance name as $1 and $2
function RUN()
{
  COMMAND=${1}
  NAME=${2}
  mkdir -p ${PCKSTCK_DIR}/${NAME}
  echo "Runnning ${COMMAND} on ${NAME} ..."
  "$@" > ${PCKSTCK_DIR}/${NAME}/${COMMAND}.log 2>&1
  ret=$?
  if [[ $ret -eq 0 ]]
  then
    echo "Success - ${COMMAND} on ${NAME}."
  else
    echo "FAIL - ${COMMAND} on ${NAME}."
  fi
  return $ret
}

function install_repo_on_vm()
{
  NAME=${1}
  RPM_REPO_URL=${2}
  cd ${PCKSTCK_DIR}/${NAME}
  IP=$(get_vm_ip ${NAME})
  ssh "root@${IP}" "yum -y install ${RPM_REPO_URL}"
}

function update_vm()
{
  NAME=${1}
  cd ${PCKSTCK_DIR}/${NAME}
  IP=$(get_vm_ip ${NAME})
  ssh "root@${IP}" 'yum clean all; yum -y update'
}

function selinux_permissive_vm()
{
  NAME=${1}
  cd ${PCKSTCK_DIR}/${NAME}
  IP=$(get_vm_ip ${NAME})
  ssh "root@${IP}" 'setenforce 0; sed -i -e "s/enforcing/permissive/" /etc/sysconfig/selinux' && \
  ssh "root@${IP}" 'yum -y install policycoreutils-python auditd' && \
  ssh "root@${IP}" 'service auditd restart'
}

function setup_packstack()
{
  NAME=${1}
  PACKSTACK_URI=${2}
  PACKSTACK_BRANCH=${3}
  OPM_URI="${4%*/openstack-puppet-modules.git}/"
  OPM_BRANCH=${5}
  echo ${OPM_URI}
  cd ${PCKSTCK_DIR}/${NAME}
  IP=$(get_vm_ip ${NAME})
  ssh "root@${IP}" 'yum -y install git PyYAML python-setuptools' && \
  ssh "root@${IP}" "git clone ${PACKSTACK_URI} packstack" && \
  ssh "root@${IP}" "cd packstack; git checkout ${PACKSTACK_BRANCH}" && \
  ssh "root@${IP}" "sed -i -e 's,^MODULES_REPO.*$,MODULES_REPO = ('\''${OPM_URI}'\'',' packstack/setup.py" && \
  ssh "root@${IP}" "sed -i -e 's/^MODULES_BRANCH.*$/MODULES_BRANCH = '\''${OPM_BRANCH}'\''/' packstack/setup.py" && \
  ssh "root@${IP}" "cd packstack; python setup.py install_puppet_modules" && \
  ssh "root@${IP}" "cd packstack; python setup.py install"
}

function configure_packstack()
{
  NAME=${1}
  cd ${PCKSTCK_DIR}/${NAME}
  IP=$(get_vm_ip ${NAME})
  ssh "root@${IP}" "packstack --gen-answer-file=/root/pckstck.conf"
}

function run_packstack_config()
{
  NAME=${1}
  CONFIG=${2}
  cd ${PCKSTCK_DIR}/${NAME}
  IP=$(get_vm_ip ${NAME})
  ssh "root@${IP}" "packstack -d --answer-file=${CONFIG}"
}

function run_allinone()
{
  NAME=${1}
  SOURCE_VM=${2}
  PACKSTACK_URI=${3}
  PACKSTACK_BRANCH=${4}
  OPM_URI=${5}
  OPM_BRANCH=${6}
  RPM_REPO_URL=${7}
  if [ "${RPM_REPO_URL}" != "" ]
  then
    RUN install_repo_on_vm ${NAME} ${RPM_REPO_URL} || return 1
  fi
  RUN update_vm ${NAME} && \
  RUN selinux_permissive_vm ${NAME} && \
  RUN setup_packstack ${NAME} ${PACKSTACK_URI} ${PACKSTACK_BRANCH} ${OPM_URI} ${OPM_BRANCH} && \
  RUN configure_packstack ${NAME} && \
  RUN run_packstack_config ${NAME} /root/pckstck.conf | tee ${PCKSTCK_DIR}/${NAME}/packstack.log && \
  RUN run_packstack_config ${NAME} /root/pckstck.conf | tee ${PCKSTCK_DIR}/${NAME}/packstack2.log

  # ensure we have local stored logs
  RUN collect_logs ${NAME}
}

function allinone()
{
  SOURCE_VMS=${1}
  PACKSTACK_URI=${2}
  PACKSTACK_BRANCH=${3}
  OPM_URI=${4}
  OPM_BRANCH=${5}
  RPM_REPO_URL=${6}
  for vm in ${SOURCE_VMS//,/ }; do
    RUN prepare_virtpwn_vm "allinone-${vm}" "${vm}" && \
    RUN run_virtpwn_vm "allinone-${vm}"
  done
  for vm in ${SOURCE_VMS//,/ }; do
    run_allinone "allinone-${vm}" "${vm}" \
		"${PACKSTACK_URI}" "${PACKSTACK_BRANCH}" \
		"${OPM_URI}" "${OPM_BRANCH}" \
		"${RPM_REPO_URL}" &
  done
  wait
  if $KEEP_VMS;
  then
   exit 0
  fi
  for vm in ${SOURCE_VMS//,/ }; do
    RUN stop_virtpwn_vm "allinone-${vm}"
    RUN drop_virtpwn_vm "allinone-${vm}"
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
    -m|--opm-branch <branch>       Sets specific opm branch to clone. Default: master
    -o|--opm-git <url>             Sets opm git url to clone in setup.py.
                                   Default: https://github.com/redhat-openstack/openstack-puppet-modules.git
    -r|--repo <url>                Installs repo rpm from specified url. If unspecified no repo is used.
                                   Default: https://repos.fedorapeople.org/repos/openstack/openstack-juno/rdo-release-juno-1.noarch.rpm
    -n|--source-vms <vms>          Comma separated list of VMs to use for clonning.
                                   All tests run for each source VM.
EOF
}

function echoerr()
{
cat <<< "$@" 1>&2
}

SHORTOPTS="hkb::g::m::o::r::n:"
LONGOPTS="help,packstack-branch::,packstack-git::,opm-branch::,opm-git::,repo::,source-vms:,keep"
PROGNAME=${0##*/}

ARGS=$(getopt -s bash --options $SHORTOPTS  \
  --longoptions $LONGOPTS -n $PROGNAME -- "$@" )


# default options
PACKSTACK_BRANCH='master'
PACKSTACK_GIT='https://github.com/stackforge/packstack.git'
OPM_BRANCH='master'
OPM_GIT='https://github.com/redhat-openstack/openstack-puppet-modules.git'

# options that can be empty
REPO=""

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
    -k|--keep)
      export KEEP_VMS=true
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
allinone "${VMS}" "${PACKSTACK_GIT}" "${PACKSTACK_BRANCH}" "${OPM_GIT}" "${OPM_BRANCH}" "${REPO}"
fi

