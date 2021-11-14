-- local variables for API functions. any changes to the line below will be lost on re-generation
local client_set_event_callback, entity_get_players, globals_frametime, globals_tickcount, math_floor, renderer_measure_text, renderer_text, renderer_world_to_screen, require, string_upper, ui_get, ui_new_checkbox, ui_new_color_picker, ui_reference, pairs = client.set_event_callback, entity.get_players, globals.frametime, globals.tickcount, math.floor, renderer.measure_text, renderer.text, renderer.world_to_screen, require, string.upper, ui.get, ui.new_checkbox, ui.new_color_picker, ui.reference, pairs

local Vector    = require("vector")
local Entity    = require("gamesense/entity")

local MasterSwitch  = ui_new_checkbox("VISUALS", "Effects", "Miss marker")
local IconCol       = ui_new_color_picker("VISUALS", "Effects", "Miss marker", 238, 147, 147, 255)
local ExtraSwitch   = ui_new_checkbox("VISUALS", "Effects", "Extra info")
local ExtraCol      = ui_new_color_picker("VISUALS", "Effects", "Miss marker reason", 255, 255, 255, 255)
local DpiCombo      = ui_reference("MISC", "Settings", "DPI scale")

-- How long it stays before beginning to fade out
local _WaitTime = 2.5
-- How long it takes to fade out in seconds
local _FadeTime = 0.5

local Shots = {}
local Angles = {}

local function Clamp(v, mn, mx)
    return v < mn and mn or v > mx and mx or v
end

local function GetAngle(Player)
    if not Player then
        return "0°"
    end

    local EntityObj     = Entity.new(Player)
    local GoalFeetYaw   = EntityObj:get_anim_state().goal_feet_yaw
    local EyeAngles     = Vector(EntityObj:get_prop("m_angEyeAngles"))
    if EyeAngles.y < 0 then
        EyeAngles.y = EyeAngles.y + 360
    end

    return Clamp(math_floor(((EyeAngles.y - GoalFeetYaw + 180) % 360 - 180) + 0.5), -60, 60) .. "°"
end

local MissReasonFmt = 
{
    ["prediction error"]    = "PREDICTION",
    ["unregistered shot"]   = "UNREGISTERED",
    ["?"]                   = "UNKNOWN"
}

local MissValues = 
{
    ["UNKNOWN"]     = function(Shot)
        if not Shot.target then
            return "0°"
        end

        return (Angles[Shot.target] and Angles[Shot.target][Shot.tick]) or GetAngle(Shot.target)
    end,
    ["SPREAD"]      = function(Shot) return math_floor(Shot.hit_chance + 0.5) .. "%" end,
    ["PREDICTION"]  = function(Shot) return globals_tickcount() - Shot.tick .. "t" end
}

local function OnPaint()
    local bMaster, bExtra   = ui_get(MasterSwitch), ui_get(ExtraSwitch)
    local IconColor = {ui_get(IconCol)}
    local TextColor = {ui_get(ExtraCol)}
    local Dpi       = ui_get(DpiCombo):gsub('%%', '') / 100

    for i, Miss in pairs(Shots) do
        if not bMaster or Miss.FadeTime <= 0 then
            Shots[i] = nil
        else
            Miss.WaitTime      = Miss.WaitTime - globals_frametime()
            if Miss.WaitTime <= 0 then
                Miss.FadeTime  = Miss.FadeTime - ((1 / _FadeTime) * globals_frametime())
            end

            local x, y = renderer_world_to_screen(Miss.Pos.x, Miss.Pos.y, Miss.Pos.z)
            if x and Miss.Reason and Miss.FadeTime > 0.05 then
                local IconSize = Vector(renderer_measure_text("d", "❌"))
                local IconPos = Vector(x - (IconSize.x / 2), y - (IconSize.y / 2))

                renderer_text(IconPos.x, IconPos.y, IconColor[1], IconColor[2], IconColor[3], IconColor[4] * Miss.FadeTime, "d", 0, "❌")
                renderer_text(IconPos.x + IconSize.x, IconPos.y - ((10 * Dpi) * (1 - Miss.FadeTime)), TextColor[1], TextColor[2], TextColor[3], TextColor[4] * Miss.FadeTime, "d-", 0, Miss.Reason)

                if bExtra and Miss.Value then
                    local ReasonSize = Vector(renderer_measure_text("d-", Miss.Reason))
                    renderer_text(IconPos.x + IconSize.x, IconPos.y + (ReasonSize.y * 0.8) - ((10 * Dpi) * (1 - Miss.FadeTime)), TextColor[1], TextColor[2], TextColor[3], TextColor[4] * Miss.FadeTime, "d-", 0, Miss.Value)
                end
            end
        end
    end
end

local function OnRunCommand()
    local Enemies = entity_get_players(true)
    for Key, Index in pairs(Enemies) do
        if not Angles[Index] then
            Angles[Index] = {}
        end

        local TickCount = globals_tickcount()
        Angles[Index][TickCount] = GetAngle(Index)
        -- Calculating total backtrackable amount is really not necessary
        for i, v in pairs(Angles[Index]) do
            if TickCount - i > 64 then
                Angles[Index][i] = nil
            end
        end
    end
end

local function OnShotFired(Shot)
    if not ui_get(MasterSwitch) then
        return end

    Shots[Shot.id] = 
    {
        Pos         = Vector(Shot.x, Shot.y, Shot.z),
        WaitTime    = _WaitTime,
        FadeTime    = 1,
    }
end

local function OnShotMiss(Shot)
    if not ui_get(MasterSwitch) then
        return end

    local Reason            = string_upper(MissReasonFmt[Shot.reason] or Shot.reason)
    Shots[Shot.id].Reason   = Reason
    Shots[Shot.id].Value    = MissValues[Reason] and MissValues[Reason](Shot) or nil
end

client_set_event_callback('paint',          OnPaint)
client_set_event_callback('run_command',    OnRunCommand)
client_set_event_callback('aim_fire',       OnShotFired)
client_set_event_callback('aim_miss',       OnShotMiss)
