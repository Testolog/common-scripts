#@IgnoreInspection BashAddShebang
# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"
export COMMON_SCRIPT="$HOME/common-scripts"

#append logic to install using base package installer

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"

eval "$(rbenv init - zsh)"
eval "$(pyenv init - zsh)"

DISABLE_AUTO_UPDATE="true"

export UPDATE_ZSH_DAYS=13
ENABLE_CORRECTION="true"

plugins=(
   colorize pip python brew 
)

source $ZSH/oh-my-zsh.sh
source $COMMON_SCRIPT/init.sh
source <(fzf --zsh)

NEW_LINE=$'\n'
GIT_PROM='%{$fg[green]%}%c $(git_prompt_info)%{$reset_color%}'
TIME_PROM='%{$fg[red]%}%D{%H:%M:%S}%{$reset_color%}'
PROMPT="%{$fg[yellow]%}%hƒ ${GIT_PROM} ${TIME_PROM} ${NEW_LINE}%{$fg[yellow]%}→%{$reset_color%} "

HISTTIMEFORMAT="%d-%m-%y %T "
HISTORY_IGNORE="(ls|la|ll|cd|pwd|bg|fg|history)"
HISTCONTROL=ignoreboth:erasedups
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory


if [ -f $HOME/${USER}_env.sh ]; then
 echo "load ${USER}_env.sh"
 source $HOME/${USER}_env.sh
fi

[ -s ~/.luaver/luaver ] && . ~/.luaver/luaver

