-- Preserve all existing startup bytes, including BOMs and top-level returns.
local M = {}
local begin_marker = '-- BEGIN Launchpad X Native Note startup\n'
local end_marker = '-- END Launchpad X Native Note startup\n'

function M.render(existing, script)
  local first = existing:find(begin_marker, 1, true)
  if first then
    local last = existing:find(end_marker, first, true)
    assert(last, 'Incomplete Launchpad X startup block; repair it before installing')
    existing = existing:sub(1, first - 1) .. existing:sub(last + #end_marker)
    assert(not existing:find(begin_marker, 1, true), 'Multiple Launchpad X startup blocks')
  end
  local bom = ''
  if existing:sub(1, 3) == '\239\187\191' then
    bom, existing = existing:sub(1, 3), existing:sub(4)
  end
  -- Schedule before existing startup code so an existing `return` cannot skip us.
  local block = begin_marker .. 'reaper.defer(function()\n'
    .. '  local ok, err = xpcall(function() dofile(' .. string.format('%q', script)
    .. ') end, debug.traceback)\n'
    .. "  if not ok then reaper.ShowConsoleMsg('Launchpad X startup error: ' .. err .. '\\n') end\n"
    .. 'end)\n' .. end_marker
  return bom .. block .. existing
end

local function read(path)
  local file, err, code = io.open(path, 'rb')
  if not file then
    assert(code == 2, err) -- Only ENOENT means absent; never replace an unreadable file.
    return nil
  end
  local content = file:read('*a')
  file:close()
  assert(content, 'Cannot read ' .. path)
  return content
end

local function write(path, content)
  local file, err = io.open(path, 'wb')
  assert(file, err)
  local ok, write_err = file:write(content)
  local closed, close_err = file:close()
  assert(ok and closed, write_err or close_err)
end

function M.install(resource, script)
  local path = resource .. '/Scripts/__startup.lua'
  local existing = read(path)
  local updated = M.render(existing or '', script)
  if existing == updated then return path end
  if existing ~= nil then
    local backup = path .. '.launchpad-backup'
    if read(backup) == nil then write(backup, existing) end
  end
  local temporary = path .. '.launchpad-tmp'
  write(temporary, updated)
  local ok, err = os.rename(temporary, path)
  assert(ok, err)
  return path
end

return M
