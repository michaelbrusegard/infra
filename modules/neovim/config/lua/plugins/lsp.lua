 return {
   {
     'neovim/nvim-lspconfig',
     opts = {
       servers = {
         ['*'] = {
           keys = {
             {
               'gra',
               '<cmd>lua vim.lsp.buf.code_action()<CR>',
               desc = 'Code Action',
               mode = { 'n', 'v' },
               has = 'codeAction',
             },
             {
               'gri',
               '<cmd>lua vim.lsp.buf.implementation()<CR>',
               desc = 'Go to Implementation',
               mode = 'n',
               has = 'implementation',
             },
             {
               'grn',
               '<cmd>lua require("live-rename").rename()<cr>',
               desc = 'Rename',
               mode = 'n',
               has = 'rename',
             },
             {
               '<leader>cr',
               '<cmd>lua require("live-rename").rename()<cr>',
               desc = 'Rename',
               mode = 'n',
               has = 'rename',
             },
             {
               'grr',
               '<cmd>lua vim.lsp.buf.references()<CR>',
               desc = 'Go to References',
               mode = 'n',
               has = 'references',
             },
             {
               'grt',
               '<cmd>lua vim.lsp.buf.type_definition()<CR>',
               desc = 'Go to Type Definition',
               mode = 'n',
               has = 'typeDefinition',
             },
             {
               'gO',
               '<cmd>lua vim.lsp.buf.document_symbol()<CR>',
               desc = 'Document Symbols',
               mode = 'n',
               has = 'documentSymbol',
             },
             {
               '<C-s>',
               '<cmd>lua vim.lsp.buf.signature_help()<CR>',
               desc = 'Signature Help',
               mode = 'i',
               has = 'signatureHelp',
             },
             {
               'an',
               '<cmd>lua vim.lsp.buf.selection_range()<CR>',
               desc = 'Outer Selection Range',
               mode = 'v',
               has = 'selectionRange',
             },
             {
               'in',
               '<cmd>lua vim.lsp.buf.selection_range()<CR>',
               desc = 'Inner Selection Range',
               mode = 'v',
               has = 'selectionRange',
             },
           };
         };
       };
     };
   },
 }
