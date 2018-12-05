#!/usr/bin/env bash


echo "alias loaded"

alias gh="history | grep"
alias 'tmux --kill-all'="tmux ls | grep : | cut -d. -f1 | awk '{print substr(\$1, 0, length(\$1)-1)}' | (while IFS='' read -r p1; do if ! [ -z \${p1} ]; then tmux kill-session -t \$p1; else echo \$p1; fi; done)"
alias gps="ps aux -xl | grep"