return {
  {
    'neovim/nvim-lspconfig',
    opts = function(_, _)
      local keys = require('lazyvim.plugins.lsp.keymaps').get()
      keys[#keys + 1] = {
        'gra',
        vim.lsp.buf.code_action,
        desc = 'Code Action',
        mode = { 'n', 'v' },
        has = 'codeAction',
      }
      keys[#keys + 1] = {
        'gri',
        vim.lsp.buf.implementation,
        desc = 'Go to Implementation',
        mode = 'n',
        has = 'implementation',
      }
      keys[#keys + 1] = {
        'grn',
        '<cmd>lua require("live-rename").rename()<cr>',
        desc = 'Rename',
        mode = 'n',
        has = 'rename',
      }
      keys[#keys + 1] = {
        '<leader>cr',
        '<cmd>lua require("live-rename").rename()<cr>',
        desc = 'Rename',
        mode = 'n',
        has = 'rename',
      }
      keys[#keys + 1] = {
        'grr',
        vim.lsp.buf.references,
        desc = 'Go to References',
        mode = 'n',
        has = 'references',
      }
      keys[#keys + 1] = {
        'grt',
        vim.lsp.buf.type_definition,
        desc = 'Go to Type Definition',
        mode = 'n',
        has = 'typeDefinition',
      }
      keys[#keys + 1] = {
        'gO',
        vim.lsp.buf.document_symbol,
        desc = 'Document Symbols',
        mode = 'n',
        has = 'documentSymbol',
      }
      keys[#keys + 1] = {
        '<C-s>',
        vim.lsp.buf.signature_help,
        desc = 'Signature Help',
        mode = 'i',
        has = 'signatureHelp',
      }
      keys[#keys + 1] = {
        'an',
        vim.lsp.buf.selection_range,
        desc = 'Outer Selection Range',
        mode = 'v',
        has = 'selectionRange',
      }
      keys[#keys + 1] = {
        'in',
        vim.lsp.buf.selection_range,
        desc = 'Inner Selection Range',
        mode = 'v',
        has = 'selectionRange',
      }
    end,
  },
}
