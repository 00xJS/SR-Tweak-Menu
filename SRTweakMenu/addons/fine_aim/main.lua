-- Fine Aim - Precision Gunplay 1.5.4 by car123609!,
-- https://github.com/car123609/SaintsReborn-Fine-Aim-Precision-Gunplay
-- Bundled with SR Tweak Menu with the author's permission. One change, marked
-- SR Tweak Menu below: the menu switches the mod on and off instead of enable_key.

-- Fine Aim for Whompay's Mod Loader, using the supplied TU0 XEX layout.
-- Selects the player's native ready locomotion poses only during fine aim.
-- No game files or weapon tables are replaced.
-- The random direction helper takes COS(spread angle), not the angle itself.

local CAMERA = 0x827D9778
local CAMERA_MODE = 0x827DA15C
local PLAYER = 0x8309ABEC
local OBJECTS = 0x830866C8
local GAME_UPDATE = 0x82209E30
local FOLLOW_CAMERA = 0x8210D518
local CAMERA_UPDATE = 0x82109608
local HORIZONTAL_TURN = 0x8210CFE0
local VERTICAL_TURN = 0x8210C9E0
local SLOW_PAN_H, SLOW_PAN_V = 0x827D9348, 0x827D934C
local FAST_PAN_H, FAST_PAN_V = 0x827D9340, 0x827D9344
local RANDOM_CONE = 0x82629DE8
local HUD_SPREAD = 0x82475548
local HUMAN_UPDATE = 0x82456550
local ANIMATION_STATE = 0x8244E018
local WEAPON_READY = 0x82449708
local WEAPON_RELOAD = 0x82474AB0
local LOCOMOTION_UPDATE = 0x82440200
local CONTROLLER_INPUT = 0x82788EC4 -- XamInputGetState, xam ordinal 0x191.
local SHOT_RETURNS = { [0x824717B8] = true, [0x82471F5C] = true }
local SHOT_READY_RETURNS = { [0x82470E24] = true, [0x82471404] = true }
local ON_FOOT_MODES = { [6] = true, [15] = true, [16] = true, [17] = true, [18] = true }
local AIRBORNE_MODES = { [2] = true, [3] = true, [4] = true }
local MENU_SLOTS = { 0x839E0DF8, 0x839E0FB0, 0x82FFE434, 0x82FFE43C }

local function finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function bounded_setting(name, default, low, high)
    local value = wml.setting(name, default)
    if not finite(value) then return default end
    return math.max(low, math.min(high, value))
end

local enabled = wml.setting("enabled", true)
local aim_key = wml.setting("aim_key", 2)
local enable_key = wml.setting("enable_key", "F8")
local secondary_key = wml.setting("secondary_key", "ALT")
local toggle_aim = wml.setting("toggle_aim", false)
local controller_enabled = wml.setting("controller_enabled", true)
local controller_toggle = wml.setting("controller_toggle", true)
local controller_button = tostring(wml.setting("controller_button", "RS")):upper()
local trigger_threshold = math.floor(bounded_setting("controller_trigger_threshold", 120, 25, 245))
if controller_button == "R3" or controller_button == "RIGHT_STICK" then controller_button = "RS" end
if controller_button == "L2" or controller_button == "LEFT_TRIGGER" then controller_button = "LT" end
if controller_button ~= "RS" and controller_button ~= "LT" then
    wml.log("Unknown controller_button; using RS (right-stick click). Supported values: RS or LT.")
    controller_button = "RS"
end
local keep_scopes = wml.setting("preserve_native_scopes", true)
local include_launchers = wml.setting("include_launchers", true)
local raise_weapon = wml.setting("raise_weapon", true)
local face_camera = wml.setting("face_camera_while_aiming", true)
local cancel_when_running = wml.setting("cancel_when_running", true)
local debug = wml.setting("debug", false)
local fov_multiplier = bounded_setting("fov_multiplier", 0.75, 0.25, 1.0)
local sensitivity = bounded_setting("sensitivity_multiplier", 0.25, 0.05, 1.0)
local spread_multiplier = bounded_setting("spread_multiplier", 0.25, 0.0, 1.0)
local aim_in_time = bounded_setting("aim_in_time", 0.12, 0.0, 2.0)
local aim_out_time = bounded_setting("aim_out_time", 0.10, 0.0, 2.0)
local post_shot_hold_ms = math.floor(bounded_setting("post_shot_hold_ms", 150, 0, 2500))

-- Fail before taking any keys or installing hooks on another executable layout.
-- These words verify the camera addresses, the equipped-gun pointer chain,
-- the shooter register, shot-spread call sites and locomotion state chooser.
local signatures = {
    { FOLLOW_CAMERA, 0x7D8802A6 },
    { 0x8210D53C, 0x3B8BA158 },
    { CAMERA_UPDATE, 0x7D8802A6 },
    { 0x82109620, 0x3BEB9778 },
    { HORIZONTAL_TURN, 0x7D8802A6 },
    { VERTICAL_TURN, 0x7D8802A6 },
    { 0x8210D080, 0x396B9340 },
    { 0x8210D0DC, 0xC00B0008 },
    { 0x8210D0E8, 0xD01F0148 },
    { 0x8210D10C, 0xC06B0000 },
    { 0x8210CA58, 0x3BAB9344 },
    { 0x8210CEA8, 0xC1BD0008 },
    { 0x8210CED4, 0x387F014C },
    { 0x8210CF44, 0xC15F0154 },
    { GAME_UPDATE, 0x7D8802A6 },
    { RANDOM_CONE, 0x7D8802A6 },
    { 0x82629E14, 0x4BFFFC05 },
    { HUD_SPREAD, 0x7D8802A6 },
    { 0x82470A70, 0x7C761B78 },
    { 0x82470A84, 0x81760DDC },
    { 0x82470A90, 0x830B0010 },
    { 0x82470A9C, 0x81F80008 },
    { 0x824717B4, 0x481B8635 },
    { 0x82471F58, 0x481B7E91 },
    { 0x82788ECC, 0x7D6903A6 },
    { 0x82788ED0, 0x4E800420 },
    { HUMAN_UPDATE, 0x7D8802A6 },
    { 0x82456568, 0x7C7F1B78 },
    { ANIMATION_STATE, 0x7D8802A6 },
    { 0x8244E024, 0x7CBF2B78 },
    { 0x82440230, 0x827F01FC },
    { 0x8244023C, 0x825F0200 },
    { 0x82434D80, 0x82435014 },
    { 0x82434D84, 0x8243517C },
    { 0x827D2290, 0x82059F4C },
    { 0x827D22FC, 0x82059D94 },
    { 0x827D2350, 0x82059C5C },
    { 0x827D2434, 0x82059850 },
    { WEAPON_READY, 0x7D8802A6 },
    { 0x82449730, 0x388509C4 },
    { 0x82470E20, 0x4BFD88E9 },
    { 0x82471400, 0x4BFD8309 },
    { WEAPON_RELOAD, 0x7D8802A6 },
    { 0x82474ADC, 0x834B0010 }, -- Equipped weapon in the reload entry.
    { 0x82474898, 0x816B001C }, -- Native reloading query reads weapon +28.
    { 0x824750D8, 0x387A001C }, -- Reload entry starts that same timer.
    { 0x824727B8, 0x556B035A }, -- Pending reload request: player +212, bit 0x40000.
    { LOCOMOTION_UPDATE, 0x7D8802A6 },
    { 0x82440A84, 0x931F0240 }, -- Native pose update commits the locomotion state.
    { 0x82440AA0, 0x4BDE6309 }, -- It resolves the corresponding skeleton animation too.
    { 0x8244E194, 0x8244E680 }, -- Airborne movement modes in the native chooser.
    { 0x8244E198, 0x8244E740 },
    { 0x8244E19C, 0x8244E794 },
    { 0x827D25F0, 0x82059050 }, -- Locomotion state 0x86: calm fall.
    { 0x827D2BD0, 0x82057CE8 }, -- Action 0x20: jump start.
}
for _, expected in ipairs(signatures) do
    if wml.read_u32(expected[1]) ~= expected[2] then
        wml.log(string.format("Fine Aim disabled: unsupported executable at %08X. Use the SaintsReborn-main(2) build.", expected[1]))
        return
    end
end

-- This WML build reports some MinHook failures with a Lua formatting error.
-- Contain optional hook failures so later features still get registered.
local function install_hook(address, callback)
    local ok, message = pcall(wml.hook, address, callback)
    if not ok then
        wml.log(string.format("Fine Aim hook unavailable at %08X: %s", address, tostring(message)))
    end
    return ok
end

local frame = 0
local follow_frame = -100
local step_frame = -1
local frame_dt = 1 / 60
local blend = 0
local latched = false
local capture = false
local last_active = false
local shots_tightened = 0
local owned_fov, normal_fov
local controller_latched = false
local controller_down = false
local controller_held = false
local controller_blocked = false
local controller_last_poll = -100
local controller_owner, controller_handle
local controller_sprinting = false
local controller_look_active = false
local movement_owner, movement_handle, requested_sprint
local movement_frame = -100
local requested_jump = false
local reload_call_player, reload_call_handle

local function pointer(p)
    return type(p) == "number" and p >= 0x10000 and p <= 0xFFFFFF00 and (p & 3) == 0
end

local function local_player()
    local p = wml.read_u32(PLAYER)
    if not pointer(p) or wml.read_u32(p + 72) ~= 1 then return nil end
    local handle = wml.read_u32(p + 68)
    local index = handle & 0xFFFF
    if handle == 0 or index >= 4096 then return nil end
    if wml.read_u32(OBJECTS + 12 + index * 16) ~= p then return nil end
    return p
end

local function normal_gun(player)
    local inventory = wml.read_u32(player + 3548)
    if not pointer(inventory) then return false end
    local weapon = wml.read_u32(inventory + 16)
    if not pointer(weapon) then return false end
    local info = wml.read_u32(weapon + 8)
    if not pointer(info) then return false end
    -- Weapon_Class enum: pistol 0, SMG 1, rifle 2, shotgun 3, launcher 4;
    -- thrown 5 and melee 6-10. Info +12 bit 0x80 is the native "can zoom" flag.
    local class = wml.read_u32(info + 20)
    if class > (include_launchers and 4 or 3) then return false end
    if keep_scopes and (wml.read_u8(info + 12) & 0x80) ~= 0 then return false end
    return true
end

local function jumping(player)
    -- Catch takeoff and landing as well as the airborne part. Checking the
    -- actual actions works with keyboard, controller and remapped controls.
    if AIRBORNE_MODES[wml.read_u32(player + 508)] then return true end
    local state = wml.read_u32(player + 576)
    if state >= 0x86 and state <= 0x8C then return true end
    for _, offset in ipairs({756, 764, 772}) do
        local action = wml.read_u32(player + offset)
        if action >= 0x20 and action <= 0x37 then return true end
    end
    -- The native chooser can receive a jump request before the actor's
    -- committed fields change. Cover that first update too.
    return movement_owner == player and movement_handle == wml.read_u32(player + 68)
        and frame - movement_frame <= 1 and requested_jump
end

local function eligible()
    if not enabled or frame - follow_frame > 3 then return nil end
    if controller_blocked then return nil end
    if wml.read_u32(CAMERA) ~= 0 or not ON_FOOT_MODES[wml.read_u32(CAMERA_MODE)] then return nil end
    if wml.read_u8(0x8370D990) ~= 0 or wml.read_u8(0x8370D991) ~= 0 then return nil end
    for _, address in ipairs(MENU_SLOTS) do
        if wml.read_u32(address) ~= 0 then return nil end
    end
    if wml.key_down("Q") then return nil end
    local p = local_player()
    if not p then return nil end
    if jumping(p) then return nil end
    -- A vehicle handle also blocks ADS during getting in or getting out.
    if wml.read_u32(p + 2496) ~= 0 then return nil end
    if wml.read_u32(p + 3700) ~= 0xFFFFFFFF then return nil end
    -- The body's up vector rejects ragdoll/tumbling without changing animation.
    local up_y = wml.read_f32(p + 48)
    if not finite(up_y) or up_y < 0.5 then return nil end
    if not normal_gun(p) then return nil end
    return p
end

local function running(p)
    if not cancel_when_running then return false end
    if controller_sprinting or wml.key_down("SHIFT") then return true end
    -- Normal left-stick/WASD movement can use minor 2 and animations named
    -- "run". Those must remain aimable. Minor 3 is the faster sprint action.
    -- Do not cancel from a pose ID: old/preview/blended run poses can still
    -- appear while the player is walking or has just stopped sprinting.
    if wml.read_u32(p + 508) == 0 and wml.read_u32(p + 512) == 3 then return true end
    -- The chooser receives a sprint request before it is committed to the
    -- actor. Remember that request, rather than its returned animation ID.
    return movement_owner == p and movement_handle == wml.read_u32(p + 68)
        and frame - movement_frame <= 1 and requested_sprint == true
end

local function aiming(p)
    p = p or eligible()
    if not p or jumping(p) or running(p) then return false end
    local mouse = toggle_aim and latched or (not toggle_aim and wml.key_down(aim_key))
    local valid_controller = controller_enabled and controller_owner == p
        and controller_handle == wml.read_u32(p + 68)
    local controller = valid_controller and
        (controller_toggle and controller_latched or (not controller_toggle and controller_held))
    return mouse or controller
end

local function clear_controller()
    controller_latched = false
    controller_held = false
    controller_owner, controller_handle = nil, nil
    -- Keep the sampled button state: returning from a menu with RS still held
    -- must not count as a new press. A physical release arms the next toggle.
end

-- Native animation state IDs, verified in the table at 0x827D1FA8.
-- Map only ordinary locomotion; firing/reload actions use separate slots.
local READY_STATES = {
    [0x00] = 0x3E, [0x01] = 0x3F, [0x02] = 0x40, [0x03] = 0x3E,
    [0x04] = 0x61, [0x05] = 0x62,
    [0x44] = 0x48, [0x45] = 0x49, [0x46] = 0x4A,
    [0x4B] = 0x4F, [0x4C] = 0x50, [0x4D] = 0x51,
    [0x52] = 0x55, [0x53] = 0x56, [0x54] = 0x57,
    [0x58] = 0x5B, [0x59] = 0x5C, [0x5A] = 0x5D,
    [0x5E] = 0x63, [0x5F] = 0x64, [0x60] = 0x65,
    -- Use running-ready rather than the arm-swinging sprint animations during
    -- fine aim. Directional inputs, movement requests and stamina stay native.
    [0x33] = 0x4E, [0x34] = 0x4F, [0x35] = 0x50, [0x36] = 0x51,
    [0x37] = 0x4E, [0x38] = 0x4E,
}
for state = 0x1A, 0x2B do READY_STATES[state] = 0x47 end -- walk variants
for state = 0x2D, 0x32 do READY_STATES[state] = 0x4E end -- run variants

local function reloading(player)
    -- The native reload entry selects the action before starting the weapon
    -- timer. Yield throughout that call, including its nested pose queries.
    if reload_call_player == player and reload_call_handle == wml.read_u32(player + 68) then
        return true
    end
    -- Manual reload requests and empty-clip automatic reloads precede the
    -- animation action. Looking only in the action slots misses this phase.
    if (wml.read_u32(player + 212) & 0x00040000) ~= 0 then return true end
    local inventory = wml.read_u32(player + 3548)
    if not pointer(inventory) then return false end
    local weapon = wml.read_u32(inventory + 16)
    if not pointer(weapon) then return false end
    -- Weapon +28 is the native reload deadline, not a remaining duration.
    -- Its high bit marks an inactive timer (normally 0xFFFFFFFF). Do not
    -- compare it to a frame count or edit it; the engine owns completion.
    if (wml.read_u32(weapon + 28) & 0x80000000) == 0 then return true end
    local clip = wml.read_u32(weapon + 16)
    local reserve = wml.read_u32(weapon + 20)
    return clip == 0 and reserve > 0 and reserve < 0x80000000
end

local function can_pose(player)
    if not player or wml.read_u32(player + 952) ~= 0xFFFFFFFF then return false end
    local up_y = wml.read_f32(player + 48)
    if not finite(up_y) or up_y < 0.9 then return false end
    if reloading(player) then return false end
    -- Three active action slots. Action names come from the executable's
    -- table at 0x827D2A50: reload/walk/run/crouch/passenger reload, plus
    -- the two helicopter passenger reload variants.
    for _, offset in ipairs({756, 764, 772}) do
        local action = wml.read_u32(player + offset)
        if (action >= 0xA4 and action <= 0xAD) or action == 0x251 or action == 0x253 then
            return false
        end
    end
    return true
end

local function pose_player()
    local player = eligible()
    return player and aiming(player) and can_pose(player) and player or nil
end

local function face_aim_camera()
    if not face_camera then return end
    local player = pose_player()
    if not player then return end
    -- Turn the root towards the camera's yaw; native weapon/bone aiming
    -- supplies the pitch. Do not tilt the whole character when looking up.
    local fx = wml.read_f32(CAMERA + 104)
    local fz = wml.read_f32(CAMERA + 112)
    if not finite(fx) or not finite(fz) then return end
    local length = math.sqrt(fx * fx + fz * fz)
    if length < 0.001 then return end
    fx, fz = fx / length, fz / length
    local matrix = {}
    for i = 1, 9 do
        matrix[i] = wml.read_f32(player + 28 + i * 4)
        if not finite(matrix[i]) then return end
    end
    local ux, uy, uz = matrix[4], matrix[5], matrix[6]
    local up_length = math.sqrt(ux * ux + uy * uy + uz * uz)
    if up_length < 0.001 then return end
    ux, uy, uz = ux / up_length, uy / up_length, uz / up_length
    local dot = ux * fx + uz * fz
    local fy
    fx, fy, fz = fx - dot * ux, -dot * uy, fz - dot * uz
    length = math.sqrt(fx * fx + fy * fy + fz * fz)
    if length < 0.001 then return end
    fx, fy, fz = fx / length, fy / length, fz / length
    -- Preserve the model matrix's handedness, as the bundled First Person
    -- mod does. Preserve its up vector for slightly sloped surfaces too.
    local old_rx = uy * matrix[9] - uz * matrix[8]
    local old_ry = uz * matrix[7] - ux * matrix[9]
    local old_rz = ux * matrix[8] - uy * matrix[7]
    local handedness = old_rx * matrix[1] + old_ry * matrix[2] + old_rz * matrix[3]
    if math.abs(handedness) < 0.001 then return end
    local sign = handedness >= 0 and 1 or -1
    local result = { sign * (uy * fz - uz * fy), sign * (uz * fx - ux * fz),
        sign * (ux * fy - uy * fx), ux, uy, uz, fx, fy, fz }
    for i, value in ipairs(result) do wml.write_f32(player + 28 + i * 4, value) end
    -- On release the engine resumes steering from this heading; restoring
    -- the pre-aim heading would snap the player back in the old direction.
end

local function restore_fov()
    if owned_fov then
        local current = wml.read_f32(CAMERA + 188)
        -- Another camera/mod may have replaced the value since our last write.
        if finite(current) and math.abs(current - owned_fov) < 0.001 then
            wml.write_f32(CAMERA + 188, normal_fov)
        end
    end
    owned_fov, normal_fov = nil, nil
end

local function reset_view()
    restore_fov()
    blend = 0
    step_frame = -1
end

local function update_bindings()
    local player = eligible()
    local supported = player ~= nil
    if supported ~= capture then
        wml.take_key(aim_key, supported)
        capture = supported
    end
    -- wml.force_key bypasses take_key in the built-in controls. Alt therefore
    -- provides the original secondary attack without making it an ADS request.
    local original_secondary = supported and wml.key_down(secondary_key)
    wml.force_key(2, original_secondary)
    if not supported or running(player) then
        latched = false
        clear_controller()
        reset_view()
    end
end

-- Register physical key watches before the first rendered frame.
wml.key_down(aim_key)
wml.key_down(secondary_key)
wml.key_down(enable_key)
wml.key_down("Q")
wml.key_down(4) -- Middle mouse can be translated to right-stick click by KBM.
wml.key_down("V")
wml.key_down("SHIFT")

wml.on_frame(function()
    frame = frame + 1
    -- SR Tweak Menu: the menu's Aim tab switches Fine Aim on and off.
    local switched
    if type(wml.srtm) == "table" then
        switched = wml.srtm.live() ~= enabled
    else
        switched = wml.key_pressed(enable_key)
    end
    if switched then
        enabled = not enabled
        latched = false
        clear_controller()
        wml.log(enabled and "Fine Aim on" or "Fine Aim off")
    end
    local player = eligible()
    if toggle_aim and player and not running(player) and wml.key_pressed(aim_key) then latched = not latched end
    if frame - controller_last_poll > 12 then
        clear_controller()
        controller_blocked = false
        controller_sprinting = false
        controller_look_active = false
    end
    update_bindings()
    if debug then
        local active = aiming()
        if active ~= last_active then
            wml.log(string.format("Fine Aim %s; player shots tightened: %d", active and "engaged" or "released", shots_tightened))
        end
        last_active = active
    end
end)

do
    install_hook(CONTROLLER_INPUT, function(ctx)
        -- WML chains this after the port's own keyboard/controller mixer.
        -- Preserve the input arguments because the original returns status in r3.
        local user = ctx:r(3) & 0xFF
        local flags = ctx:r(4) & 0xFFFFFFFF
        local state = ctx:r(5) & 0xFFFFFFFF
        ctx:call_original()
        if (user ~= 0 and user ~= 0xFF) or not pointer(state) then return end
        if (flags & 0xFF) ~= 0 and (flags & 1) == 0 then return end
        if (ctx:r(3) & 0xFFFFFFFF) ~= 0 then
            clear_controller()
            controller_blocked = false
            controller_sprinting = false
            controller_look_active = false
            controller_down = false
            return
        end
        controller_last_poll = frame
        -- X_INPUT_STATE: packet +0, buttons +4, LT +6, RT +7, sticks +8..15.
        local buttons = wml.read_u16(state + 4)
        local rx = wml.read_u16(state + 12)
        local ry = wml.read_u16(state + 14)
        if rx >= 0x8000 then rx = rx - 0x10000 end
        if ry >= 0x8000 then ry = ry - 0x10000 end
        -- The port's mouse-look feed includes the physical controller too.
        -- Do not feed that controller component back as mouse correction.
        controller_look_active = math.abs(rx) >= 7864 or math.abs(ry) >= 7864
        if not controller_enabled then return end
        controller_sprinting = (buttons & 0x0200) ~= 0 -- RB/R1: native sprint.
        -- B opens the weapon wheel; Start/Back enter screens. Cancel immediately.
        controller_blocked = (buttons & 0x2030) ~= 0
        local down, synthetic
        if controller_button == "LT" then
            local threshold = controller_down and (trigger_threshold - 25) or trigger_threshold
            down = wml.read_u8(state + 6) >= threshold
            synthetic = wml.key_down(2) or wml.key_down(secondary_key)
        else
            down = (buttons & 0x0080) ~= 0
            synthetic = wml.key_down(4) or wml.key_down("V")
        end
        local pressed = down and not controller_down
        controller_down = down
        local p = eligible()
        if not p then clear_controller() return end
        local handle = wml.read_u32(p + 68)
        if controller_owner ~= p or controller_handle ~= handle then clear_controller() end
        controller_owner, controller_handle = p, handle
        controller_held = down and not synthetic
        if running(p) then
            latched = false
            clear_controller()
            reset_view()
        elseif controller_toggle and pressed and not synthetic then
            controller_latched = not controller_latched
            if debug then wml.log("Controller fine aim " .. (controller_latched and "on" or "off")) end
        end
        -- Reserve only the configured aim control during supported gameplay.
        -- Native sniper scopes and menu/vehicle controls passed through above.
        local changed = false
        if controller_button == "RS" then
            local filtered = buttons & 0xFF7F
            if filtered ~= buttons then wml.write_u16(state + 4, filtered) changed = true end
        elseif not synthetic and wml.read_u8(state + 6) ~= 0 then
            wml.write_u8(state + 6, 0)
            changed = true
        end
        if changed then
            wml.write_u32(state, (wml.read_u32(state) + 1) & 0xFFFFFFFF)
        end
    end)
end

-- Apply the contextual binding before the recurring gameplay update as well
-- as during render callbacks, so a gun/scope/menu transition releases it.
install_hook(GAME_UPDATE, function(ctx)
    update_bindings()
    ctx:call_original()
end)

local reload_prepare_error_reported = false
local function prepare_standing_reload(ctx, player)
    if not raise_weapon or eligible() ~= player or not aiming(player) then return end
    if wml.read_u32(player + 508) ~= 0 or wml.read_u32(player + 512) ~= 0 then return end
    if wml.read_u32(player + 952) ~= 0xFFFFFFFF then return end
    local up_y = wml.read_f32(player + 48)
    if not finite(up_y) or up_y < 0.9 then return end
    -- Do not reset an animation which has already started. The reload entry
    -- may be queried again while its timer or action is still active.
    for _, offset in ipairs({756, 764, 772}) do
        local action = wml.read_u32(player + offset)
        if (action >= 0xA4 and action <= 0xAD) or action == 0x251 or action == 0x253 then return end
    end
    local inventory = wml.read_u32(player + 3548)
    if not pointer(inventory) then return end
    local weapon = wml.read_u32(inventory + 16)
    if not pointer(weapon) or (wml.read_u32(weapon + 28) & 0x80000000) == 0 then return end
    local state = wml.read_u32(player + 576)
    if state < 0x3E or state > 0x40 then return end -- Stand-ready A/B/C.

    -- The chooser override only changes a returned state ID. An installed
    -- ready pose and its skeleton binding survive until the next native pose
    -- update, so merely yielding during reload is too late for its first call.
    -- Re-evaluate that base through the engine before selecting/playing reload.
    -- The surrounding reload scope suppresses our chooser override here.
    local registers, floats = {}, {}
    for n = 0, 31 do registers[n], floats[n] = ctx:r(n), ctx:f(n) end
    local ok, message = pcall(function()
        ctx:set_r(3, player)
        ctx:set_r(4, -1) -- Preserve the native movement mode.
        ctx:set_r(5, -1) -- Preserve the native movement minor.
        ctx:set_r(6, 1)  -- Force the native pose evaluation.
        ctx:call(LOCOMOTION_UPDATE)
    end)
    -- A game call can clobber volatile registers. The original reload must
    -- receive exactly the context its caller supplied, including float args.
    for n = 0, 31 do ctx:set_r(n, registers[n]) ctx:set_f(n, floats[n]) end
    if not ok and not reload_prepare_error_reported then
        reload_prepare_error_reported = true
        wml.log("Fine Aim standing reload preparation unavailable: " .. tostring(message))
    elseif ok and debug then
        wml.log("Standing Fine Aim reload: native base refreshed before reload.")
    end
end

-- Suspend only the pose/root override while the native reload begins. Keep
-- the mouse/controller aim latch, zoom and sensitivity intact, so fine aim
-- resumes without another press after the engine finishes the reload.
local standing_reload_hook = install_hook(WEAPON_RELOAD, function(ctx)
    local player = ctx:r(3) & 0xFFFFFFFF
    if player ~= local_player() then ctx:call_original() return end
    local previous_player, previous_handle = reload_call_player, reload_call_handle
    reload_call_player, reload_call_handle = player, wml.read_u32(player + 68)
    local ok, message = pcall(function()
        if previous_player ~= player then prepare_standing_reload(ctx, player) end
        ctx:call_original()
    end)
    reload_call_player, reload_call_handle = previous_player, previous_handle
    if not ok then error(message, 0) end
end)

-- The game queries this chooser during animation updates, even when the
-- player keeps the same movement input. Return the appropriate ready pose
-- without repeatedly playing an action or editing gun-ready/firing timers.
install_hook(ANIMATION_STATE, function(ctx)
    local player = (ctx:r(5) & 0xFFFFFFFF)
    local movement_mode = ctx:r(3) & 0xFFFFFFFF
    local movement_minor = ctx:r(4) & 0xFFFFFFFF
    local local_call = player == local_player()
    if local_call and AIRBORNE_MODES[movement_mode] then
        movement_owner, movement_handle = player, wml.read_u32(player + 68)
        requested_jump, requested_sprint, movement_frame = true, false, frame
        latched = false
        clear_controller()
        reset_view()
    end
    local use_ready = raise_weapon and player == wml.read_u32(PLAYER)
        and pose_player() == player
    ctx:call_original()
    if local_call and player == local_player() then
        movement_owner, movement_handle = player, wml.read_u32(player + 68)
        requested_sprint = movement_mode == 0 and movement_minor == 3
        local state = ctx:r(3) & 0xFFFFFFFF
        requested_jump = AIRBORNE_MODES[movement_mode] == true
            or (state >= 0x86 and state <= 0x8C)
        movement_frame = frame
        if requested_jump or (cancel_when_running and requested_sprint) then
            latched = false
            clear_controller()
            reset_view()
        end
    end
    if use_ready and pose_player() == player then
        local replacement = READY_STATES[ctx:r(3) & 0xFFFFFFFF]
        if replacement then ctx:set_r(3, replacement) end
    end
end)

-- Native firing raises the gun twice: first with zero extra duration, then
-- with the actual firing-animation length in milliseconds. The ready setter
-- adds a 2500 ms tail. Reduce only that tail, including for normal hip fire.
-- Do not keep rewriting the timer or clear the firing action on subsequent
-- frames: doing so can interrupt animation completion or preserve stale state.
install_hook(WEAPON_READY, function(ctx)
    local shot = SHOT_READY_RETURNS[ctx:lr() & 0xFFFFFFFF]
    if not shot or not enabled or post_shot_hold_ms == 2500 or (ctx:r(4) & 0xFF) == 0 then
        ctx:call_original() return
    end
    local player = eligible()
    if not player or (ctx:r(3) & 0xFFFFFFFF) ~= player or not can_pose(player) then
        ctx:call_original() return
    end
    local original_extra = ctx:r(5)
    local extra_ms = original_extra & 0xFFFFFFFF
    if extra_ms > 60000 then ctx:call_original() return end
    ctx:set_r(5, extra_ms + post_shot_hold_ms - 2500)
    local ok, message = pcall(function() ctx:call_original() end)
    -- The firing caller reads r5 after this setter, so return the original
    -- animation length to it. Negative adjustment must not reach recoil math.
    ctx:set_r(5, original_extra)
    if not ok then error(message, 0) end
end)

-- Keep the body facing the aiming direction around the native human update.
-- The action slots, recoil, reloads and firing completion remain game-owned.
install_hook(HUMAN_UPDATE, function(ctx)
    local player_call = (ctx:r(3) & 0xFFFFFFFF) == wml.read_u32(PLAYER)
    if player_call then face_aim_camera() end
    ctx:call_original()
    if player_call then face_aim_camera() end
end)

-- Scale the whole supported follow-camera call. The compiled per-axis turn
-- functions at 8210CFE0/8210C9E0 are not hookable in the user's build.
local PAN_RATES = { SLOW_PAN_H, SLOW_PAN_V, FAST_PAN_H, FAST_PAN_V }
local mouse_helpers = type(wml.mouse_look) == "function" and type(wml.turn_camera) == "function"

local function camera_turn(ctx, dt, mouse_yaw, mouse_pitch)
    if not aiming() or sensitivity == 1 then ctx:call_original() return end
    local saved = {}
    for i, address in ipairs(PAN_RATES) do
        saved[i] = wml.read_f32(address)
        if not finite(saved[i]) then ctx:call_original() return end
    end
    local yaw_velocity = wml.read_f32(CAMERA + 328)
    local pitch_velocity = wml.read_f32(CAMERA + 332)
    local extra_pitch = wml.read_f32(CAMERA + 340)
    if not finite(yaw_velocity) or not finite(pitch_velocity) or not finite(extra_pitch) then
        ctx:call_original() return
    end
    for i, address in ipairs(PAN_RATES) do wml.write_f32(address, saved[i] * sensitivity) end
    wml.write_f32(CAMERA + 328, yaw_velocity * sensitivity)
    wml.write_f32(CAMERA + 332, pitch_velocity * sensitivity)

    local owned_pitch
    if mouse_helpers and not controller_look_active and finite(dt) and dt > 0.0001 and dt <= 0.5 then
        -- KBM installs unit pan rates inside this call when the mouse moves.
        -- Compensate its mouse deltas through the supplied WML yaw API and
        -- the native additive pitch-rate input instead of relying on leaf hooks.
        local yaw_correction = (sensitivity - 1) * mouse_yaw
        if yaw_correction ~= 0 then wml.turn_camera(yaw_correction) end
        if mouse_pitch ~= 0 then
            owned_pitch = extra_pitch + (sensitivity - 1) * mouse_pitch / dt
            wml.write_f32(CAMERA + 340, owned_pitch)
        end
    end
    local ok, message = pcall(function() ctx:call_original() end)
    local next_yaw = wml.read_f32(CAMERA + 328)
    local next_pitch = wml.read_f32(CAMERA + 332)
    for i, address in ipairs(PAN_RATES) do wml.write_f32(address, saved[i]) end
    wml.write_f32(CAMERA + 328, ok and finite(next_yaw) and next_yaw / sensitivity or yaw_velocity)
    wml.write_f32(CAMERA + 332, ok and finite(next_pitch) and next_pitch / sensitivity or pitch_velocity)
    if owned_pitch then
        local current = wml.read_f32(CAMERA + 340)
        if finite(current) and math.abs(current - owned_pitch) < 0.0001 then
            wml.write_f32(CAMERA + 340, extra_pitch)
        end
    end
    if not ok then error(message, 0) end
end

install_hook(FOLLOW_CAMERA, function(ctx)
    follow_frame = frame
    local dt = ctx:f(1)
    if finite(dt) and dt > 0 and dt <= 0.5 then frame_dt = math.min(dt, 0.1) end
    -- Drain the feed while inactive too, so entering aim cannot reuse old mouse deltas.
    local yaw, pitch = 0, 0
    if mouse_helpers then
        yaw, pitch = wml.mouse_look()
        if not finite(yaw) then yaw = 0 end
        if not finite(pitch) then pitch = 0 end
    end
    camera_turn(ctx, dt, yaw, pitch)
    face_aim_camera()
end)

install_hook(CAMERA_UPDATE, function(ctx)
    -- Restore the unzoomed input before the game's interpolation runs.
    -- Otherwise feeding our zoom back in would shrink FOV again each frame.
    restore_fov()
    ctx:call_original()
    if not eligible() then reset_view() return end
    face_aim_camera()
    local active = aiming()
    if step_frame ~= frame then
        step_frame = frame
        local goal = active and 1 or 0
        local duration = active and aim_in_time or aim_out_time
        local amount = duration > 0 and (1 - math.exp(-frame_dt / duration)) or 1
        blend = blend + (goal - blend) * amount
        if blend < 0.001 then blend = 0 end
        if blend > 0.999 then blend = 1 end
    end
    if blend == 0 then return end
    local base = wml.read_f32(CAMERA + 188)
    if not finite(base) or base < 10 or base > 170 then return end
    normal_fov = base
    local target = math.max(20, base * fov_multiplier)
    owned_fov = base + (target - base) * blend
    wml.write_f32(CAMERA + 188, owned_fov)
end)

install_hook(RANDOM_CONE, function(ctx)
    -- r22 is the shooter in the firearm function at 0x82470A50. Restricting
    -- both the return address and this pointer excludes NPCs, effects and the
    -- shotgun's separate pellet cone (return address 0x824717F4).
    if SHOT_RETURNS[ctx:lr() & 0xFFFFFFFF] and spread_multiplier < 1 then
        local p = eligible()
        if p and (ctx:r(22) & 0xFFFFFFFF) == p and aiming() then
            local cosine = ctx:f(1)
            if finite(cosine) and cosine >= -1.0001 and cosine <= 1.0001 then
                local angle = math.acos(math.max(-1, math.min(1, cosine)))
                ctx:set_f(1, math.cos(angle * spread_multiplier))
                shots_tightened = shots_tightened + 1
            end
        end
    end
    ctx:call_original()
end)

install_hook(HUD_SPREAD, function(ctx)
    -- Only change the HUD reticle call; the game's other uses of this getter
    -- keep their original values. The input r3 is the character pointer.
    local hud = (ctx:lr() & 0xFFFFFFFF) == 0x820D43D4
    local p = hud and eligible() or nil
    local tighten = p and (ctx:r(3) & 0xFFFFFFFF) == p and aiming()
    ctx:call_original()
    local angle = ctx:f(1)
    if tighten and finite(angle) and angle >= 0 and angle <= math.pi then
        ctx:set_f(1, angle * spread_multiplier)
    end
end)

if not standing_reload_hook then
    wml.log("Fine Aim standing reload fix unavailable: native reload-entry hook could not be installed.")
end
wml.log(string.format("Fine Aim 1.5.4 loaded: jumping blocks aim; native standing reload preparation %s; parent-camera sensitivity; walking allows aim; sprint cancels; post-shot hold %d ms; all code in main.lua. Hold right mouse; controller %s %s. Spread %.2fx, look %.2fx, FOV %.2fx. F8 toggles; Alt secondary attack.", standing_reload_hook and "active" or "unavailable", post_shot_hold_ms, controller_button, controller_toggle and "toggle" or "hold", spread_multiplier, sensitivity, fov_multiplier))
