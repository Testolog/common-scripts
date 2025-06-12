#!/usr/bin/env bash
source ~/common-scripts/logging.sh
verbosity=4

function exists { which $1 &> /dev/null }

function mem() {
  vm_stat | perl -ne '/page size of (\d+)/ and $size=$1; /Pages\s+([^:]+)[^\d]+(\d+)/ and printf("%-16s % 16.2f Mi\n", "$1:", $2 * $size / 1048576);'
}

#todo optimize
function remove_docker_images() {
  _images=()
  while IFS='' read -r line; do _images+=("$line"); done < <(docker images | awk '{print $3}')
  for img in "${_images[@]:1}"; do
    echo "$img"
    docker rmi -f "$img"
  done
}
function history_memory(){
    PROCESS=()
    while IFS='' read -r r; do PROCESS+=("$r"); done < <(ps -A -o "pid,ppid,%cpu,%mem,comm" | awk ' {OFS=","; print $1,$2,$3,$4,$5 }')
    echo "${#PROCESS[*]}"

    for row in "${PROCESS[@]:1}"; do
      splitarray=()
      while IFS= read -r r; do splitarray+=("$r"); done < <(echo "${row//,/\n}")
      pid=${splitarray[1]}
      ppid=${splitarray[2]}
      cpu=${splitarray[3]}
      mem=${splitarray[4]}
      comm=${splitarray[5]}
      if (($cpu > 10)); then
        echo "${row}"
        echo "$pid", "$comm"
      fi
    done

}

function stop_all_container_docker() {
  _containers=()
  while IFS='' read -r line; do _containers+=("$line"); done < <(docker ps | awk '{print $1}')
  echo
  for cont in "${_containers[@]:1}"; do
    docker stop $cont
  done
}

function md2pdf() {
  if (($# != 2)); then
    echo "Usage: md2pdf <input.md> <output.pdf>"
    exit 1
  fi
  markdown $1 | htmldoc --cont --headfootsize 8.0 --linkcolor blue --linkstyle plain --format pdf14 - >$2
}

function use() {
    function show(){
        echo "availible profiles:" 
        ls -1 $profiles | grep ".*\\.sh" | cut -d "." -f 1
    }
    name=$1
    profiles=~/profiles
    if [ ! -d $profiles ]; then
        echo "profiles dir don't exists"
        return 1
    fi
    if [[ -z $name ]]; then
        echo "require a existsed env profile"
        size=$(ls -1 $profiles | grep ".*\\.sh$" | wc -l)
        if [ 0 -eq $size ]; then
            echo "no profile existed"
            return 1
        fi
        show
        return 0
    fi
    if [ ! -e "$profiles/$name.sh" ]; then
        echo " '$name' doesn't exists"
        size=$(ls -1 $profiles | grep ".*\\.sh$" | wc -l)
        if [ 0 -eq $size ]; then
            echo "no profile existed"
            return 1
        fi
        show
        return 0
    fi
    echo "source profile $name"
    source "$profiles/$name.sh" 
}

function vim_new_project() {
    tmux new-session -d -s my_session 'ruby run.rb'
}

