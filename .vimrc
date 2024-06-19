set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
    Plugin 'VundleVim/Vundle.vim'
    Plugin 'Smart-Tabs'
    Plugin 'dracula/vim'
    Plugin 'ryanoasis/vim-devicons'
    Plugin 'vim-syntastic/syntastic'
call vundle#end()

syntax on
color dracula
set nocompatible
set nu

filetype off
filetype plugin indent on
filetype plugin on



