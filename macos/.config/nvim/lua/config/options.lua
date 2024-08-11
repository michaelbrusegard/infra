-- Set <space> as the leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Make line numbers default
vim.opt.number = true

-- Add relative line numbers, to help with jumping
vim.opt.relativenumber = true

-- Set the number of spaces that a <Tab> in the file counts for
vim.opt.tabstop = 2

-- Number of spaces a <Tab> counts for while editing
vim.opt.softtabstop = 2

-- Set the number of spaces to use for each step of (auto)indent
vim.opt.shiftwidth = 2

-- Round indent to multiple of shift width
vim.opt.shiftround = true

-- Convert tabs to spaces
vim.opt.expandtab = true

-- Enable mouse mode, can be useful for resizing splits
vim.opt.mouse = "a"

-- Don't show the mode, since it's already in the status line
vim.opt.showmode = false

-- Save undo history
vim.opt.undofile = true

-- Save as many undo ops as possible
vim.opt.undolevels = 10000

-- Save to swap file after 200ms
vim.opt.updatetime = 200

-- Case-insensitive searching one or more capital letters in the search term
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Disable line wrapping
vim.opt.wrap = false

-- Better line wrapping
vim.opt.linebreak = true

-- Keep the sign column on by default
vim.opt.signcolumn = "yes"

-- Decrease update time
vim.opt.updatetime = 50

-- Decrease mapped sequence wait time, displays which-key popup sooner
vim.opt.timeoutlen = 300

-- Configure how new splits should be opened
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Maintain text around the cursor when splitting
vim.opt.splitkeep = "screen"

-- Preview substitutions live, as you type!
vim.opt.inccommand = "split"

-- Show which line your cursor is on
vim.opt.cursorline = true

-- Minimal number of screen lines to keep above and below the cursor.
vim.opt.scrolloff = 13

-- Same as scrolloff, but for the horizontal axis
vim.opt.sidescrolloff = 13

-- Enable highlight on search
vim.opt.hlsearch = true

-- Enables incremental search, highlights matches while typing
vim.opt.incsearch = true

-- Set the command line height to 0, to disable it when not in use
vim.opt.cmdheight = 0

-- Maximum number of items in the popup menu
vim.opt.pumheight = 10

-- Blend the popup menu with the background
vim.opt.pumblend = 10

-- Auto save when focus is lost
vim.opt.autowrite = true

-- Set completion options
vim.opt.completeopt = "menu,menuone,noselect"

-- Hide * markup for bold and italic, but not markers with substitutions
vim.opt.conceallevel = 2

-- Spellcheck
vim.opt.spelllang = { "en" }

-- Confirm instead of failing
vim.opt.confirm = true

-- Set fill characters
vim.opt.fillchars = {
	foldopen = "",
	foldclose = "",
	fold = " ",
	foldsep = " ",
	diff = "╱",
	eob = " ",
}

-- Open all folds when file is opened
vim.opt.foldlevel = 99

-- Set the format options
vim.opt.formatoptions = "jcroqlnt"

-- Set the grep format
vim.opt.grepformat = "%f:%l:%c:%m"

-- Use ripgrep for grepping
vim.opt.grepprg = "rg --vimgrep"

-- Preview search/replace in buffer
vim.opt.inccommand = "nosplit"

-- Keep view when jumping
vim.opt.jumpoptions = "view"

-- Set mimimum width
vim.opt.winminwidth = 5

-- Single status line across splits
vim.opt.laststatus = 3

-- Store more information in the session file
vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help", "globals", "skiprtp", "folds" }

-- Disable vim info messages
vim.opt.shortmess:append({ W = true, I = true, c = true, C = true })

-- Automatic indenting new lines
vim.opt.smartindent = true

-- True color support
vim.opt.termguicolors = true

-- Set a short timeout length for which-key
vim.opt.timeoutlen = 300

-- Move cursor freely in visual block
vim.opt.virtualedit = "block"

-- Set command-line completion mode
vim.opt.wildmode = "longest:full,full"

-- Enable smooth scrolling
vim.opt.smoothscroll = true

-- Set status column
vim.opt.statuscolumn = [[%!v:lua.require('util.options').statuscolumn()]]

-- Create folds using expressions
vim.opt.foldexpr = "v:lua.require('util.options').foldexpr()"
vim.opt.foldmethod = "expr"

-- Set format expression to use conform
vim.opt.formatexpr = "v:lua.require'conform'.formatexpr()"

-- Disable fold text
vim.opt.foldtext = ""

-- Disable tabs
vim.opt.showtabline = 0

-- Float opened
vim.g.float_open = false

-- Set bigfile size to 1MB
vim.g.bigfile_size = 1024 * 1024

-- Show marks in the sign column
vim.g.show_marks = true

-- Show diagnostics in the sign column
vim.g.show_diagnostics = true
