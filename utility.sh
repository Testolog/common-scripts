#!/usr/bin/env bash

function ssh_presto_client() {
    #todo append uuid
    local query_path=$1
    local file_name=$(basename ${query_path})
    local remote_path=/tmp/${file_name}
    local remote_out_path=/tmp/${file_name}.csv

    scp  -P ${SSH_PORT_PRESTO} ${query_path} ${SSH_HOST_PRESTO}:/tmp/$(basename ${query_path})
    local running=$( { ssh  -D ${SSH_PORT_PRESTO} ${SSH_HOST_PRESTO} 'ssh_presto_server ${remote_path} ${remote_out_path}' } > /dev/null )
    scp  -P ${SSH_PORT_PRESTO} ${SSH_HOST_PRESTO}:/tmp/$(basename ${query_path})

    return ${running}
}


function ssh_presto_server() {
    local query_path=$1
    local out_path=$2
    local running=$(presto -f ${query_path} --output-format CSV_HEADER > ${out_path})
    return ${running}
}