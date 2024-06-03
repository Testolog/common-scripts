#!/usr/bin/env bash
source logging.sh


NOT_PROVIDED_CONN_SETTINGS=120
CONN_FAILED=3
NOT_EXISTS_QUERY_FILE=2

verbosity=5
function remote_execute(){
   debug "ssh ${SSH_HOST_PRESTO} $1"
   ssh ${SSH_HOST_PRESTO} -f $1
}


function ssh_presto_client() {
    #todo append uuid
    local query_path=$1
    local result_path=$2
    local file_name=$(basename ${query_path})
    if ! [[ -z result_path ]]; then
        result_path=$(dirname $(dirname ${query_path}))/result/${file_name}.csv
    fi
    local remote_path=/tmp/${file_name}
    local remote_out_path=/tmp/${file_name}.csv
    info "check connection to remote host"
    remote_execute "ls" 2>&1 > /dev/null && ! [[ $? -eq 0 ]] &&  error "connection was failed" && exit ${CONN_FAILED}
    info "load queries file to remote machine"
    scp ${query_path} ${SSH_HOST_PRESTO}:${remote_path}
    info "exists of remote queries"
    remote_execute "test -e ${remote_path}"
    ! [[ $? -eq 0 ]] && error "not exitst remote queries" &&  exit ${NOT_EXISTS_QUERY_FILE}
    info "execute of script"
    remote_execute "presto --execute \"$(cat ${query_path})\" --output-format CSV_HEADER > ${remote_out_path}"
    remote_execute "test -e ${remote_out_path}"
    ! [[ $? -eq 0 ]] && error "not exitst remote queries" &&  exit ${NOT_EXISTS_QUERY_FILE}
    scp ${SSH_HOST_PRESTO}:${remote_out_path} ${result_path}
    return ${running}
}


if [[ -z ${SSH_HOST_PRESTO} ]]; then
    echo "try to load env"
    source ~/env.sh
    if [[ -z ${SSH_HOST_PRESTO} ]]; then
        error "SSH_PORT_PRESTO and SSH_HOST_PRESTO are empty"
        exit ${NOT_PROVIDED_CONN_SETTINGS}
    else
        info "port ${SSH_PORT_PRESTO} and host ${SSH_HOST_PRESTO}"
    fi

fi

ssh_presto_client $1