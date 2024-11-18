local json    = require"cjson"
local utils   = require"checker.utils"
local log     = utils.logger
local req     = utils.req
local getconf = utils.getconf
local trace   = utils.trace
local b64enc  = utils.b64enc

local _C      = {}

_C.proto      = "custom"
_C.type       = "service"

_C.prepare    = function()
  local api            = ("https://%s/api"):format(getconf"backend_domain")
  local tasks_endpoint = ("%s/checker/tasks/"):format(api)

  log.print"Получение параметров заданий"
  local meta_r = req{
    url = tasks_endpoint,
    headers = _G.headers,
    timeout = 10,
    connect_timeout = 10,
    retries = 5,
  }.body or ""
  log.good"Завершено"

  log.debug"===== Попытка десериализации полученного конфига ====="
  if meta_r:match"^%[" or meta_r:match"^%{" then
    local ok, res = pcall(json.decode, meta_r)
    if ok then
      if type(res) == "table" and #res > 0 then
        _C.queue = {}
        for i = 1, #res do
          local r    = res[i]
          local cmd  = r.command
          local opts = {
            task_id  = r.task_id,
            tgt      = r.target,
          }
          local cmds = {
            trace    = { port = r.port or 443, proto = r.proto or "tcp", },
            curl     = { post = r.post, },
            proxy    = { post = r.post, url = r.url, },
            sni_slow = { url = r.url, },
          }
          local c = cmds[cmd]

          if c then
            _C.queue[cmd]  = _C.queue[cmd] or {}
            c.force_v4     = r.force_v4
            c.range        = r.range
            c.conn_timeout = r.conn_timeout
            c.req_timeout  = r.req_timeout
            for k, v in pairs(c) do
              opts[k] = v
            end
            table.insert(_C.queue[cmd], opts)
          else
            log.bad(("Получен неподдерживаемый тип задания: %s (id задания: %s)!"):format(cmd, r.task_id))
            return false
          end
        end
      end
    else
      log.bad(("Ошибка десериализации мета-информации о задании: %s"):format(meta_r))
      return false
    end
  end
  log.debug"===== Завершено ====="
  log.debug"==== Выход из функции подключения ===="
  return true
end

_C.perform    = function()
  local back = ("https://%s"):format(getconf"backend_domain")

  local jobs = {
    trace = function(o)
      return trace{
        host = o.tgt,
        proto = o.proto or "tcp",
        port = o.proto or 443,
        force_ipv4 = o.force_v4 or true, --- NOTE: на некоторых провайдерах по IPv6 не замедляется
      }
    end,
    curl  = function(o)
      return req{
        url = o.tgt,
        post = o.post,
        timeout = o.req_timeout or 5,
        connect_timeout = o.conn_timeout or 5,
        retries = 0,
        force_ipv4 = o.force_v4 or true, --- NOTE: на некоторых провайдерах по IPv6 не замедляется
        range = o.range or "0-400000", --- NOTE: 🤔
        include_header_in_body = true,
      }.body
    end,
    proxy = function(o)
      return req{
        url = o.url or back,
        post = o.post,
        proxy = o.tgt,
        timeout = o.req_timeout or 5,
        connect_timeout = o.conn_timeout or 5,
        retries = 0,
        range = o.range or "0-400000", --- NOTE: 🤔
        force_ipv4 = o.force_v4 or true, --- NOTE: на некоторых провайдерах по IPv6 не замедляется
        include_header_in_body = true,
      }.body
    end,
    sni_slow = function(o)
      local scheme, host, uri = o.url:match"^([^/]*)://([^/]*)(.*)"
      return {
        raw_speed = req{
          url = o.url,
          force_ipv4 = o.force_v4 or true, --- NOTE: на некоторых провайдерах по IPv6 не замедляется
          range = o.range or "0-400000", --- NOTE: 🤔
          timeout = o.req_timeout or 5,
          connect_timeout = o.conn_timeout or 5,
          writefunction = function() end,
          retries = 0,
          measure_dlspeed = true,
          ignore_errors = true,
        }.dlspeed or 0,
        sni_speed = req{
          url = ("%s://%s%s"):format(scheme, o.tgt, uri),
          force_ipv4 = o.force_v4 or true, --- NOTE: на некоторых провайдерах по IPv6 не замедляется
          range = o.range or "0-400000", --- NOTE: 🤔
          timeout = o.req_timeout or 5,
          connect_timeout = o.conn_timeout or 5,
          no_verify_host = true,
          connect_to = ("::%s"):format(host),
          headers = { ("Host: %s"):format(host), },
          writefunction = function() end,
          retries = 0,
          measure_dlspeed = true,
          ignore_errors = true,
        }.dlspeed or 0,
      }
    end,
  }
  _C.logs    = {}
  log.print"Выполнение заданий"
  for job_type, _ in pairs(jobs) do
    log.debug(("Обработка заданий типа '%s'"):format(job_type))
    local current_queue = _C.queue[job_type] or {}
    for i = 1, #current_queue do
      local q = current_queue[i]
      local t = jobs[job_type](q)
      local t_id = q.task_id
      log.debug(("Задание с ID %s"):format(t_id))
      if job_type == "sni_slow" then
        _C.logs[t_id] = t
      else
        _C.logs[t_id] = b64enc(t or "")
      end
    end
  end
  log.good"Завершено"
end

_C.finish     = function()
  local api              = ("https://%s/api"):format(getconf"backend_domain")
  local reports_endpoint = ("%s/checker/tasks/"):format(api)

  log.print"Отправка отчёта"
  local resp_json = req{
    url = reports_endpoint,
    post = json.encode(_C.logs),
    headers = _G.headers,
    timeout = 10,
    connect_timeout = 10,
    retries = 0,
  }.body or ""

  local rok, resp_t = pcall(json.decode, resp_json)
  if not rok then
    log.bad(
      ("Ошибка обработки ответа бекенда! Ожидался JSON-массив, получено: %s")
      :format(resp_json)
    )
    resp_t = {}
  end
  if resp_t.status == "success" then
    log.good"Отчёт успешно получен сервером"
  else
    log.bad"При отправке отчёта произошли ошибки"
    log.bad"Возможно, информация ниже вам пригодится:"
    log.bad(("Ответ сервера: %s"):format(resp_json))
    log.bad"Если из сообщений об ошибках выше ничего не понятно - напишите в чат"
  end
end

return _C
