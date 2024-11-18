return function(settings)
  local cURL  = require"cURL"

  local utils = require"checker.utils"
  local log   = utils.logger
  local split = utils.split

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
  if settings.include_headers_in_body and not settings.headers_only then
    c:setopt_header(1) -- включать заголовки в тело ответа
  elseif settings.headerfunction then
    c:setopt_headerfunction(settings.headerfunction)
  elseif _G.DEBUG or settings.collect_headers or settings.headers_only then
    c:setopt_headerfunction(function(chunk) table.insert(hbuf, chunk) end)
  end
  c:setopt_url(settings.url)

  if not settings.headers_only then
    c:setopt_writefunction(settings.writefunction or function(chunk) table.insert(wbuf, chunk) end)
  end

  c:setopt_timeout(settings.timeout or 10)
  c:setopt_connecttimeout(settings.connect_timeout or 10)

  if settings.progressfunction then
    c:setopt_progressfunction(settings.progressfunction)
    c:setopt_noprogress(0)
  end

  if settings.connect_to then
    c:setopt_connect_to{ settings.connect_to, }  --- NOTE: {}, sic❗
  end

  if settings.no_verify then
    c:setopt_ssl_verifypeer(0)
  end

  if settings.no_verify_host then
    c:setopt_ssl_verifyhost(0)
  end

  if settings.range then
    c:setopt_range(settings.range)
  end

  if settings.force_ipv4 then
    c:setopt_ipresolve(cURL.IPRESOLVE_V4)
  elseif settings.force_ipv6 then
    c:setopt_ipresolve(cURL.IPRESOLVE_V6)
  end

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
  local ret = {}
  if not success and not settings.ignore_errors then
    log.bad(("Ошибка при выполнении запроса: %q"):format(errmsg))
    ret.error = errmsg
  end

  local dlspeed
  if settings.measure_dlspeed then
    dlspeed = c:getinfo(cURL.INFO_SPEED_DOWNLOAD_T)
  end
  c:close()

  ret.body = table.concat(wbuf or {}):gsub("[\r\n]*$", "")
  ret.headers = table.concat(hbuf or {}):gsub("[\r\n]*$", "")
  ret.headers = #ret.headers > 0 and ret.headers or nil
  if settings.headers_only and settings.include_headers_in_body then ret.body = ret.headers end
  ret.dlspeed = dlspeed
  if _G.DEBUG then
    log.debug"=== выполнение запроса завершено ==="
    if not settings.headerfunction then
      log.debug"====== Заголовки ответа: ======"
      for _, v in ipairs(split(ret.headers, "\n")) do
        log.debug(("%s"):format(v))
      end
      log.debug"======================"
    end
    if not settings.writefunction then
      log.debug"====== Тело ответа: ======"
      log.debug(("%s"):format(ret.body or ""))
      log.debug"==================="
    end
  end
  return ret
end
