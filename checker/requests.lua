local cURL = require"cURL"

local log = require"checker.utils".logger
local split = require"checker.utils".split

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
  c:setopt_useragent(settings.useragent or ("DPIDetector/%s"):format(_G.version))
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

  c:setopt_timeout(settings.timeout or 10)
  c:setopt_connecttimeout(settings.connect_timeout or 10)

  -- c:perform()
  if _G.DEBUG then
    log.debug"=== Подготовка к отправке запроса ==="
    log.debug(("====== URL запроса: %s ======"):format(settings.url))
    if #hdr > 0 then
      log.debug"====== Заголовки запроса: ======"
        for _, v in ipairs(hdr) do
          log.debug(("%s"):format(v))
        end
      log.debug"======================"
    end
    if settings.post then
      log.debug"====== Тело запроса: ======"
      log.debug(("%s"):format(settings.post))
      log.debug"======================"
    end
    log.debug"=== выполнение запроса начато ==="
  end

  local success, errmsg = pcall(c.perform, c)
  if not success then
    log.error(("Ошибка при выполнении запроса: %q"):format(errmsg))
    return errmsg
  end

  c:close()

  local ret = table.concat(wbuf):gsub("[\r\n]*$", "")
  log.debug"=== выполнение запроса завершено ==="
  log.debug"====== Заголовки ответа: ======"
  for _, v in ipairs(
    split(
      table.concat(hbuf or {})
        :gsub("[\r\n]*$", ""),
      "\n"
    )
  ) do
    log.debug(("%s"):format(v))
  end
  log.debug"======================"
  log.debug"====== Тело ответа: ======"
  log.debug(("%s"):format(ret))
  log.debug"==================="
  return ret
end
