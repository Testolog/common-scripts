#!/usr/bin/env bash

function mem() {
  vm_stat | perl -ne '/page size of (\d+)/ and $size=$1; /Pages\s+([^:]+)[^\d]+(\d+)/ and printf("%-16s % 16.2f Mi\n", "$1:", $2 * $size / 1048576);'
}
function remove_docker_images() {
  _images=$(docker images)
  for img in $(${_images} | awk '{print \$3}'); do
    docker rmi -f "$img"
  done
}
alias smem="mem"
alias drm="remove_docker_images"
alias gh="history | grep"
#alias 'tmux --kill-all'="tmux ls | grep : | cut -d. -f1 | awk '{print substr(\$1, 0, length(\$1)-1)}' | (while IFS='' read -r p1; do if ! [ -z \${p1} ]; then tmux kill-session -t \$p1; else echo \$p1; fi; done)"
alias gps="ps aux -xl | grep"
