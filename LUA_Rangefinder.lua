--[[
  串口通信模块脚本
  功能：发送AT+START命令使能模块，然后循环读取模块返回的数据
  更新：添加启动延迟功能，延迟5秒后再发送AT+START命令
--]]

--[[
  LD7901B 模块需要预先配置
  AT+START\n 开始命令
  AT+RESET\n 复位命令
  AT+BAUD=115200\n 波特率命令
  AT+SKIPMIN=15\n 最小测量范围，可设置的最小值为20cm(单位:cm)
  AT+SKIPMAX=1500\n 最大测量范围，可设置的最小值为1500cm(单位:cm)
  AT+TIME=160\n 帧周期(即改变输出结果间隔)单位ms
  AT+TLVS=1\n 输出结果模式切换(0:16 进制协议输出，1:字符串输出)
--]]

-- 定义MAV_SEVERITY常量表
local MAV_SEVERITY = {EMERGENCY=0, ALERT=1, CRITICAL=2, ERROR=3, WARNING=4, NOTICE=5, INFO=6, DEBUG=7}


local PARAM_TABLE_KEY = 4
assert(param:add_table(PARAM_TABLE_KEY, "LUA_RF_", 2), 'could not add param table')
assert(param:add_param(PARAM_TABLE_KEY, 1,  'ENABLE', 1), 'could not add param1')
assert(param:add_param(PARAM_TABLE_KEY, 2,  'VALUE', 0), 'could not add param2')

-- 配置参数
local SERIAL_PORT = 1     -- 串口端口号，对应SERIALx_PROTOCOL = 28的端口
local BAUD_RATE = 115200  -- 波特率
local UPDATE_RATE_MS = 1000 -- 更新频率(毫秒)
local MAX_BYTES_TO_READ = 100 -- 每次读取的最大字节数
local ENABLE_DEBUG = true -- 启用调试信息
local START_DELAY_SEC = 3 -- 启动延迟时间(秒)

--find Terrain Sensor Backend
local terrainSensor = rangefinder:get_backend(0)

-- 全局变量
local est_range_value = 0  -- 新增距离值存储变量
local port = nil
local initialized = false -- 初始化状态
local delay_timer = 0     -- 延迟计时器
local delay_complete = false -- 延迟完成状态

local available_bytes = 0

-- lua altitude enable and value
-- local LUA_RF_ENABLE = Parameter()
-- local LUA_RF_VALUE = Parameter()


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

  gcs:send_text(MAV_SEVERITY.INFO, "Module Start")
  
  return true
end

-- 处理接收到的数据
function process_received_data(data)
    -- 检查数据长度是否至少为6字节
    if #data < 6 then
        return
    end
    
    -- 检查数据是否以0xff开头 AT+TLVS=0\n  16进制协议输出
    if string.byte(data, 1) == 0xff then
        -- 提取第2到第5字节（共4个字节）
        local byte_str = string.sub(data, 2, 5)
        
        -- 使用string.unpack将4个字节转换为IEEE 754浮点数
        -- 格式说明：'<f' 表示小端序的单精度浮点数
        est_range_value = string.unpack("<f", byte_str)
    end

    -- 设置参数值并输出
    if (est_range_value > 15) and (est_range_value < 1500) then
      if terrainSensor ~= nil then
        terrainSensor:handle_script_msg(est_range_value / 100)
      end
      
      -- gcs:send_text(MAV_SEVERITY.INFO, string.format("RF%.2f", est_range_value))
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

  -- LUA_RF_ENABLE:init('LUA_RF_ENABLE')
  -- LUA_RF_VALUE:init('LUA_RF_VALUE')

  -- 读取 LUA_RANGEFINDER_ENABLE
  -- if (LUA_RF_ENABLE:get()) == 0 then
  --   gcs:send_text(MAV_SEVERITY.INFO, "read lua alt disable")
  --   return update, 2000
  -- end



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
    
    available_bytes = port:available()
    if not available_bytes then
      gcs:send_text(MAV_SEVERITY.ERROR, "available() returns nil")
      return update, 1000
    end

    -- todo... available_bytes 无法判断是否有数据
    -- prot:available() 返回uint32_t 类型,无法直接与 number 类型的 0 进行比较
    -- 使用 tonumber() 转化出 nil,无法与 0 进行比较
    -- 暂时直接赋值 6 
    available_bytes = 6
    -- available_bytes = tonumber(available_bytes)
    -- gcs:send_text(MAV_SEVERITY.INFO, string.format("byte%d", available_bytes))
    -- gcs:send_text(MAV_SEVERITY.INFO, tostring(available_bytes))
    if available_bytes > 0 then
      -- 限制每次读取的字节数
      available_bytes = math.min(available_bytes, MAX_BYTES_TO_READ)
      
      -- 读取数据
      local data = ""
      for i = 1, available_bytes do
        local r = port:read()
        if r >= 0 then
          data = data .. string.char(r)
        end
      end
      
      -- 处理接收到的数据
      if #data > 0 then
        process_received_data(data)
      end
    else
      initialized = false
      gcs:send_text(MAV_SEVERITY.INFO, "no data, restart...")
      return update, 2000
    end
  end
  
  -- 继续循环
  return update, 50
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