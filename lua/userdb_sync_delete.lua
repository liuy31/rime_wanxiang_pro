-- 初始化函数
function init(env)
    if not env.initialized then
        env.initialized = true
        env.yaml_installation = detect_yaml_installation()
        env.os_type = detect_os_type(env)
        env.total_deleted = 0
    end
end

-- 解析 installation.yaml 文件
function detect_yaml_installation()
    local trim = function(s) return s:match("^%s*(.-)%s*$") or "" end
    local yaml = {}
    local user_data_dir = rime_api.get_user_data_dir()
    local yaml_path = user_data_dir .. "/installation.yaml"
    local file = io.open(yaml_path, "r")
    if not file then return yaml end
    for line in file:lines() do
        if not line:match("^%s*#") and not line:match("^%s*$") then
            local key_part, value_part = line:match("^([^:]-):(.*)")
            if key_part then
                local key = trim(key_part)
                local raw_value = trim(value_part)
                if key ~= "" and raw_value ~= "" then
                    local value = raw_value
                    if value:sub(1,1) == '"' and value:sub(-1) == '"' then
                        value = trim(value:sub(2, -2))
                    end
                    yaml[key] = value
                end
            end
        end
    end
    file:close()
    return yaml
end

-- 系统检测（保留）
function detect_os_type(env)
    local dist_name = env.yaml_installation["distribution_code_name"] or ""
    if dist_name:match("fcitx%-rime") then return "linux" end
    if dist_name:match("squirrel") then return "macos" end
    if dist_name:match("trime") then return "android" end
    if dist_name:match("hamster") then return "ios" end
    return "unknown"
end

-- 生成 UTF-8 用户提示
function generate_utf8_message(deleted_count)
    return "用户词典共清理 " .. tostring(deleted_count) .. " 行无效词条"
end

-- 显示通知
function send_user_notification(deleted_count, env)
    local msg = generate_utf8_message(deleted_count)
    if env.os_type == "linux" then
        os.execute('notify-send "' .. msg .. '" "--app-name=万象输入法"')
    elseif env.os_type == "macos" then
        os.execute('osascript -e \'display notification "' .. msg .. '" with title "万象输入法"\'')
    elseif env.os_type == "android" then
        os.execute('notify "' .. msg .. '"')
    elseif env.os_type == "ios" then
        os.execute('notify "' .. msg .. '"')
    end
end

-- 收集子目录
function list_dirs(path)
    local command = 'ls -p "'..path..'" | grep / 2>/dev/null'
    local handle = io.popen(command)
    if not handle then return {} end
    local dirs = {}
    for dir in handle:lines() do
        table.insert(dirs, path .. "/" .. dir:gsub("/$", ""))
    end
    handle:close()
    return dirs
end

-- 收集文件
function list_files(path)
    local command = 'ls -p "'..path..'" | grep -v / 2>/dev/null'
    local handle = io.popen(command)
    if not handle then return {} end
    local files = {}
    for file in handle:lines() do
        table.insert(files, path .. "/" .. file)
    end
    handle:close()
    return files
end

-- 清理 .userdb.txt 文件
function clean_userdb_file(file_path, env)
    local file = io.open(file_path, "r")
    if not file then return end

    local temp_file_path = file_path .. ".tmp"
    local temp_file = io.open(temp_file_path, "w")
    if not temp_file then file:close() return end

    local deleted = 0
    for line in file:lines() do
        local c_value = tonumber(line:match("c=(%-?%d+)") or "")
        if c_value and c_value <= 0 then
            deleted = deleted + 1
        else
            temp_file:write(line .. "\n")
        end
    end

    file:close()
    temp_file:close()

    if deleted > 0 then
        os.remove(file_path)
        os.rename(temp_file_path, file_path)
        env.total_deleted = env.total_deleted + deleted
    else
        os.remove(temp_file_path)
    end
end

-- 处理 .userdb.txt
function process_userdb_files(env)
    local sync_dir = env.yaml_installation["sync_dir"] or (rime_api.get_user_data_dir() .. "/sync")
    local id = env.yaml_installation["installation_id"]
    if id then sync_dir = sync_dir .. "/" .. id end

    local files = list_files(sync_dir)
    for _, file in ipairs(files) do
        if file:match("%.userdb%.txt$") then
            clean_userdb_file(file, env)
        end
    end
end

-- 删除 .userdb 文件夹
function process_userdb_folders(env)
    local user_data_dir = rime_api.get_user_data_dir()
    local dirs = list_dirs(user_data_dir)
    for _, dir in ipairs(dirs) do
        if dir:match("%.userdb$") then
            os.execute('rm -rf "' .. dir .. '"')
        end
    end
end

-- 清理入口（包含延时）
function sleep(seconds)
    os.execute("sleep " .. tostring(seconds))
end

function trigger_sync_cleanup(env)
    process_userdb_files(env)
    sleep(0.5)
    process_userdb_folders(env)
end

function UserDictCleaner_process(key_event, env)
    local context = env.engine.context

    -- 屏蔽未知平台
    if env.os_type == "unknown" then
        return 2
    end

    -- 仅在初始化且输入为 /del 时执行清理
    if context.input == "/del" and env.initialized then
        env.total_deleted = 0
        pcall(trigger_sync_cleanup, env)
        send_user_notification(env.total_deleted, env, true)  -- 可选：即使0也提示
        context:clear()
        return 1
    end

    return 2
end


-- 导出
return {
    init = init,
    func = UserDictCleaner_process
}
