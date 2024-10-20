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

  log.debug"===== Получение параметров заданий ====="
  local meta_r = req{
    url = tasks_endpoint,
    headers = _G.headers,
    timeout = 10,
    connect_timeout = 10,
    retries = 5,
  }
  log.debug"===== Завершено ====="

  log.debug"===== Попытка десериализации полученного конфига ====="
  if meta_r:match"^%[" or meta_r:match"^%{" then
    local ok, res = pcall(json.decode, meta_r)
    if ok then
      if #res > 0 then
        _C.queue = {}

        _C.queue.trace = {}
        _C.queue.curl = {}
        _C.queue.proxy = {}

        for i = 1, #res do
          local r = res[i]
          local cmd = r.command
          if cmd == "trace" then
            table.insert(_C.queue.trace, {
              tgt = r.target,
              port = 443,
              proto = "tcp",
              task_id = res[i].task_id,
            })
          elseif cmd == "curl" then
            table.insert(_C.queue.curl, {
              tgt = r.target,
              post = nil,
              task_id = res[i].task_id,
            })
          elseif cmd == "proxy" then
            table.insert(_C.queue.proxy, {
              tgt = r.target,
              post = nil,
              task_id = res[i].task_id,
            })
          else
            log.bad(("Получен неподдерживаемый тип задания: %s (id задания: %s)!"):format(cmd, r.task_id))
            return false
          end
        end
      end
    else
      log.bad(("Ошибка десереализации мета-информации о задании: %s"):format(meta_r))
      return false
    end
  end
  log.debug"===== Завершено ====="
  log.debug"==== Выход из функции подключения ===="
  return true
end

_C.perform    = function()
  local back  = ("https://%s"):format(getconf"backend_domain")

  local jobs = {
    curl  = function(o) return req{ url = o.tgt, post = o.post } end,
    trace = function(o) return trace{ host = o.tgt, proto = o.proto or "tcp", port = o.proto or 443, } end,
    proxy = function(o) return req{ url = o.url or back, post = o.post, proxy = o.tgt } end,
  }
  _C.logs    = {}
  for job_type, _ in pairs(jobs) do
    local current_queue = _C.queue[job_type]
    for i = 1, #current_queue do
      _C.logs[current_queue[i].task_id] = b64enc(jobs[job_type](current_queue[i]) or "")
    end
  end
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
  }

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
