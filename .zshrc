#@IgnoreInspection BashAddShebang
# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

DISABLE_AUTO_UPDATE="true"

export UPDATE_ZSH_DAYS=13
ENABLE_CORRECTION="true"

plugins=(
  git init colored-man colorize pip python brew osx zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh
PROMPT="%{$fg[yellow]%}λ %{$fg[green]%}%c $(git_prompt_info)%{$reset_color%} %{$fg[yellow]%}→%{$reset_color%} "
if [ -f $HOME/env.sh ]; then
 echo "load env.sh"
 source $HOME/env.sh
fi

