#!/bin/bash
set -e
NOT_PROVIDED_CONN_SETTINGS=120
CONN_FAILED=3
NOT_EXISTS_QUERY_FILE=2

if [[ -n ~/env.sh ]]; then
  # shellcheck disable=SC1090
  source ~/env.sh
fi
# shellcheck source=../logging.sh
source "${COMMON_SCRIPTS}"/logging.sh

if [[ -z ${SSH_HOST_PRESTO} ]]; then
  error "SSH_PORT_PRESTO and SSH_HOST_PRESTO are empty"
  exit ${NOT_PROVIDED_CONN_SETTINGS}
else
  info "port ${SSH_PORT_PRESTO} and host ${SSH_HOST_PRESTO}"
fi

export verbosity=5
function remote_execute() {
  debug "ssh ${SSH_HOST_PRESTO} $1"
  ssh -P "${SSH_PORT_PRESTO}" "${SSH_HOST_PRESTO}" "$1"
}

function ssh_presto_client() {
  #todo append uuid
  local query_path=$1
  local result_path=$2
  local query_file_name=$(basename ${query_path} | cut -f1 -d.)
  local result_file_name=$(date '+%Y_%d_%m_%H_%M_%S').csv
  if [[ -n result_path ]]; then
    mkdir -p $(dirname $(dirname ${query_path}))/result/${query_file_name}
    result_path=$(dirname $(dirname ${query_path}))/result/${query_file_name}/${result_file_name}
  fi
  local remote_query_path=/tmp/${query_file_name}
  local remote_out_path=/tmp/${result_file_name}
  info "check connection to remote host"
  if ! remote_execute "ls" > /dev/null 2>&1
  then
    error "connection was failed"
    exit ${CONN_FAILED}
  fi
  info "load queries file to remote machine"
  scp "${query_path}" "${SSH_HOST_PRESTO}":"${remote_query_path}"
  info "exists of remote queries"
  remote_execute "test -e ${remote_query_path}"
  ! [[ $? -eq 0 ]] && error "not exitst remote queries" && exit ${NOT_EXISTS_QUERY_FILE}
  info "execute of script"

  remote_execute "presto -f ${remote_query_path} --schema ${PRESTO_SILVER} --output-format CSV_HEADER > ${remote_out_path}"
  remote_execute "test -e ${remote_out_path}"
  ! [[ $? -eq 0 ]] && error "not exitst remote queries" && exit ${NOT_EXISTS_QUERY_FILE}
  scp "${SSH_HOST_PRESTO}":"${remote_out_path}" "${result_path}"
  #    return ${running}
}

ssh_presto_client $1 $2
