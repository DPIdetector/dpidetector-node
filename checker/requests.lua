local cURL = require"cURL"

return function(settings)
  if type(settings) ~= "table" then settings = {} end
  if not settings.url then error("Вызов функции запроса URL без указания самого URL 🤷") end

  local hdr = settings.headers or {}
  local hbuf, wbuf = {}, {}
  local c = cURL.easy_init()

  c:setopt_httpheader(hdr)
  c:setopt_followlocation(1)
  if settings.post then
    c:setopt_post(1)
    c:setopt_postfields(settings.post)
  end
  if settings.proxy then
    c:setopt_proxy(settings.proxy)
  end
  c:setopt_useragent(settings.useragent or "DPIdetector/0.0.0")
  if settings.interface then
    c:setopt_interface(settings.interface)
  end
  c:setopt_cookiejar("/tmp/cookies.txt")
  if _G.DEBUG then
    c:setopt_headerfunction(function(chunk) table.insert(hbuf, chunk) end)
    -- c:setopt_header(1) -- включать заголовки в тело ответа
  end
  c:setopt_url(settings.url)
  c:setopt_writefunction(function(chunk) table.insert(wbuf, chunk) end)

  -- c:perform()
  if _G.DEBUG then
    _G.stderr:write("\n====== URL запроса: ======\n")
    _G.stderr:write(settings.url)
    _G.stderr:write("\n======================\n")
    if #hdr > 0 then
      _G.stderr:write("\n====== Заголовки запроса: ======\n")
        for k, v in pairs(hdr) do
          _G.stderr:write(("%s: %s\n"):format(k, v))
        end
      _G.stderr:write("\n======================\n")
    end
    if settings.post then
      _G.stderr:write("\n====== Тело запроса: ======\n")
      _G.stderr:write(settings.post)
      _G.stderr:write("\n======================\n")
    end
    _G.stderr:write("(выполнение запроса начато)")
  end
  local success, errmsg = pcall(c.perform, c)
  if not success then
    _G.stderr:write(errmsg)
    return errmsg
  end

  local ret = table.concat(wbuf)
  if _G.DEBUG then
    _G.stderr:write("(выполнение запроса завершено)")
    _G.stderr:write("\n====== Заголовки ответа: ======\n")
    _G.stderr:write(table.concat(hbuf))
    _G.stderr:write("\n======================\n")
  end
  if _G.VERBOSE or _G.DEBUG then
    _G.stderr:write("\n====== Тело ответа: ======\n")
    _G.stderr:write(ret)
    _G.stderr:write("\n===================\n")
  end
  return ret
end
