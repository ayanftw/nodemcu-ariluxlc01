-- file : application.lua
local module = {}
local flash_led = nil

local mqttclient = mqtt.Client('wifiled-' .. config.ID, 120, config.MQTT_USER, config.MQTT_PASS)
mqttclient:on("connect", function(client) print("connected") end)
mqttclient:on("offline", function(client) print("offline") end)


redPin = 5
greenPin = 1
bluePin = 6
whitePin = 7

pwm.setup(redPin, 500, 0)
pwm.setup(greenPin, 500, 0)
pwm.setup(bluePin, 500, 0)
pwm.setup(whitePin, 500, 0)
pwm.start(redPin)
pwm.start(bluePin)
pwm.start(greenPin)
pwm.start(whitePin)

local function map_value(value, max_in, max_out)
    if max_in == max_out then
        return value
    end
    return (value / max_in ) * max_out
end

local function get_state(max_out)
    max_out = max_out or 1023
    colour = {
        r = map_value(pwm.getduty(redPin), 1023, max_out),
        g = map_value(pwm.getduty(greenPin), 1023, max_out),
        b = map_value(pwm.getduty(bluePin), 1023, max_out),
        w = map_value(pwm.getduty(whitePin), 1023, max_out)
    }

    local state = 'OFF'
    for k, v in pairs(colour) do
        if v > 0 then
            state = 'ON'
            break
        end
    end

    return {
        colour = colour,
        color = colour,
        state = state
    }
end

local function mqtt_update()
    ok, json = pcall(cjson.encode, get_state(255))

    if ok then
        mqttclient:publish(config.ENDPOINT .. config.ID .. "/state/", json, 0, 0)
    else
        print("failed to encode!")
    end
end

local function set_colour(r, g, b, w)
    -- duty cycle ranges from 0-1023
    r = r or 0
    g = g or 0
    b = b or 0
    w = w or 0
    pwm.setduty(redPin, r)
    pwm.setduty(greenPin, g)
    pwm.setduty(bluePin, b)
    pwm.setduty(whitePin, w)
end

local function send_ping()
    mqttclient:publish(config.ENDPOINT .. "ping", "id=" .. config.ID, 0, 0)
end

local function mqtt_start()
    local pingtimer = tmr.create()
    pingtimer:register(1000, tmr.ALARM_AUTO, function(t)
        if not pcall(send_ping) then
            flash_led(1)
        end
    end)
    -- Connect to broker
    mqttclient:connect(config.MQTT_HOST, config.MQTT_PORT, 0, 1, function(client)
        topic = config.ENDPOINT .. config.ID
        client:subscribe(topic, 1, function(conn)
            print("subscribed at " .. topic)
        end)
        pingtimer:start()
    end,
    function(client, reason)
        print("failed: " .. reason)
    end)
end

local function update_colour(r, g, b, w)
    set_colour(r, g, b, w)
    if pcall(mqtt_update) then
        print("updating mqtt")
    else
        print("failed to update mqtt")
        --flash_led(1)
    end
end

local function flash_led(num)
    num = num or 1
    current = get_state().colour
    sw = true
    local flash_timer = tmr.create()
    flash_timer:register(500, tmr.ALARM_AUTO, function(timer)
        if (sw) then
            set_colour(1023, 0, 0, 0)
        else
            set_colour(current.r, current.g, current.b, current.w)
            num = num - 1
        end
        if num <= 0 then
            flash_timer:unregister()
        end
        sw = not sw
    end)
    flash_timer:start()
end

local function handle_message(client, topic, message)
    -- register message callback beforehand
    if message ~= nil then
        --print(topic .. ": " .. message)
        m = cjson.decode(message)
        if m.state == 'ON' then
            if m.color then
                r = map_value(m.color.r, 255, 1023)
                g = map_value(m.color.g, 255, 1023)
                b = map_value(m.color.b, 255, 1023)
                update_colour(r,g,b,0)
            else
                update_colour(1023,1023,1023,1023)
            end
        elseif m.state == 'OFF' then
            update_colour(0,0,0,0)
        end
    end
end
mqttclient:on("message", handle_message)

function module.start()
    mqtt_start()
end


return module
