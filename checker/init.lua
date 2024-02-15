-- luacheck: globals

local interval = 600

local json   = require"cjson"
local utils  = require"checker.utils"
local req    = require"checker.requests"
local custom = require"checker.custom"
local sleep  = utils.sleep
local getenv = utils.getenv
local proto  = custom.proto

_G.token    = getenv"token"
_G.nodename = getenv"node"

_G.DEBUG = os.getenv"DEBUG" or os.getenv(("%s_DEBUG"):format(proto:gsub("-", "_")))
_G.VERBOSE = os.getenv"VERBOSE" or os.getenv(("%s_VERBOSE"):format(proto:gsub("-", "_")))
if _G.VERBOSE or _G.DEBUG then
  _G.stdout = io.stdout
  _G.stderr = io.stderr
else
  _G.devnull = io.output("/dev/null")
  _G.stdout = _G.devnull
  _G.stderr = _G.devnull
end

if custom.init then
  local ok, ret = pcall(custom.init)
  if not ok and _G.DEBUG then
    _G.stderr:write(("\nОшибка при инициализации: %q\n"):format(ret))
    os.exit(1)
  end
end

local backend_domain = "dpidetector.org"
local api = ("https://%s/api"):format(backend_domain)
local servers_endpoint = ("%s/servers/"):format(api)
local reports_endpoint = ("%s/reports/"):format(api)

while true do
  local servers = {}

  local geo = req{
    url = "https://geo.censortracker.org/get-iso/plain"
  }

  if geo:match"RU" then
    -- Выполнять проверки только если нода выходит в интернет в России (например, не через VPN)
    -- т.к. в данный момент нас интересует именно блокировка трафика из/внутри России,
    -- а трафик из заграницы для этих целей бесполезен
    local servers_fetched = req{
      url = servers_endpoint,
      headers = {
        ("Token: %s"):format(_G.token),
      }
    }

    if servers_fetched:match"COULDNT_CONNECT" then
      --- HACK: (костыль) если получили ошибку "невозможно соединиться",
      --- то на всякий случай попробуем перезапросить ещё раз
      servers_fetched = req{
        url = servers_endpoint,
        headers = headers,
      }
    end

    if servers_fetched
      and servers_fetched:match"name"
      and servers_fetched:match"^%["
    then
      local ok, e = pcall(json.decode, servers_fetched)
      if not ok then
        io.stderr:write"Проблема со списком серверов (при частом повторении - попробуйте включить режим отладки)\n"
        -- То, что выше - выведется в любом случае, т.к. пишется на настоящий stderr
        -- То, что ниже - выведется только в случае объявленных VERBOSE или DEBUG (см. блок выше)
        _G.stderr:write"(Не получается десериализовать JSON со списком серверов)"
        _G.stderr:write"\n====== Результат запроса: ======"
        _G.stderr:write"\n==================\n"
        _G.stderr:write(servers_fetched)
        _G.stderr:write"\n==================\n"
        _G.stderr:write"\n====== Результат попытки десериализации: ======"
        _G.stderr:write"\n==================\n"
        _G.stderr:write(e)
        _G.stderr:write"\n==================\n"
      else
        servers = e
      end
    else
      io.stderr:write"Не удалось связаться с бекендом\n"
      io.stderr:write"Если данное сообщение имеет разовый характер - можно игнорировать\n"
      io.stderr:write"Если появляется при каждой итерации проверки - включите режим отладки и проверьте причину\n"
      -- То, что выше - выведется в любом случае, т.к. пишется на настоящий stderr
      -- То, что ниже - выведется только в случае объявленных VERBOSE или DEBUG (см. блок выше)
      _G.stderr:write"\n====== Результат запроса: ======"
      _G.stderr:write"\n==================\n"
      _G.stderr:write(servers_fetched)
      _G.stderr:write"\n==================\n"
    end
  end

  for _, server in ipairs(servers) do
    local conn = custom.connect(server)
    if conn then
      local result = custom.checker and custom.checker(server) or false
      custom.disconnect(server)

      local report = {
        server_name = tostring(server.name),
        protocol = tostring(custom.proto),
        available = not(not(result)),
        node_name = tostring(_G.nodename),
      }

      req{
        url = reports_endpoint,
        post = json.encode(report),
        headers = {
          ("Token: %s"):format(_G.token),
          "Content-Type: application/json",
        },
      }
    end
  end
  sleep(interval)
end
