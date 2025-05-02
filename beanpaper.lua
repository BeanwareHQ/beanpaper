-- beanpaper: a cursed hyprpaper config generator
--
-- Copyright (c) Eason Qin <eason@ezntek.com>, 2025.
--
-- This source code form is licensed under the MIT/Expat license. Visit the
-- root of the project directory for details, or find a digital copy on the OSI
-- website.

local M = {}
local should_log

---@class Monitor
---@field [1] string (output)
---@field [2] string (path)
---@field log? boolean (default = false)
---@field contain? boolean (default = false)
---@field tile? boolean (default = false)
---@field useprefix? boolean (default = true)

---@class Config
---@field monitors Monitor[]
---@field prefix? string
---@field ipc? boolean
---@field splash? boolean

---Pretty-prints an error.
---@param txt string
local function err(txt)
    local s = "\27[31;1m[ERROR] \27[0m" .. txt
    io.stderr:write(s)
    os.exit(1)
end

---Pretty-prints a warning.
---@param txt string
local function warn(txt)
    local s = "\27[35;1m[WARN] \27[0m\27[2m" .. txt .. "\27[0m"
    io.stderr:write(s)
end

---Pretty-prints a log value
---@param txt string
local function log(txt)
    if not should_log then
        return
    end

    local s = "\27[36;1m[INFO] \27[0m\27[2m" .. txt .. "\27[0m"
    io.stderr:write(s)
end

---Executes a command silently.
---@param cmd string
local function execute_silent(cmd)
    log(string.format("\27[2mexecuted `%s`\27[0m\n", cmd))
    os.execute(cmd .. " > /dev/null 2>&1")
end

---Checks if hyprpaper is running.
---@return boolean
local function is_hyprpaper_running()
    local handle = io.popen("pgrep -f 'hyprpaper'")
    if handle == nil then
        return false
    end

    -- for some reason, at least 1 pid is read from pgrep. therefore we count
    -- if there is >1 line
    local lines = 0
    for _ in handle:lines() do
        lines = lines + 1
        if lines > 1 then
            return true
        end
    end
    return false
end

---Restarts hyprpaper, or starts it if it is not running.
local function restart_hyprpaper()
    if is_hyprpaper_running() then
        execute_silent("pkill hyprpaper")
    end
    os.execute("nohup hyprpaper > /dev/null 2>&1 &")
end

---Checks if a file exists at path
---@param path string
---@return boolean
local function file_exists(path)
    local fp = io.open(path, "r")
    if fp ~= nil then
        fp:close()
        return true
    else
        return false
    end
end

---Resolves a wallpaper path given a prefix.
---@param mon Monitor
---@param prefix? string
local function resolve_path(mon, prefix)
    local path = mon[2]
    local useprefix = mon.useprefix or true
    if prefix ~= nil and useprefix then
        path = prefix .. '/' .. path
    end
    return path
end

---Gets the path to $XDG_CONFIG_HOME/hypr
---@return string
local function get_config_path()
    local cfgpath = os.getenv("XDG_CONFIG_HOME")
    if cfgpath == nil then
        local home = os.getenv("HOME")
        if home == nil then
            err("$HOME does not exist")
        end

        cfgpath = home .. "/.config"
    end

    return cfgpath .. "/hypr"
end

---Checks if IPC is enabled via the hyprland config on disk.
---@return boolean
local function check_ipc()
    local cfgpath = get_config_path() .. "/hyprpaper.conf"

    local fp = io.open(cfgpath, "r")
    if fp == nil then
        err(string.format("failed to open hyprpaper config at %s", cfgpath)); return false
    end

    for line in fp:lines() do
        if line == "ipc = true" then
            return true
        end
    end

    return false
end

---Generates a string configuration for a monitor table.
---@param mon Monitor
---@param prefix? string
---@return string[]
local function generate_monitor(mon, prefix)
    local output = {}

    local contain = mon.contain or false
    local tile = mon.tile or false

    if contain and tile then
        warn(string.format("cannot have both contain and tile for monitor %s. defaulting to cover", mon[1]))
    elseif contain then
        table.insert(output, "contain:")
    elseif tile then
        table.insert(output, "tile:")
    end

    local path = mon[2]

    local useprefix = mon.useprefix or true
    if prefix ~= nil and useprefix then
        path = prefix .. "/" .. path
    end

    table.insert(output, path)

    local line = string.format("%s,%s", mon[1], table.concat(output, ""))
    return { line, path }
end

---Gets loaded wallpapers from hyprctl (loaded items stored as keys)
---@return table<string, integer>
local function get_loaded_wallpapers()
    local handle = io.popen("hyprctl hyprpaper listloaded", "r")
    if handle == nil then
        err "failed to query hyprctl for loaded wallpapers"; return {}
    end

    local res = {}
    for line in handle:lines() do
        res[line] = 1
    end

    return res
end

---Validates a configuration before applying
---@param cfg Config
function M.Validate(cfg)
    for _, mon in ipairs(cfg.monitors) do
        local path = resolve_path(mon, cfg.prefix)

        if not file_exists(path) then
            err(string.format("file at %s does not exist", path)); return
        end
    end
end

---Generates a string configuration for a whole config.
---@param cfg Config
function M.Generate(cfg)
    local wallpapers = {}
    local preload = {}

    local ipc = cfg.ipc or true
    local splash = cfg.splash or false

    local header = [[
# ===== GENERATED BY HPG =====
# visit https://github.com/ezntek/beanpaper for details.
# ============================
#
]]
    M.Validate(cfg)

    for _, v in ipairs(cfg.monitors) do
        local mon = generate_monitor(v, cfg.prefix)
        table.insert(wallpapers, "wallpaper = " .. mon[1])

        -- precalculating required wallpapers avoids duplicate preloads
        preload[mon[2]] = 1
    end

    local res = header
    res = res .. "ipc = " .. tostring(ipc) .. "\n"
    res = res .. "splash = " .. tostring(splash) .. "\n"

    for k, _ in pairs(preload) do
        local line = "preload = " .. k .. "\n"
        res = res .. line
    end

    for _, v in ipairs(wallpapers) do
        res = res .. v .. "\n"
    end

    return res
end

---Writes a cfg table to disk, at $HOME/hypr/hyprpaper.conf
---@param cfg Config
function M.ApplyDisk(cfg)
    local cfgpath = get_config_path()

    local path = string.format("%s/hypr/hyprpaper.conf", cfgpath)
    execute_silent(string.format("mkdir -p %s/hypr", cfgpath))

    local fp, errmsg = io.open(path, "w")
    if fp == nil then
        err(string.format("failed to open file (%s)", errmsg)); return
    end

    local s = M.Generate(cfg)
    fp:write(s)

    fp:close()
end

---Applies the configuration over IPC.
---@param cfg Config
function M.ApplyIPC(cfg)
    local loaded = get_loaded_wallpapers()

    for _, mon in ipairs(cfg.monitors) do
        if loaded[mon[2]] == nil then
            local path = resolve_path(mon, cfg.prefix)
            execute_silent("hyprctl hyprpaper preload " .. path)
            loaded[mon[2]] = 1 -- mark as loaded
        end

        local gen = generate_monitor(mon, cfg.prefix)
        execute_silent("hyprctl hyprpaper wallpaper \"" .. gen[1] .. "\"")
    end

    execute_silent("hyprctl hyprpaper unload all")
end

---Applies the configuration.
---@param cfg Config
function M.Apply(cfg)
    local ipc_enabled = check_ipc()
    local cfgipc = cfg.ipc or true
    local should_apply_disk = not ipc_enabled or (ipc_enabled and not cfgipc)
    should_log = cfg.log or false

    -- if IPC is not enabled or if it should be enabled
    if should_apply_disk then
        M.ApplyDisk(cfg)
        restart_hyprpaper()
    else
        -- ipc is on and should be on
        M.ApplyDisk(cfg)

        if not is_hyprpaper_running() then
            restart_hyprpaper()
        end

        M.ApplyIPC(cfg)
    end
end

return M
