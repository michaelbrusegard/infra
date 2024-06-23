" Set <space> as the leader key
let mapleader=" "
let maplocalleader=" "

" Make line numbers default
set number

" Add relative line numbers, to help with jumping
set relativenumber

" Set the number of spaces that a <Tab> in the file counts for
set tabstop=4

" Number of spaces a <Tab> counts for while editing
set softtabstop=4

" Set the number of spaces to use for each step of (auto)indent
set shiftwidth=4

" Convert tabs to spaces
set expandtab

" Enable mouse mode, can be useful for resizing splits
set mouse=a

" Don't show the mode, since it's already in the status line
set showmode

" Save undo history
set undofile

" Case-insensitive searching UNLESS \C or one or more capital letters in the search term
set ignorecase
set smartcase

" Disable line wrapping
set nowrap

" Decrease update time
set updatetime=50

" Decrease mapped sequence wait time
set timeoutlen=300

" Configure how new splits should be opened
set splitright
set splitbelow

" Show which line your cursor is on
set cursorline

" Minimal number of screen lines to keep above and below the cursor
set scrolloff=13

" Same as scrolloff, but for the horizontal axis
set sidescrolloff=13

" Enable highlight on search
set hlsearch

" Enables incremental search, highlights matches while typing
set incsearch

" Set the command line height to 1
set cmdheight=1

" Set the popup menu height
set pumheight=7

" Exit terminal mode in the builtin terminal with a shortcut that is easier
tnoremap <Esc><Esc> <C-\><C-n>

" Copy to clipboard using global binding
nnoremap <leader>y "+y
vnoremap <leader>y "+y

" Paste from clipboard using global binding
nnoremap <leader>p "+p
vnoremap <leader>p "+p
inoremap <leader>p <C-R><C-O>+

" Preserves clipboard when pasting with leader
xnoremap <leader>p "_dP

" Preserve clipboard when deleting with leader
nnoremap <leader>d "_d
vnoremap <leader>d "_d

" Move selected lines up and down
vnoremap J :move '>+1<CR>gv-gv
vnoremap K :move '<-2<CR>gv-gv

" Keep selection when indenting
vnoremap > >gv
vnoremap < <gv

" Save file
nnoremap <leader>w :w<CR>

" Quit file
nnoremap <leader>q :q<CR>

" Save and quit file
nnoremap <leader>x :x<CR>

" Highlight when yanking text
au TextYankPost * silent! lua vim.highlight.on_yank()

" Prevent automatic comments on new lines
au BufEnter * set fo-=c fo-=r fo-=o

" Remove trailing whitespace on save
au BufWritePre * %s/\s\+$//e

" Auto save on buffer leave or focus lost
au BufLeave,FocusLost * if &modified && !&readonly && expand('%') != '' && &buftype == '' | silent! update | endif

" Use terminal colors
set t_Co=0

" Disable backup files
set nobackup

" Disable backup before writing
set nowritebackup

" Disable swap file creation
set noswapfile
