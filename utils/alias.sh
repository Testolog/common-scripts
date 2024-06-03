#!/usr/bin/env bash

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

function stop_all_container_docker() {
  _containers=()
  while IFS='' read -r line; do _containers+=("$line"); done < <(docker ps | awk '{print $1}')
  echo
  for cont in "${_containers[@]:1}"; do
    docker stop $cont
  done
}
alias smem="mem"
alias drm="remove_docker_images"
alias sdc="stop_all_container_docker"
alias gh="history | grep"
#alias 'tmux --kill-all'="tmux ls | grep : | cut -d. -f1 | awk '{print substr(\$1, 0, length(\$1)-1)}' | (while IFS='' read -r p1; do if ! [ -z \${p1} ]; then tmux kill-session -t \$p1; else echo \$p1; fi; done)"
alias gps="ps aux -xl | grep"
