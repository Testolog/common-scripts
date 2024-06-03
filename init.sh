#!/usr/bin/env bash


source $COMMON_SCRIPT/utility.sh
source $COMMON_SCRIPT/logging.sh

alias smem="mem"
alias ports="lsof -PiTCP -sTCP:LISTEN"
alias drm="remove_docker_images"
alias sdc="stop_all_container_docker"
alias gh="percol_select_history"
#alias 'tmux --kill-all'="tmux ls | grep : | cut -d. -f1 | awk '{print substr(\$1, 0, length(\$1)-1)}' | (while IFS='' read -r p1; do if ! [ -z \${p1} ]; then tmux kill-session -t \$p1; else echo \$p1; fi; done)"
alias gps="ps aux -xl | grep"
alias vim="nvim"

#todo
