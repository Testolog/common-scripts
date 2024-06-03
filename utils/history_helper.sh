function exists { which $1 &> /dev/null }

function percol_select_history() {
    local tac
    exists gtac && tac="gtac" || { exists tac && tac="tac" || { tac="tail -r" } }
    BUFFER=$(fc -l -n 1 | eval $tac | percol --query "$LBUFFER")
    CURSOR=$#BUFFER         # move cursor
    zle -R -c               # refresh
}
if exists percol; then
    zle -N percol_select_history
    bindkey '^R' percol_select_history
else
  pip install percol
fi
