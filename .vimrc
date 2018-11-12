set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
    Plugin 'VundleVim/Vundle.vim'
    Plugin 'Smart-Tabs'
    Plugin 'dracula/vim'
    Plugin 'vim-syntastic/syntastic'
    Plugin 'scrooloose/nerdtree'
call vundle#end()

syntax on
color dracula
set nocompatible
set nu

filetype off
filetype plugin indent on
filetype plugin on


let NERDTreeIgnore=['\.pyc$', '\~$']
let g:NERDTreeDirArrowExpandable = '▸'
let g:NERDTreeDirArrowCollapsible = '▾'
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif

map <C-m> :NERDTreeToggle<CR>