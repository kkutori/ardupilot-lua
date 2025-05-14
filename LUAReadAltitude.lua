--[[
  串口通信模块脚本
  功能：发送AT+START命令使能模块，然后循环读取模块返回的数据
  更新：添加启动延迟功能，延迟5秒后再发送AT+START命令
--]]

-- 定义MAV_SEVERITY常量表
local MAV_SEVERITY = {EMERGENCY=0, ALERT=1, CRITICAL=2, ERROR=3, WARNING=4, NOTICE=5, INFO=6, DEBUG=7}

-- 配置参数
local SERIAL_PORT = 1     -- 串口端口号，对应SERIALx_PROTOCOL = 28的端口
local BAUD_RATE = 9600  -- 波特率
local UPDATE_RATE_MS = 1000 -- 更新频率(毫秒)
local MAX_BYTES_TO_READ = 100 -- 每次读取的最大字节数
local ENABLE_DEBUG = true -- 启用调试信息
local START_DELAY_SEC = 5 -- 启动延迟时间(秒)

-- 全局变量
local est_range_value = 0  -- 新增距离值存储变量
local port = nil
local initialized = false -- 初始化状态
local command_sent = false -- 命令发送状态
local buffer = {}         -- 接收缓冲区
local buffer_len = 0      -- 缓冲区长度
local delay_timer = 0     -- 延迟计时器
local delay_complete = false -- 延迟完成状态

-- lua altitude enable and value
local alt_enable = 0
local alt_value = 0

-- 查找并初始化串口
function init_serial()
  -- 查找脚本串口实例 (0索引，所以减1)
  port = serial:find_serial(SERIAL_PORT - 1)
  if not port then
    gcs:send_text(MAV_SEVERITY.ERROR, "Init Fail")
    return false
  end
  
  -- 初始化串口
  port:begin(BAUD_RATE)
  
  return true
end

-- 发送使能命令
function send_enable_command()
  if not port then
    return false
  end
  
  -- 发送AT+START\n命令
  local command = "AT+START\n"
  -- 逐字节写入命令
  for i = 1, #command do
    port:write(string.byte(command, i))
  end
  
  if ENABLE_DEBUG then
    gcs:send_text(MAV_SEVERITY.INFO, "AT+START")
  end
  
  return true
end

-- 处理接收到的数据
function process_received_data(data)
    -- 模式匹配提取数字
    local numeric_value = data:match("EstRange:(%d+%.%d+)")
  
    if numeric_value then
        est_range_value = tonumber(numeric_value)
    else
        est_range_value = 0
    end



      -- test read baro altitude
    -- local baro_alt = baro:get_altitude()
    -- gcs:send_text(MAV_SEVERITY.INFO, string.format("B:%.2f", baro_alt))

    param:set("LUA_ALT_VALUE", est_range_value)
    

    -- 数据显示
    if ENABLE_DEBUG then
        -- gcs:send_text(MAV_SEVERITY.INFO, string.format("R:%s, %.6f", data, est_range_value))
        alt_value = param:get("LUA_ALT_VALUE")
        gcs:send_text(MAV_SEVERITY.INFO, string.format("A%.2f B%.2f", est_range_value, alt_value))
        -- gcs:send_named_float("altasl", est_range_value)
    end
   
end


-- 主更新函数
function update()
  -- 处理延迟逻辑
  if not delay_complete then
    delay_timer = delay_timer + UPDATE_RATE_MS / 1000 -- 转换为秒
    if delay_timer >= START_DELAY_SEC then
      delay_complete = true
    else
      -- 继续等待延迟完成
      return update, UPDATE_RATE_MS
    end
  end

  -- 读取 LUA_ALT_ENABLE 和 LUA_ALT_VALUE
  alt_enable = param:get("LUA_ALT_ENABLE")
  alt_value = param:get("LUA_ALT_VALUE")
  if alt_enable == 0 then
    gcs:send_text(MAV_SEVERITY.INFO, "read lua alt disable")
    return update, 2000
  end



  -- 初始化串口(如果尚未初始化)
  if not initialized then
    initialized = init_serial()
    if not initialized then
      -- 如果初始化失败，1秒后重试
      return update, 1000
    end

    -- 发送使能命令
    send_enable_command()
  end
  

  
  -- 读取串口数据
  if initialized then
    if not port then
      gcs:send_text(MAV_SEVERITY.ERROR, "Port object missing")
      return update, 1000
    end
    
    local nbytes = port:available()
    if not nbytes then
      gcs:send_text(MAV_SEVERITY.ERROR, "available() returns nil")
      return update, 1000
    end
    -- nbytes = tonumber(nbytes)
    nbytes = 30
    -- gcs:send_text(MAV_SEVERITY.INFO, string.format("byte%d", nbytes))
    -- gcs:send_text(MAV_SEVERITY.INFO, tostring(nbytes))
    if nbytes > 0 then
      -- 限制每次读取的字节数
      nbytes = math.min(nbytes, MAX_BYTES_TO_READ)
      
      -- 读取数据
      local data = ""
      for i = 1, nbytes do
        local r = port:read()
        if r >= 0 then
          data = data .. string.char(r)
        end
      end
      
      -- 处理接收到的数据
      if #data > 0 then
        process_received_data(data)
      end
    end
  end
  
  -- 继续循环
  return update, 100
end

-- 错误处理包装函数
function protected_wrapper()
  local success, err = pcall(update)
  if not success then
    gcs:send_text(MAV_SEVERITY.ERROR, "内部错误: " .. err)
    -- 发生错误时，1秒后重试，避免错误信息刷屏
    return protected_wrapper, 1000
  end
  return update()
end

-- 开始运行更新循环
return protected_wrapper()