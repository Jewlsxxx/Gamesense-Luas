-- local variables for API functions. any changes to the line below will be lost on re-generation
local client_color_log, client_create_interface, client_key_state, client_screen_size, client_set_event_callback, client_unset_event_callback, client_userid_to_entindex, database_read, database_write, entity_get_local_player, entity_get_player_name, entity_get_player_weapon, entity_get_players, entity_get_prop, globals_realtime, globals_tickcount, math_deg, math_floor, renderer_gradient, renderer_measure_text, renderer_rectangle, require, error, pcall, plist_get, renderer_load_rgba, renderer_text, renderer_texture, string_format, string_upper, ui_get, ui_is_menu_open, ui_menu_position, ui_menu_size, ui_mouse_position, ui_new_color_picker, ui_new_combobox, ui_new_multiselect, ui_reference, ui_set_callback, ui_set_visible, pairs = client.color_log, client.create_interface, client.key_state, client.screen_size, client.set_event_callback, client.unset_event_callback, client.userid_to_entindex, database.read, database.write, entity.get_local_player, entity.get_player_name, entity.get_player_weapon, entity.get_players, entity.get_prop, globals.realtime, globals.tickcount, math.deg, math.floor, renderer.gradient, renderer.measure_text, renderer.rectangle, require, error, pcall, plist.get, renderer.load_rgba, renderer.text, renderer.texture, string.format, string.upper, ui.get, ui.is_menu_open, ui.menu_position, ui.menu_size, ui.mouse_position, ui.new_color_picker, ui.new_combobox, ui.new_multiselect, ui.reference, ui.set_callback, ui.set_visible, pairs

local Vector    = require("vector")
local Weapons   = require("gamesense/csgo_weapons")
local Entity    = require("gamesense/entity")
local ffi       = require("ffi")

-- From solus ui
local HSVToRGB = function(b,c,d,e)local f,g,h;local i=math_floor(b*6)local j=b*6-i;local k=d*(1-c)local l=d*(1-j*c)local m=d*(1-(1-j)*c)i=i%6;if i==0 then f,g,h=d,m,k elseif i==1 then f,g,h=l,d,k elseif i==2 then f,g,h=k,d,m elseif i==3 then f,g,h=k,l,d elseif i==4 then f,g,h=m,k,d elseif i==5 then f,g,h=d,k,l end;return f*255,g*255,h*255,e*255 end

local RawEntityList         = client_create_interface("client_panorama.dll", "VClientEntityList003")    or error("Hitlist. RawEntityList not found", 2)
local EntityListInterface   = ffi.cast(ffi.typeof("void***"), RawEntityList)                            or error("Hitlist. EntityList interface is null", 2)
local GetClientEntity       = ffi.cast("void*(__thiscall*)(void*, int)", EntityListInterface[0][3])     or error("Hitlist. GetClientEntity is null", 2)

local ElementNames = 
{
    "Shot Index",
    "Player Name",
    "Targeted", 
    "Hit", 
    "Hitchance", 
    "Pred. Damage", 
    "Damage", 
    "Backtrack",
    "Angle",
    "Spread Angle",
    "Miss Reason"
}

local SelfElementNames = 
{
    "Player Name",
    "Weapon",
    "Hitgroup",
    "Damage",
}

-- Check for solus ui. If it isnt found create an empty table
local SolusCombo            = {pcall(ui_reference, "CONFIG", "Presets", "Solus Palette")}
local Solus = not SolusCombo[1] and {} or
{
    TypeCombo   = SolusCombo[2],
    FadeOffset  = ui_reference("CONFIG", "Presets", "Fade offset"),
    FadeRatio   = ui_reference("CONFIG", "Presets", "Fade split ratio"),
    FadeFreq    = ui_reference("CONFIG", "Presets", "Fade frequency"),
}

local DpiCombo              = ui_reference("MISC", "Settings", "DPI scale")
local ElementsCombo         = ui_new_multiselect("MISC", "Miscellaneous", "Hitlist", ElementNames)
local SelfElementCombo      = ui_new_multiselect("MISC", "Miscellaneous", "Local damage", SelfElementNames)
local ConsoleCombo          = ui_new_multiselect("MISC", "Miscellaneous", "Console Log", "Hitlist", "Local damage")
local StyleCombo            = ui_new_combobox("MISC", "Miscellaneous", "Style", "Solus", "Skeet", "Teamskeet")
local ColorPicker           = SolusCombo[1] and SolusCombo[3] or ui_new_color_picker("MISC", "Miscellaneous", "Style Color", 0, 123, 255, 150)

ui_set_callback(StyleCombo, function() if not SolusCombo[1] then ui_set_visible(ColorPicker,  ui_get(StyleCombo) == "Solus") end end)

local o, x = "\x00\x00\x00\x00", "\x14\x14\x14\xFF"
local BgTexture = renderer_load_rgba(table.concat{x, x, o, x,o, x, o, x,o, x, x, x,o, x, o, x}, 4, 4)

local HitlistInfo = 
{
    DatabaseName    = "Jewls Hitlist",
    Position        = Vector(500, 10),
    SelfPosition    = Vector(200, 10),
    Padding         = Vector(10, 3),
    Spacing         = 10,
    MaxShots        = 7,
    InDrag          = false,
    MovementInfo    = {},
    LocalMovementInfo   = {},

    BackedUpAngles  = {},
}

if not database_read(HitlistInfo.DatabaseName) then
    local ScreenSize = Vector(client_screen_size())
    database_write(HitlistInfo.DatabaseName,
    {
        MainPosition    = {ScreenSize.x * 0.5, 10},
        SelfPosition    = {ScreenSize.x * 0.5, 50},
    })
end

local DB = database_read(HitlistInfo.DatabaseName)
HitlistInfo.Position        = Vector(DB.MainPosition[1], DB.MainPosition[2])
HitlistInfo.SelfPosition    = Vector(DB.SelfPosition[1], DB.SelfPosition[2])


local Shots         = {}
local LocalDamage    = {}

local Hitgroups = 
{
    [0] = "Generic",
    "Head",
    "Chest",
    "Stomach",
    "Arms",
    "Arms",
    "Legs",
    "Legs",
}


local MissReason = 
{
    ["prediction error"]    = "Prediction",
    ["unregistered shot"]   = "Unregistered",
}

local GrenadeNames = 
{
    ["hegrenade"]       = 1,
    ["flashbang"]       = 1,
    ["inferno"]         = 1,
    ["decoy"]           = 1,
    ["smokegrenade"]    = 1,
}

-- From solus ui
local function GetBarColor()
    local r, g, b, a = ui_get(ColorPicker)

    if not SolusCombo[1] then
        return r, g, b, a
    end

    local palette = ui_get(SolusCombo[2])

    if palette ~= "Solid" then
            local rgb_split_ratio = ui_get(Solus.FadeRatio) / 100

            local h = palette == "Dynamic fade" and globals_realtime() * (ui_get(Solus.FadeFreq) / 100) or ui_get(Solus.FadeOffset) / 1000
            r, g, b = HSVToRGB(h, 1, 1, 1)
            r, g, b =
            r * rgb_split_ratio,
            g * rgb_split_ratio,
            b * rgb_split_ratio
    end

    return r, g, b, a
end

local function Contains(Table, Value)
    for i, v in pairs(Table) do
        if v == Value then
            return true
        end
    end
    return false
end

local function Clamp(v, mn, mx)
    return v < mn and mn or v > mx and mx or v
end

local function IsPointInBounds(Point, Min, Max)
    return Point.x >= Min.x and Point.x <= Max.x and Point.y >= Min.y and Point.y <= Max.y;
end

local function Norm(a)
    if a < 0 then
        a = a + 360
    end
    return a
end

local function GetAngle(Player)
    if not plist_get(Player, 'Correction active') then
        return "-"
    end

    local EntityObj     = Entity.new(Player)
    local GoalFeetYaw   = EntityObj:get_anim_state().goal_feet_yaw
    local EyeAngles     = Vector(EntityObj:get_prop("m_angEyeAngles"))

    return Clamp(math_floor(((Norm(EyeAngles.y) - GoalFeetYaw + 180) % 360 - 180) + 0.5), -60, 60) .. "°"
end

local function GetSpreadAngle()
    -- I am terrible with ffi so if something is wrong here feel free to tell me.
    local LocalWeapon   = entity_get_player_weapon(entity_get_local_player())
    local RawEntity     = GetClientEntity(EntityListInterface, LocalWeapon)
    if not RawEntity then
        return "-"
    end
    local GetInaccuracyFn = ffi.cast("float(__thiscall*)(void*)", ffi.cast("void***", RawEntity)[0][483])

    if not GetInaccuracyFn then
        return "-"
    end
    
    local Weapon = Weapons[entity_get_prop(LocalWeapon, "m_iItemDefinitionIndex") or -1]

    if not Weapon then
        return "-"
    end

    return string_format("%0.2f°", math_deg(Weapon.spread + GetInaccuracyFn(RawEntity)))
end

local function ShotInfo(Shot)
    local Backtrack     = globals_tickcount() - Shot.tick

    -- Should never happen. Just a saftey check
    if not HitlistInfo.BackedUpAngles[Shot.target] then
        HitlistInfo.BackedUpAngles[Shot.target] = {}
    end

    return 
    {
        [ElementNames[1]]   = Shot.id,
        [ElementNames[2]]   = entity_get_player_name(Shot.target),
        [ElementNames[3]]   = Hitgroups[Shot.hitgroup] or "-",
        [ElementNames[4]]   = "-",
        [ElementNames[5]]   = math_floor(Shot.hit_chance + 0.5) .. "%",
        [ElementNames[6]]   = Shot.damage,
        [ElementNames[7]]   = "-",
        [ElementNames[8]]   = Backtrack == 0 and "-" or Backtrack .. "t",
        [ElementNames[9]]   = HitlistInfo.BackedUpAngles[Shot.target][Shot.tick] or GetAngle(Shot.target), -- Check to see if this tick is saved if not get the current angle
        [ElementNames[10]]  = GetSpreadAngle(),
        [ElementNames[11]]  = "-",
    }
end

local function LocalDamageInfo(Event)
    local Attacker          = client_userid_to_entindex(Event.attacker)
    local AttackerName      = entity_get_player_name(Attacker) or "Unknown"
    local AttackerWeapon    = entity_get_prop(entity_get_player_weapon(Attacker), "m_iItemDefinitionIndex")
    local Weapon            = GrenadeNames[Event.weapon] and "Grenade" or Weapons[AttackerWeapon or -1] and Weapons[AttackerWeapon].name or "Unknown"
    if Event.weapon == "" then
        Weapon = "Fall"
        AttackerName = "World"
    end

    return 
    {
        [SelfElementNames[1]] = AttackerName,
        [SelfElementNames[2]] = Weapon,
        [SelfElementNames[3]] = Hitgroups[Event.hitgroup] or "-",
        [SelfElementNames[4]] = Event.dmg_health,
    }
end

local function LogConsole(Table, SelfDamage)
    local r, g, b = ui_get(ColorPicker)
    if SelfDamage then
        local Combo = ui_get(SelfElementCombo)
        if #Combo == 0 then
            return end
        client_color_log(r, g, b, "[Hurt log] \0")
        for i = 1, #SelfElementNames do
            client_color_log(255, 255, 255, SelfElementNames[i] .. " \0")
            client_color_log(r, g, b, Table[SelfElementNames[i]] .. (i == #SelfElementNames and "" or " \0"))
        end        
    else
        local Combo = ui_get(ElementsCombo)
        if #Combo == 0 then
            return end

        client_color_log(r, g, b, "[Hitlist] \0")
        for i = 1, #ElementNames do
            client_color_log(255, 255, 255, ElementNames[i] .. " \0")
            client_color_log(r, g, b, Table[ElementNames[i]] .. (i == #ElementNames and "" or " \0"))
        end
    end
end

local function DrawSkeetWindow(x, y, w, h)
    y = y - 2
    h = h + 3
    local RectInfo = 
    {
        {12, 6},
        {60, 5},
        {40, 4},
        {60, 1},
        {12, 0}
    }
    local Gradients = 
    {
        {55, 177, 218},
        {204, 83, 192},
        {204, 227, 53},
        
    }
    -- The inner black area will be equal to the width and height
    -- This makes positioning easier
    for i = 1, #RectInfo do
        -- Color, Offset
        local C, O = RectInfo[i][1], RectInfo[i][2]
        renderer_rectangle(x - O, y - O, w + O * 2, h + O * 2, C, C, C, 255)
    end

    renderer_texture(BgTexture, x, y, w, h, 255, 255, 255, 255, "r")
    renderer_gradient(x + 1, y + 1, (w - 2) / 2, 1, Gradients[1][1], Gradients[1][2], Gradients[1][3], 255, Gradients[2][1], Gradients[2][2], Gradients[2][3], 255, true)
    renderer_gradient(x + w - 1, y + 1, - ((w - 1) / 2), 1, Gradients[3][1], Gradients[3][2], Gradients[3][3], 255, Gradients[2][1], Gradients[2][2], Gradients[2][3], 255, true)

    renderer_gradient(x + 1, y + 2, (w - 2) / 2, 1, Gradients[1][1] * 0.53, Gradients[1][2] * 0.53, Gradients[1][3] * 0.53, 255, Gradients[2][1] * 0.53, Gradients[2][2] * 0.53, Gradients[2][3] * 0.53, 255, true)
    renderer_gradient(x + w - 1, y + 2, - ((w - 1) / 2), 1, Gradients[3][1] * 0.53, Gradients[3][2] * 0.53, Gradients[3][3] * 0.53, 255, Gradients[2][1] * 0.53, Gradients[2][2] * 0.53, Gradients[2][3] * 0.53, 255, true)
end

local function DrawTable(Position, ActiveElements, InfoTable)
    local Dpi                   = ui_get(DpiCombo):gsub('%%', '') / 100
    local Style                 = ui_get(StyleCombo)
    local bTeamSkeet            = Style == "Teamskeet"
    local Padding, Spacing      = (bTeamSkeet and HitlistInfo.Padding * 1.5 or HitlistInfo.Padding) * Dpi, HitlistInfo.Spacing * Dpi


    local NameSizes = {}
    for i = 1, #ActiveElements do
        local Str = ActiveElements[i] == "Hit" and "Targeted" or ActiveElements[i]
        NameSizes[i] = Vector(renderer_measure_text(bTeamSkeet and "bd" or "d", bTeamSkeet and string_upper(Str) or Str))
    end
    local WindowSize = Vector(0, NameSizes[1].y + (Padding.y * 2));

    if Style == "Skeet" then
        for i = 1, #ActiveElements do
            WindowSize.x = WindowSize.x + NameSizes[i].x + (Spacing * 2)
        end
        if #InfoTable > 0 then
            WindowSize.y = WindowSize.y + 6 * Dpi
            WindowSize.y = WindowSize.y + (Clamp(#InfoTable, 0, HitlistInfo.MaxShots) * (NameSizes[1].y + Padding.y))
        end
        DrawSkeetWindow(Position.x, Position.y, WindowSize.x, WindowSize.y);

        if #InfoTable > 0 then
            local P, S = Vector(Position.x + Spacing - 3, Position.y + NameSizes[1].y + Padding.y * 2 + 1), Vector(WindowSize.x - ((Spacing - 3) * 2), 1)
            renderer_rectangle(P.x, P.y, S.x, S.y, 60, 60, 60, 255)
            renderer_rectangle(P.x, P.y + 1, S.x, S.y, 40, 40, 40, 255)
        end
    elseif bTeamSkeet then
        for i = 1, #ActiveElements do
            WindowSize.x = WindowSize.x + NameSizes[i].x + ((i == 1 and Padding.x or Spacing) * 2)
        end
        renderer_rectangle(Position.x, Position.y, WindowSize.x, WindowSize.y, 20, 20, 20, 255)
        renderer_gradient(Position.x, Position.y, WindowSize.x / 2, 2, 0, 200, 255, 255, 255, 0, 255, 255, true)
        renderer_gradient(Position.x + WindowSize.x / 2, Position.y, WindowSize.x / 2, 2, 255, 0, 255, 255, 175, 255, 0, 255, true)
        if #InfoTable > 0 then
            renderer_rectangle(Position.x, Position.y + WindowSize.y, WindowSize.x, Clamp(#InfoTable, 0, HitlistInfo.MaxShots) * (NameSizes[1].y + Padding.y), 25, 25, 25, 255)
        end
    else
        for i = 1, #ActiveElements do
            WindowSize.x = WindowSize.x + NameSizes[i].x + ((i == 1 and Padding.x or Spacing) * 2)
        end
        local r, g, b, a = GetBarColor()

        renderer_rectangle(Position.x, Position.y, WindowSize.x, WindowSize.y, 17, 17, 17, a)
        if SolusCombo[1] and ui_get(SolusCombo[2]) ~= "Solid" then
            local bOddWidth = WindowSize.x % 2 ~= 0
            renderer_gradient(Position.x, Position.y, (WindowSize.x / 2), 2, g, b, r, 255, r, g, b, 255, true)
            renderer_gradient(Position.x + WindowSize.x / 2, Position.y, WindowSize.x / 2 + (bOddWidth and 1 or 0), 2, r, g, b, 255, b, r, g, 255, true)
        else
            renderer_rectangle(Position.x, Position.y, WindowSize.x, 2, r, g, b, 255)
        end
        -- Divider rects
        local DividerOffset = 0
        for i = 1, #ActiveElements - 1 do
            DividerOffset = DividerOffset + NameSizes[i].x + (Spacing * 2)
            renderer_rectangle(Position.x + Padding.x + DividerOffset - Spacing, Position.y + 5, 1, WindowSize.y - 8, 175, 175, 175, 255)
            renderer_rectangle(Position.x + Padding.x + DividerOffset - Spacing + 1, Position.y + 5 + 1, 1, WindowSize.y - 8, 0, 0, 0, 100)
        end
        if #InfoTable > 0 then
            renderer_rectangle(Position.x, Position.y + WindowSize.y, WindowSize.x, Clamp(#InfoTable, 0, HitlistInfo.MaxShots) * (NameSizes[1].y + Padding.y), 17, 17, 17, a * 0.5)
        end
    end

    local TotalNameSize = 0
    for i = 1, #ActiveElements do
        local TextPos = Vector(Position.x + TotalNameSize + (NameSizes[i].x / 2 + (Style == "Skeet" and Spacing or Padding.x)), Position.y + Padding.y + NameSizes[i].y / 2 + (bTeamSkeet and 1 or 0))
        renderer_text(TextPos.x, TextPos.y, 255, 255, 255, 255, bTeamSkeet and "bdc" or "dc", 0, bTeamSkeet and string_upper(ActiveElements[i]) or ActiveElements[i])

        for j = #InfoTable, 1, -1 do
            if #InfoTable - (j - 1) <= HitlistInfo.MaxShots then
                renderer_text(TextPos.x, (Position.y + NameSizes[1].y + Padding.y * (Style == "Skeet" and 3 or 1)) + ((#InfoTable - (j - 1)) * (NameSizes[1].y + Padding.y)) - NameSizes[1].y / 2 - (Style == "Skeet" and 1 or 0), 255, 255, 255, 255, bTeamSkeet and "bdc" or "dc", NameSizes[i].x * 1.25, bTeamSkeet and string_upper(InfoTable[j][ActiveElements[i]]) or InfoTable[j][ActiveElements[i]])
            end
        end
        TotalNameSize = TotalNameSize + NameSizes[i].x + (Spacing * 2)
    end
    return WindowSize
end

local function HandleMovement(Info, Position, Size)
    local CursorPos = Vector(ui_mouse_position())
    if ui_is_menu_open() and client_key_state(0x1) then

        -- Check whether we are in bounds or was in bounds when we clicked
        -- This fixes the issue where you stop dragging if you move to fast
        local PointInBounds = IsPointInBounds(CursorPos, Position, Position + Size)

        -- Check if we are on the menu or off the hitlist and not already dragging
        if (IsPointInBounds(CursorPos, Vector(ui_menu_position()), Vector(ui_menu_position()) + Vector(ui_menu_size())) or not PointInBounds) and not Info.Held then
            Info.ClickedOff = true;
        end
        
        -- If this click was off the hitlist then dont run any movement
        if not Info.ClickedOff then
            if (PointInBounds or Info.Held) then
                if not Info.Held then
                    -- We arent holding aka first click. Set our grab delta
                    Info.GrabOffset = Vector(CursorPos.x - Position.x, CursorPos.y - Position.y)
                end
                -- We are holding now
                Info.Held = true 
                -- Move position based of grab delta
                Position = Vector(CursorPos.x - Info.GrabOffset.x, CursorPos.y - Info.GrabOffset.y)
                HitlistInfo.InDrag = true
            end
        end
    else
        -- We are no longer pressing mouse one stop holding
        Info.Held = false
        Info.ClickedOff = false;
    end
    -- Clamp out position. Stay on screen!!!
    local ScreenSize = Vector(client_screen_size())
    Position.x = Clamp(Position.x, 0, ScreenSize.x - Size.x)
    Position.y = Clamp(Position.y, 0, ScreenSize.y - Size.y)
    return Position
end

local function OnPaint()
    if not entity_get_local_player() then
        Shots       = {}
        LocalDamage = {}
        HitlistInfo.BackedUpAngles = {}
        return
    end
    
    local ActiveElements        = ui_get(ElementsCombo)
    local ActiveSelfElements    = ui_get(SelfElementCombo)

    if #ActiveElements > 0 then
        local Size = DrawTable(HitlistInfo.Position, ActiveElements, Shots)
        HitlistInfo.Position = HandleMovement(HitlistInfo.MovementInfo, HitlistInfo.Position, Size)
    end

    if #ActiveSelfElements > 0 then
        local Size = DrawTable(HitlistInfo.SelfPosition, ActiveSelfElements, LocalDamage)
        HitlistInfo.SelfPosition = HandleMovement(HitlistInfo.LocalMovementInfo, HitlistInfo.SelfPosition, Size)
    end
end

local function SetupCommand(cmd)
    if HitlistInfo.InDrag then
        cmd.in_attack       = false
        HitlistInfo.InDrag  = false
    end

    local Enemies = entity_get_players(true)

    for i, Index in pairs(Enemies) do
        if not HitlistInfo.BackedUpAngles[Index] then
            HitlistInfo.BackedUpAngles[Index] = {}
        end
        HitlistInfo.BackedUpAngles[Index][globals_tickcount()] = GetAngle(Index)

        for i2, v in pairs(HitlistInfo.BackedUpAngles[Index]) do
            local Delta = globals_tickcount() - i2

            -- I dont think actually calculating how many ticks you can backtrack is needed here
            -- Just save 2 seconds worth
            if Delta > 128 then
                HitlistInfo.BackedUpAngles[Index][i2] = nil
            end
        end
    end
end

local function OnAimFire(Shot)
    if Shot.id == 0 and #Shots > 0 then
        Shots = {}
    end
    Shots[#Shots + 1] = ShotInfo(Shot)
end

local function OnAimHit(Shot)
    for i = #Shots, 1, -1 do
        if Shots[i][ElementNames[1]] == Shot.id then
            Shots[i]["Hit"] = Hitgroups[Shot.hitgroup] or "-"
            Shots[i]["Damage"] = Shot.damage
            if Contains(ui_get(ConsoleCombo), "Hitlist") then
                LogConsole(Shots[i])
            end
            break;
        end
    end
end

local function OnAimMiss(Shot)
    local function UpperReason(r)
        return string_upper(r:sub(1,1)) .. r:sub(2, r:len())
    end

    for i = #Shots, 1, -1 do
        if Shots[i][ElementNames[1]] == Shot.id then
            Shots[i]["Miss Reason"] = MissReason[Shot.reason] or UpperReason(Shot.reason)
            if Contains(ui_get(ConsoleCombo), "Hitlist") then
                LogConsole(Shots[i])
            end
            break;
        end
    end
end

local function OnPlayerHurt(Event)
    if client_userid_to_entindex(Event.userid) ~= entity_get_local_player() then
        return end

    LocalDamage[#LocalDamage + 1] = LocalDamageInfo(Event)
    if Contains(ui_get(ConsoleCombo), "Local damage") then
        LogConsole(LocalDamage[#LocalDamage], true)
    end
end

local function OnRoundStart()
    Shots       = {}
    LocalDamage = {}
end

local function OnShutdown()
    database_write(HitlistInfo.DatabaseName, 
    {
        MainPosition = {HitlistInfo.Position.x, HitlistInfo.Position.y},
        SelfPosition = {HitlistInfo.SelfPosition.x, HitlistInfo.SelfPosition.y},
    })
    client_unset_event_callback("player_hurt", OnPlayerHurt)
    client_unset_event_callback("round_start", OnRoundStart)
end

client_set_event_callback("paint_ui",       OnPaint)
client_set_event_callback("setup_command",  SetupCommand)
client_set_event_callback("aim_fire",       OnAimFire)
client_set_event_callback("aim_hit",        OnAimHit)
client_set_event_callback("aim_miss",       OnAimMiss)
client_set_event_callback("player_hurt",    OnPlayerHurt)
client_set_event_callback("round_start",    OnRoundStart)
client_set_event_callback("shutdown",       OnShutdown)
