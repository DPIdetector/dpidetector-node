local ffi = require"ffi"

ffi.cdef"unsigned int sleep(unsigned int seconds);"
ffi.cdef"unsigned int wait();"

local _U = {}

function _U.getenv(name)
  local ret
  ret = os.getenv(name)
  if not ret then
    io.stderr:write(("Вы не указали значение переменной '%s'. Пожалуйста, укажите его в user.conf\n"):format(name))
    os.exit(1)
  else
    return ret
  end
end

_U.sleep = ffi.C.sleep

_U.wait = ffi.C.wait

local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/' -- You will need this for encoding/decoding

function _U.b64enc(data)
  return ((data:gsub('.', function(x)
    local r, bb = '', x:byte()
    for i = 8, 1, -1 do r = r .. (bb % 2 ^ i - bb % 2 ^ (i - 1) > 0 and '1' or '0') end
    return r;
  end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
    if (#x < 6) then return '' end
    local c = 0
    for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
    return b:sub(c + 1, c + 1)
  end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

function _U.b64dec(data)
  data = string.gsub(data, '[^' .. b .. '=]', '')
  return (data:gsub('.', function(x)
    if (x == '=') then return '' end
    local r, f = '', (b:find(x) - 1)
    for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and '1' or '0') end
    return r;
  end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
    if (#x ~= 8) then return '' end
    local c = 0
    for i = 1, 8 do c = c + (x:sub(i, i) == '1' and 2 ^ (8 - i) or 0) end
    return string.char(c)
  end))
end

local function gettime()
  local date_t = os.date"*t"
  return ("%.02d/%.02d/%.02d %.02d:%.02d:%.02d")
      :format(date_t.day, date_t.month, date_t.year, date_t.hour, date_t.min, date_t.sec)
  -- return (("%day%/%month%/%year% %hour%:%min%:%sec%"):gsub("%%(%w+)%%",os.date('*t')))
end

local function cmds_to_ansi(str)
  local seqs = {
    reset           = "\27[0m",
    normal          = "\27[0m",
    bold            = "\27[1m",
    bright          = "\27[1m",
    dim             = "\27[2m",
    italic          = "\27[3m",
    underline       = "\27[4m",
    blink           = "\27[5m",
    rapidblink      = "\27[6m",
    reverse         = "\27[7m",
    invert          = "\27[7m",
    hide            = "\27[8m",
    strikethrough   = "\27[9m",

    font0           = "\27[10m",
    font1           = "\27[11m",
    font2           = "\27[12m",
    font3           = "\27[13m",
    font4           = "\27[14m",
    font5           = "\27[15m",
    font6           = "\27[16m",
    font7           = "\27[17m",
    font8           = "\27[18m",
    font9           = "\27[19m",

    fraktur         = "\27[20m",
    gothic          = "\27[20m",

    dblunder        = "\27[21m",
    nobold          = "\27[22m",
    nodim           = "\27[22m",
    noitalic        = "\27[23m",
    nounderline     = "\27[24m",
    noblink         = "\27[25m",
    propspc         = "\27[26m",
    noreverse       = "\27[27m",
    noinvert        = "\27[27m",
    nohide          = "\27[28m",
    reveal          = "\27[28m",
    nostrike        = "\27[29m",

    black           = "\27[30m",
    red             = "\27[31m",
    green           = "\27[32m",
    yellow          = "\27[33m",
    blue            = "\27[34m",
    magenta         = "\27[35m",
    cyan            = "\27[36m",
    white           = "\27[37m",
    fg_256          = "\27[38;5;__C__m",
    fg_rgb          = "\27[38;2;__R__;__G__;__B__m",
    fg_default      = "\27[39m",

    blackbg         = "\27[40m",
    redbg           = "\27[41m",
    greenbg         = "\27[42m",
    yellowbg        = "\27[43m",
    bluebg          = "\27[44m",
    magentabg       = "\27[45m",
    cyanbg          = "\27[46m",
    whitebg         = "\27[47m",
    bg_256          = "\27[48;5;__C__m",
    bg_rgb          = "\27[48;2;__R__;__G__;__B__m",
    bg_default      = "\27[49m",

    nopropspc       = "\27[50m",
    frame           = "\27[51m",
    circle          = "\27[52m",
    overline        = "\27[53m",
    noframe         = "\27[54m",
    nocircle        = "\27[54m",
    nooverline      = "\27[55m",
    undercolor_256  = "\27[58;5;__C__m",
    undercolor_rgb  = "\27[58;2;__R__;__G__;__B__m",
    undercolor_def  = "\27[59m",

    superscript     = "\27[73m",
    subscript       = "\27[74m",
    nosuper         = "\27[75m",

    brightblack     = "\27[90m",
    brightred       = "\27[91m",
    brightgreen     = "\27[92m",
    brightyellow    = "\27[93m",
    brightblue      = "\27[94m",
    brightmagenta   = "\27[95m",
    brightcyan      = "\27[96m",
    brightwhite     = "\27[97m",

    brightblackbg   = "\27[90m",
    brightredbg     = "\27[91m",
    brightgreenbg   = "\27[92m",
    brightyellowbg  = "\27[93m",
    brightbluebg    = "\27[94m",
    brightmagentabg = "\27[95m",
    brightcyanbg    = "\27[96m",
    brightwhitebg   = "\27[97m",
  }

  local function parse_cmds(s)
    local buffer = {}
    for word in s:gmatch("[%w:_]+") do
      local seq
      if word:match":" then
        local C, R, G, B
        local cmd = word:gsub(":.+", "")
        local pat = seqs[cmd]
        if cmd:match"_256$" then
          C = word:match":([^:]+)$"
        elseif cmd:match"_rgb$" then
          R, G, B = word:match":([^:]+):([^:]+):([^:]+)$"
        end
        seq = pat:gsub("__([CRGB])__", { C = C, R = R, G = G, B = B })
      else
        seq = seqs[word] or ""
      end
      table.insert(buffer, seq)
    end
    return table.concat(buffer)
  end

  return (str:gsub("(%%{(.-)})", function(_, s) return parse_cmds(s) end))
end

local function log(t)
  local o = t.opts or {}
  local tpl = o.template or "%s%s [%s] | %s | %s%s\n"
  local fds = {
    info = _G.stdout,
    bad  = _G.stderr,
  }
  local signs = {
    bad = "!!",
    warn = "WW",
    good = "OK",
    debug = "DD",
    verbose = "VV",
    print = "..",
  }
  local log_to_console = {
    bad = not (_G.QUIET),
    warn = not (_G.QUIET),
    good = not (_G.QUIET),
    verbose = not (not (_G.VERBOSE)),
    print = not (_G.QUIET),
    debug = not (not (_G.DEBUG)),
  }
  local colors = o.colors or {
    bad = "%{red fg_rgb:250:20:20 bold}",
    warn = "%{yellow fg_rgb:250:250:20 bold}",
    good = "%{green fg_rgb:50:200:50}",
    verbose = "%{cyan fg_rgb:60:180:230}",
    print = "%{fg_default fg_rgb:180:180:180}",
    debug = "%{fg_default fg_rgb:111:111:111}",
    reset = "%{reset}",
    bold = "%{bold}",
  }
  local console_fd = o.fd or fds[t.level] or assert(_G.stderr)
  local logfile_fd = _G.log_fd
  local function handle_newlines(str)
    local s = tostring(str)
    local nl_tpl = o.nl_tpl or "%s [%s] | %s | "
    local nl_fmt = o.nl_fmt or {
      _G.proto,
      o.sign or signs[t.level] or "?",
      gettime(),
    }
    return (
      s
      :gsub(
        "\n",
        ("\n%s")
        :format(nl_tpl)
        :format(
          table.unpack(nl_fmt)
        )
      )
      :gsub("\r", "")
    )
  end
  local fmt = o.format or {
    colors[t.level] or "",
    _G.proto,
    o.sign or signs[t.level] or "?",
    gettime(),
    handle_newlines(t.text or ""),
    colors.reset or "",
  }
  local logrecord = cmds_to_ansi(
    tpl:format(
      table.unpack(fmt)
    )
  )

  if o.force_console or log_to_console[t.level] then
    console_fd:write(logrecord)
  end
  logfile_fd:write(logrecord)
  logfile_fd:flush()
end

_U.logger = {
  bad = function(text, opts)
    log{ level = "bad", text = text, opts = opts }
  end,
  warn = function(text, opts)
    log{ level = "warn", text = text, opts = opts }
  end,
  good = function(text, opts)
    log{ level = "good", text = text, opts = opts }
  end,
  print = function(text, opts)
    log{ level = "print", text = text, opts = opts }
  end,
  verbose = function(text, opts)
    log{ level = "verbose", text = text, opts = opts }
  end,
  debug = function(text, opts)
    log{ level = "debug", text = text, opts = opts }
  end,
  raw = log,
}

function _U.split(str, spr)
  local sep = spr or "\n"
  local result = {}
  local i = 1
  for c in str:gmatch(string.format("([^%s]+)", sep)) do
    result[i] = c
    i = i + 1
  end
  return result
end

function _U.getconf(opt)
  local json = require"cjson"

  local ok, config = pcall(json.decode, _G.current_config_json)
  if not ok then
    _U.logger.bad"Проблемы с получением динамической конфигурации! Будет использоваться значение по умолчанию."
    config = {}
  end

  return config[opt] or _G.config_default[opt]
end

function _U.check_ip(res, ip)
  local l = _U.logger
  if res:match(ip) then
    l.good"Проверка завершена успешно"
    return true
  else
    l.bad"Проверка провалилась!"
    if not res:match"CURL%-" then
      --- NOTE:
      --- Если там ошибка сURL'а, то о ней уже сообщено из функции запроса, так что повторять нет смысла
      --- А если там не ошибка, но при этом IP не совпадают, то при настройке туннеля случился баг
      l.debug"Произошёл странный баг: обнаруженный при проверке IP-адрес сервера не совпадает с его настоящим"
      l.debug(("Ответ сервиса определения IP: %%{bold red}%q"):format(res))
      l.debug(("Настоящий IP сервера: %%{bold red}%q"):format(ip))
      l.debug"%{bold} Возможные варианты:"
      l.debug"%{bold} - не отключилось предыдущее подключение"
      l.debug"%{bold} - что-то с обновлением конфига (или шаблоном)"
      l.debug"%{bold} - баг в туннелирующем софте и на предыдущей итерации он отказался отключаться"
      l.debug"%{bold} В любом случае - лучше написать в чат"
    end
    return false
  end
end

function _U.trace(srv)
  _U.logger.debug"===== Выполнение трассировки прохождения трафика до сервера ====="
  local protoport
  if not srv.host then
    _U.logger.error"===== Не указан сервер для проверки ====="
    return false
  end
  if type(tonumber(srv.port)) == "number" and ({ tcp = true, udp = true })[srv.proto] then
    protoport = ("--%s --port %d"):format(srv.proto, srv.port)
  else
    protoport = ""
  end
  local mtr_fd = io.popen(table.concat({
      ("mtr%s"):format(srv.force_ipv4 and " -4" or (srv.force_ipv6 and " -6") or ""),
      "--no-dns",
      "--report",
      ("--report-cycles=%d"):format(srv.cycles or 5),
      ("--gracetime=%d"):format(srv.tmout or 2),
      "--aslookup",
      protoport,
      srv.host,
      "2>&1", --- NOTE: без редиректа ошибки не попадают в лог
    },
    " "
  ))
  if not mtr_fd then
    _U.logger.bad"Проблемы с запуском трассировки (возможно, проблемы с контейнером)"
    return false
  end

  local res = (mtr_fd:read"*a" or "")
  _U.logger.debug(res)
  mtr_fd:close()
  _U.logger.debug"===== Завершено ====="
  return res
end

function _U.divine_grenade()
  local sp = require"subprocess"
  local wait = _U.wait
  local zombies = true
  local count = 0
  _U.logger.debug"= Вход в цикл очистки зомби-процессов ="
  repeat
    count = count + 1
    _U.logger.debug(("== Итерация цикла очистки зомби-процессов: %d =="):format(count))
    local e = sp.call{
      "sh",
      "-c",
      "ps -o stat,pid,comm | grep -q '^Z'",
    }
    if e == 1 then zombies = false end
    if zombies == true then
      _U.logger.debug"=== перед вызовом wait() ==="
      wait()
      _U.logger.debug"=== после вызова wait() ==="
    end
  until zombies == false or count >= 20
  _U.logger.debug"=== Выход из цикла очистки зомби-процессов ==="
  if zombies == true then
    _U.logger.bad"Проблемы с очисткой зомби-процессов (накопилось больше 20 зомби)!"
    _U.logger.bad"Перезапускаем контейнер"
    _G.need_restart = true
  end
end

function _U.is_locked()
  local fd = io.open("/tmp/.lock_checks", "r")
  if not fd then
    return false
  else
    fd:close()
    return true
  end
end

function _U.req(t)
  local function failed(s) return not (not ((s or ""):match"CURL%-")) end
  local r = require"checker.requests"
  local l = _U.logger

  l.debug"= Запуск функциии выполнения веб-запроса ="
  local ret = r(t)

  if failed(ret.body) then
    l.debug"== При выполнении запроса произошла ошибка =="
    local retries = t.retries or 3

    if retries > 0 then
      l.debug(("== Попробуем ещё несколько раз (максимум %d) =="):format(retries))
      local fails = 1
      repeat
        l.debug(("=== Попытка %d ==="):format(fails))
        _U.sleep(3)
        ret = r(t)
        if failed(ret.body) then fails = fails + 1 end
      until fails > retries or not (failed(ret))
      if failed(ret) then
        l.bad"Попытки получения ответа исчерпаны. Ответ получить не удалось"
      end
    end
  end
  l.debug"= Функция выполнения веб-запроса завершена ="
  return ret
end

function _U.read(name)
  local fd, err = io.open(name, "r")
  if fd then
    local content = fd:read"*a"
    fd:close()
    return content
  else
    _U.logger.bad(("Проблема при чтении файла %s. Сообщение об ошибке: %s"):format(name, err))
    return false
  end
end

function _U.write(name, content)
  local fd, err = io.open(name, "w+")
  if fd then
    fd:write(content)
    fd:flush()
    fd:close()
    return true
  else
    _U.logger.bad(("Проблема при открытии на запись файла %s. Сообщение об ошибке: %s"):format(name, err))
    return false
  end
end

function _U.get_defroute()
  local ret = io.popen"ip route get 222.222.222.222 2>/dev/null":read"*a":match"via ([%d.]+)"
  _U.wait()
  return ret
end

function _U.set_route(tgt, gw)
  local ret = io.popen(("ip route add %s via %s 2>&1"):format(tgt, gw))
  _U.wait()
  return not (ret)
end

function _U.setup_ssh_tunnel()
  local ssh_tun = {}
  local base_url = ("https://%s/ssh"):format(_U.getconf("backend_domain"))
  local cont_url = ("%s/%s/%s"):format(base_url, _G.node_id, _G.proto)
  local sp = require"subprocess"

  local function req(o)
    return _U.req{ headers = _G.headers, url = o.url }.body
  end

  if req{ url = ("%s/active"):format(cont_url) } == "true" then
    _U.logger.debug("Бекенд попросил поднять SSH-туннель")
    local port = req{ url = ("%s/port"):format(cont_url) }
    local tunhost = req{ url = ("%s/tunhost"):format(base_url) }
    local tunhost_user = req{ url = ("%s/tunhost_user"):format(base_url) }
    local tunhost_port = req{ url = ("%s/tunhost_port"):format(base_url) }
    local privkey = req{ url = ("%s/keys/priv"):format(base_url) }
    local pubkey = req{ url = ("%s/keys/pub"):format(base_url) }

    local function setup_keys()
      local privkey_fd = assert(io.open("/root/.ssh/id_ed25519", "w+"))
      privkey_fd:write(privkey)
      privkey_fd:write"\n"
      privkey_fd:flush()
      privkey_fd:close()

      local pubkey_fd = assert(io.open("/root/.ssh/authorized_keys", "w+"))
      pubkey_fd:write(pubkey)
      pubkey_fd:write"\n"
      pubkey_fd:flush()
      pubkey_fd:close()
    end

    local function tunnel_up()
      local exitcode = sp.call{
        "sh", "-c",
        ("netstat -ntp | grep -q '%s:%s.*/ssh'"):format(tunhost, tunhost_port),
        stdout = _G.devnull,
        stderr = _G.devnull,
      }
      return exitcode == 0
    end
    local function sshd_up()
      local exitcode = sp.call{
        "sh", "-c",
        "nestat -ntlp | grep -q '/sshd.*listener'",
        stdout = _G.log_fd or _G.stdout,
        stderr = _G.log_fd or _G.stderr,
      }
      return exitcode == 0
    end

    if not sshd_up() then
      local keygen_exitcode = sp.call{
        -- "sh", "-c",
        "ssh-keygen", "-A",
        stdout = _G.log_fd or _G.stdout,
        stderr = _G.log_fd or _G.stderr,
      }
      if keygen_exitcode > 0 then _U.logger.bad"Не получилось сгенерировать хостовые криптоключи" end

      local sshd_exitcode = sp.call{
        -- "sh", "-c",
        "/usr/sbin/sshd",
        stdout = _G.log_fd or _G.stdout,
        stderr = _G.log_fd or _G.stderr,
      }
      if sshd_exitcode > 0 then _U.logger.bad"Не получилось запустить демон SSH" end
    end

    if not tunnel_up() then
      --- Маршрут до туннельного сервера
      local gw = _U.get_defroute()
      _U.set_route(tunhost, gw)
      --- Сканируем ключи туннельного сервера
      local keyscan_exitcode = sp.call{
        "sh", "-c",
        ("mkdir -p /root/.ssh; ssh-keyscan -p %d %s > /root/.ssh/known_hosts"):format(tunhost_port, tunhost),
        stdout = _G.devnull,
        stderr = _G.devnull,
      }
      if keyscan_exitcode > 0 then _U.logger.bad"Не получилось просканировать SSH-ключи" end

      setup_keys()

      sp.call{
        "sh", "-c",
        "chmod 600 /root/.ssh/*",
        stdout = _G.devnull,
        stderr = _G.devnull,
      }
      --- Поднимаем туннель
      ssh_tun.proc, ssh_tun.errmsg, ssh_tun.errno = sp.popen{
        "ssh",
        ("%s@%s"):format(tunhost_user, tunhost),
        ("-p%d"):format(tunhost_port),
        ("-R 127.0.0.1:%s:127.0.0.1:22"):format(port),
        "-n", "-N",
        "-oConnectTimeout=3",
        "-oServerAliveInterval=3",
        "-oServerAliveCountMax=3",
        -- "-oTCPKeepAlive=3",
        -- "-oStrictHostKeyChecking=no",
        -- "-oUserKnownHostsFile=/dev/null",
        "-qqq",
        stdout = _G.log_fd or _G.stdout,
        stderr = _G.log_fd or _G.stderr,
      }
      if not ssh_tun.proc or ssh_tun.proc:poll() then
        _U.logger.bad(
          ("Проблема при инициализации! Сообщение об ошибке: %s. Код: %d"):format(
            ssh_tun.errmsg,
            ssh_tun.errno
          )
        )
        if ssh_tun.proc then
          ssh_tun.proc:kill()
          ssh_tun.proc = nil
        end
        return false
      end
    end
  else
    _U.logger.debug"Нет нужды в активном SSH-туннеле"
    _U.logger.debug"Так же, убиваем неиспользуемые SSH-туннели, если таковые были"
    sp.call{
      "sh", "-c",
      "killall -9 ssh sshd",
      stdout = _G.devnull,
      stderr = _G.devnull,
    }
  end
end

return _U
