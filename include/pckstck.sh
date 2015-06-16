#!/bin/bash
function run_rally()
{
  NAME=${1}
  CONTROLLER=${2}
  cd ${PCKSTCK_DIR}/${NAME}
  IP=$(get_vm_ip ${NAME})
  CONTROLLERIP=$(get_vm_ip ${CONTROLLER})
  ADMIN="$(ssh root@${CONTROLLERIP} 'cat keystonerc_admin')"
  ssh "root@${IP}" 'yum -y install git'
  ssh "root@${IP}" 'git clone https://github.com/stackforge/rally.git' && \
#  ssh "root@${IP}" 'cd rally && sed -i -e "s/cirros\(.*\)uec/cirros\1/" $( git grep -l cirros.*uec )' && \
#  ssh "root@${IP}" 'cd rally && sed -i -e "s/size: 10/size: 1/" $( git grep -l "size: 10" )' && \
#  ssh "root@${IP}" 'cd rally && sed -i -e "s/size\": 10/size\": 1/" $( git grep -l "size\": 10" )' && \
  ssh "root@${IP}" 'sh rally/install_rally.sh' && \
  ssh "root@${IP}" "cat <<EOF > keystonerc_admin
${ADMIN}
EOF" && \
  ssh "root@${IP}" '. keystonerc_admin ; rally deployment create --fromenv --name=existing' && \
  ssh "root@${IP}" '. keystonerc_admin ; nova flavor-create m1.nano 42 64 0 1' && \
#  ssh "root@${IP}" 'rally show images ; rally show flavors' && \
#  ssh "root@${IP}" 'for task in rally/samples/tasks/scenarios/{keystone,nova,neutron,glance,cinder,ceilometer}/*.yaml; do OUT="$(cat ${task})" ; number_of_occurrences=$(grep -o " " <<< "$(head -n2 ${task} | grep -v -- ---)"|wc -l) ; for i in $(seq 1 $number_of_occurrences); do OUT=$(echo "${OUT}" | sed  -e "s/^ //")  ; done ; echo "${OUT}"   ; done  | grep -v -- --- > pckstck.yaml' && \
  ssh "root@${IP}" 'rally verify start '
#  ssh "root@${IP}" 'rally -v task start pckstck.yaml' && \
#  ssh "root@${IP}" 'rally task report --out=pckstck.html --open' && \
#  ssh "root@${IP}" 'cat pckstck.html' > pckstck.html
}

function get_vm_packstack_ip()
{
  NAME=${1}
  IP=$(get_vm_ip ${NAME})
  if $IPV6; then
    IP=$(ssh "root@${IP}" "ip a  | grep inet6 | grep global | grep dynamic | awk '{print \$2}' | cut -d '/' -f1")
  fi
  echo ${IP}
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
      RUN prepare_virtpwn_vm "${vm_type}-${vm}" "${vm}" && \
      RUN run_virtpwn_vm "${vm_type}-${vm}" || return 1 &
    done
  done
  wait
  for vm in ${SOURCE_VMS//,/ }; do
    for vm_type in ${VM_TYPES//,/ }; do
      RUN provision_virtpwn_vm "${vm_type}-${vm}" || return 1 &
    done
  done
  wait
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
    RUN run_virtpwn_vm "allinone-${vm}" || return 1 &
  done
  wait
  for vm in ${SOURCE_VMS//,/ }; do
    RUN provision_virtpwn_vm "allinone-${vm}" || return 1 &
  done
  wait
}

function install_repo_on_vm()
{
  NAME=${1}
  RPM_REPO_URL=${2}
  cd ${PCKSTCK_DIR}/${NAME}
  IP=$(get_vm_ip ${NAME})
  for repo in ${RPM_REPO_URL//,/ }; do
    if [[ ${repo} == *.rpm ]]; then
      ssh "root@${IP}" "yum -y install ${repo}" || ssh "root@${IP}" "yum -y install ${repo}"
    elif [[ ${repo} == *.repo ]]; then
      ssh "root@${IP}" "curl \"${repo}\" > /etc/yum.repos.d/pckstck.repo"
    fi
  done
}

function update_vm()
{
  NAME=${1}
  cd ${PCKSTCK_DIR}/${NAME}
  IP=$(get_vm_ip ${NAME})
  ssh "root@${IP}" 'yum clean all; yum -y update' || ssh "root@${IP}" 'yum clean all; yum -y update'
}

function selinux_permissive_vm()
{
  NAME=${1}
  cd ${PCKSTCK_DIR}/${NAME}
  IP=$(get_vm_ip ${NAME})
  ssh "root@${IP}" 'setenforce 0; sed -i -e "s/enforcing/permissive/" /etc/sysconfig/selinux' && \
  ssh "root@${IP}" 'service auditd restart'
}

function setup_packstack()
{
  NAME=${1}
  PACKSTACK_URI=${2}
  PACKSTACK_BRANCH=${3}
  OPM_URI="${4}"
  OPM_BRANCH=${5}
  echo ${OPM_URI}
  cd ${PCKSTCK_DIR}/${NAME}
  IP=$(get_vm_ip ${NAME})
  ssh "root@${IP}" 'yum -y install git PyYAML python-setuptools python-netaddr pyOpenSSL' && \
  ssh "root@${IP}" "git clone ${PACKSTACK_URI} packstack" && \
  ssh "root@${IP}" "cd packstack; git checkout ${PACKSTACK_BRANCH}" || return 1
  if [ "${OPM_URI}" != "" ]; then
    OPM_URI="${4%*/openstack-puppet-modules.git}/"
    ssh "root@${IP}" "sed -i -e 's,^MODULES_REPO.*$,MODULES_REPO = ('\''${OPM_URI}'\'',' packstack/setup.py" || return 1
  fi
  if [ "${OPM_BRANCH}" != "" ]; then
    ssh "root@${IP}" "sed -i -e 's/^MODULES_BRANCH.*$/MODULES_BRANCH = '\''${OPM_BRANCH}'\''/' packstack/setup.py" || return 1
  fi
  ssh "root@${IP}" "cd packstack; python setup.py install_puppet_modules" && \
  ssh "root@${IP}" "cd packstack; python setup.py install"
}

function configure_packstack()
{
  NAME=${1}
  PACKSTACK_OPTIONS=${2}
  cd ${PCKSTCK_DIR}/${NAME}
  IP=$(get_vm_ip ${NAME})
  DEFAULT_PASS=$(echo ${PACKSTACK_OPTIONS} | sed -e 's/;/\n/g' | grep CONFIG_DEFAULT_PASSWORD | cut -f2 -d'=')
  ssh "root@${IP}" "packstack --gen-answer-file=/root/pckstck.conf --default-password=${DEFAULT_PASS}" && \
  for config in ${PACKSTACK_OPTIONS//;/ }; do
    OPT=$(echo ${config} | cut -f1 -d'=')
    VAL=$(echo ${config} | cut -f2 -d'=')
    if [ "${OPT}" != "" ] && [ "${VAL}" != "" ]; then
      ssh "root@${IP}" "sed -i -e 's;^${OPT}.*$;${OPT}=${VAL};' /root/pckstck.conf" || return 1
    fi
  done
  CONFIG_CONTROLLER_IP=$(get_vm_packstack_ip ${NAME})
  ssh "root@${IP}" "sed -i -e 's;${IP};${CONFIG_CONTROLLER_IP};' /root/pckstck.conf" || return 1
  # print config to output
  ssh "root@${IP}" "cat /root/pckstck.conf"
}

function run_packstack_config()
{
  NAME=${1}
  CONFIG=${2}
  cd ${PCKSTCK_DIR}/${NAME}
  IP=$(get_vm_ip ${NAME})
  ssh "root@${IP}" "packstack -d --answer-file=${CONFIG}"
}

function prepare_node()
{
  NAME=${1}
  RPM_REPO_URL=${2}
  if [ "${RPM_REPO_URL}" != "" ]
  then
    RUN install_repo_on_vm "${NAME}" "${RPM_REPO_URL}" || return 1
  fi
  RUN update_vm "${NAME}" && \
  RUN selinux_permissive_vm "${NAME}"
}

function run_controller()
{
  NAME=${1}
  PACKSTACK_URI=${2}
  PACKSTACK_BRANCH=${3}
  OPM_URI=${4}
  OPM_BRANCH=${5}
  PACKSTACK_OPTIONS=${6}
  RUN setup_packstack "${NAME}" "${PACKSTACK_URI}" "${PACKSTACK_BRANCH}" "${OPM_URI}" "${OPM_BRANCH}" && \
  RUN configure_packstack "${NAME}" "${PACKSTACK_OPTIONS}" && \
  RUN run_packstack_config "${NAME}" /root/pckstck.conf | tee ${PCKSTCK_DIR}/${NAME}/packstack.log && \
  RUN run_packstack_config "${NAME}" /root/pckstck.conf | tee ${PCKSTCK_DIR}/${NAME}/packstack2.log
}

function run_allinone()
{
  SOURCE_VM=${1}
  PACKSTACK_URI=${2}
  PACKSTACK_BRANCH=${3}
  OPM_URI=${4}
  OPM_BRANCH=${5}
  RPM_REPO_URL=${6}
  PACKSTACK_OPTIONS=${7}
  IP=$(get_vm_packstack_ip allinone-${vm})
  PACKSTACK_OPTIONS="${PACKSTACK_OPTIONS//MAGIC_NODE/${IP%*,}}"
  for vm in ${SOURCE_VMS//,/ }; do
    prepare_node "allinone-${vm}" "${RPM_REPO_URL}" && \
    run_controller "allinone-${vm}" "${PACKSTACK_URI}" "${PACKSTACK_BRANCH}" \
	"${OPM_URI}" "${OPM_BRANCH}" &
  done
  wait
}

function run_multinode()
{
  SOURCE_VM=${1}
  PACKSTACK_URI=${2}
  PACKSTACK_BRANCH=${3}
  OPM_URI=${4}
  OPM_BRANCH=${5}
  RPM_REPO_URL=${6}
  PACKSTACK_OPTIONS=${7}
  for vm in ${SOURCE_VMS//,/ }; do
    for vm_type in ${VM_TYPES//,/ }; do
      prepare_node "${vm_type}-${vm}" "${RPM_REPO_URL}" &
    done
  done
  wait
  for vm in ${SOURCE_VMS//,/ }; do
    CONTROLLER=""
    COMPUTE=""
    NETWORK=""
    MAGIC=""
    for vm_type in ${VM_TYPES//,/ }; do
      NAME="${vm_type}-${vm}"
      cd ${PCKSTCK_DIR}/${NAME}
      IP=$(get_vm_packstack_ip ${NAME})
      echo "${vm_type}" | grep -q "controller" && CONTROLLER="${IP},"
      echo "${vm_type}" | grep -q "compute*" && COMPUTE="${COMPUTE}${IP},"
      echo "${vm_type}" | grep -q "network*" && NETWORK="${NETWORK}${IP},"
      echo "${vm_type}" | grep -q "magic*" && MAGIC="${MAGIC}${IP},"
    done
    if  [ "${CONTROLLER}" != "" ] && [ "${COMPUTE}" != "" ] && [ "${NETWORK}" != "" ]; then
      PACKSTACK_OPTIONS="${PACKSTACK_OPTIONS//MAGIC_NODE/${MAGIC%*,}}"
      PACKSTACK_OPTIONS="${PACKSTACK_OPTIONS};CONFIG_CONTROLLER_HOST=${CONTROLLER%*,}"
      PACKSTACK_OPTIONS="${PACKSTACK_OPTIONS};CONFIG_NETWORK_HOSTS=${NETWORK%*,}"
      PACKSTACK_OPTIONS="${PACKSTACK_OPTIONS};CONFIG_COMPUTE_HOSTS=${COMPUTE%*,}"
      run_controller "controller-${vm}" "${PACKSTACK_URI}" "${PACKSTACK_BRANCH}" \
	"${OPM_URI}" "${OPM_BRANCH}" "${PACKSTACK_OPTIONS}" &
    else
      echoerr "Something went wrong with setting up nodes"
      exit 1
    fi
  done
  wait
}

