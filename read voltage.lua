local batt_instance = 0
local batt_pct = -1
local voltage = 0
local new_voltage = 0
local cnt = 0

function update ()
    if batt_instance > battery:num_instances() then
        error("Battery " .. batt_instance .. " does not exist")
    end

    voltage = battery:voltage(batt_instance)

    -- boot or plug battery
    if voltage > 14.4 and (batt_pct == -1 or batt_pct == 0) then 
        batt_pct = (voltage-14.4) / (16.8-14.4) * 100 -- 3.6v-4.2v
        battery:reset_remaining(batt_instance, batt_pct)
        cnt = 100
    -- boot or remove battery
    elseif voltage <= 14.4 and (batt_pct == -1 or batt_pct > 0) then
        batt_pct = 0
        battery:reset_remaining(batt_instance, batt_pct)
        cnt = 500
    end


    cnt = cnt + 1
    gcs:send_text(7,string.format("Batt%d, %.02fV, %.02f%%", cnt, voltage, batt_pct))
    

    return update, 2000
end

return update()