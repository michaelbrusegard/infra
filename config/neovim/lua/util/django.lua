local M = {}

function M.get_django_settings()
  local manage = vim.fn.getcwd() .. '/manage.py'
  if vim.fn.filereadable(manage) == 1 then
    for line in io.lines(manage) do
      local match = line:match('DJANGO_SETTINGS_MODULE",%s*"([^"]+)"')
      if match then
        return match
      end
    end
  end
  return nil
end

return M
