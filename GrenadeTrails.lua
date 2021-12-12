-- local variables for API functions. any changes to the line below will be lost on re-generation
local client_find_signature, client_set_event_callback, entity_get_all, entity_get_local_player, entity_get_origin, entity_get_prop, globals_curtime, globals_tickcount, math_atan2, math_deg, math_fmod, math_min, renderer_line, renderer_world_to_screen, table_insert, ui_get, ui_new_checkbox, ui_new_color_picker, ui_new_combobox, ui_new_slider, ui_set_callback, ui_set_visible, unpack, pairs, error, require = client.find_signature, client.set_event_callback, entity.get_all, entity.get_local_player, entity.get_origin, entity.get_prop, globals.curtime, globals.tickcount, math.atan2, math.deg, math.fmod, math.min, renderer.line, renderer.world_to_screen, table.insert, ui.get, ui.new_checkbox, ui.new_color_picker, ui.new_combobox, ui.new_slider, ui.set_callback, ui.set_visible, unpack, pairs, error, require

-- @Aviarita local player beam lua
local ffi = require("ffi")
local Vector = require("vector")
ffi.cdef[[
    struct beam_info_t {
        int			m_type;
        void* m_start_ent;
        int			m_start_attachment;
        void* m_end_ent;
        int			m_end_attachment;
        Vector		m_start;
        Vector		m_end;
        int			m_model_index;
        const char	*m_model_name;
        int			m_halo_index;
        const char	*m_halo_name;
        float		m_halo_scale;
        float		m_life;
        float		m_width;
        float		m_end_width;
        float		m_fade_length;
        float		m_amplitude;
        float		m_brightness;
        float		m_speed;
        int			m_start_frame;
        float		m_frame_rate;
        float		m_red;
        float		m_green;
        float		m_blue;
        bool		m_renderable;
        int			m_num_segments;
        int			m_flags;
        Vector		m_center;
        float		m_start_radius;
        float		m_end_radius;
    };
    typedef void (__thiscall* draw_beams_t)(void*, void*);
    typedef void*(__thiscall* create_beam_points_t)(void*, struct beam_info_t&);
    struct Color {unsigned char _color[4];};
]]

-- Credits @howard / Classy for addglowbox sig
local g_GetGlowObjectManagerFn = ffi.cast( "void*( __cdecl* )()", client_find_signature( "client.dll", "\xA1\xCC\xCC\xCC\xCC\xA8\x01\x75\x4B") )
local g_AddGlowBox_t  = "int( __thiscall* )(void*, Vector, Vector, Vector, Vector, struct Color, float )"
local g_AddGlowBoxFn  = ffi.cast(g_AddGlowBox_t, client_find_signature("client.dll", "\x55\x8B\xEC\x53\x56\x8D\x59"))
local g_BeamSignature       = client_find_signature("client_panorama.dll", "\xB9\xCC\xCC\xCC\xCC\xA1\xCC\xCC\xCC\xCC\xFF\x10\xA1\xCC\xCC\xCC\xCC\xB9") or error("Beam signature not found")
local g_RenderBeams         = ffi.cast('void**', ffi.cast("char*", g_BeamSignature) + 1)[0] or error("Render beam is nil")
local g_RenderBeamClass     = ffi.cast("void***", g_RenderBeams)
local g_DrawBeam            = ffi.cast("draw_beams_t", g_RenderBeamClass[0][6])           or error("Couldn't cast draw_beams_t", 2)
local g_CreateBeamPoints    = ffi.cast("create_beam_points_t", g_RenderBeamClass[0][12])  or error("Couldn't cast create_beam_points_t", 2)

local g_szBeamMaterialName  = "sprites/purplelaser1"

local function g_CreateBeam(Start, End, Duration, Color)
    local pBeamInfo = ffi.new("struct beam_info_t")
    pBeamInfo.m_type        = 0
    pBeamInfo.m_model_index = -1
    pBeamInfo.m_halo_scale  = 0
    pBeamInfo.m_life        = Duration
    pBeamInfo.m_fade_length = 0
    pBeamInfo.m_width       = 8
    pBeamInfo.m_end_width   = 8
    pBeamInfo.m_model_name  = g_szBeamMaterialName .. ".vmt"
    pBeamInfo.m_amplitude   = 0
    pBeamInfo.m_speed       = 0.01
    pBeamInfo.m_start_frame = 0
    pBeamInfo.m_frame_rate  = 0
    pBeamInfo.m_red         = Color[1]
    pBeamInfo.m_green       = Color[2]
    pBeamInfo.m_blue        = Color[3]
    pBeamInfo.m_brightness  = Color[4]
    pBeamInfo.m_num_segments= 2
    pBeamInfo.m_renderable  = true
    pBeamInfo.m_flags       = 0
    pBeamInfo.m_start       = Start
    pBeamInfo.m_end         = End

    local pBeam = g_CreateBeamPoints(g_RenderBeamClass, pBeamInfo)
    if pBeam ~= nil then
        g_DrawBeam(g_RenderBeams, pBeam)
    end
end

local function g_CreateGlowBox(vecOrigin, vecAngle, vecMins, vecMaxs, aColor, flLife)
    local GlowObjManager = g_GetGlowObjectManagerFn()
    if not GlowObjManager then
        return
    end
    local Index = g_AddGlowBoxFn(GlowObjManager, vecOrigin, vecAngle, vecMins, vecMaxs, ffi.new("struct Color", ffi.new("unsigned char[4]", aColor[1], aColor[2], aColor[3], aColor[4])), flLife)
end

local function g_VectorAngles(vecForward)
    local flLength = vecForward:length2d()
    if flLength < 0 then
        return Vector()
    end 
    return Vector(math_deg(math_atan2(-vecForward.z, flLength)), math_deg(math_atan2(vecForward.y, vecForward.x)), 0)
end

local g_iMasterCombo    = ui_new_combobox("VISUALS",  "Effects", "Grenade trails", {"Off", "Line", "Glow", "Beam"})
local g_iColor          = ui_new_color_picker("VISUALS",  "Effects", "Grenade trails", 255, 255, 255, 255)
local g_iLocalOnly      = ui_new_checkbox("VISUALS", "Effects", "Local only")
local g_iDuration       = ui_new_slider("VISUALS", "Effects", "Duration", 10, 100, 3, true, "s", 0.1)
local g_iSize           = ui_new_slider("VISUALS", "Effects", "Size", 10, 100, 20, true, "u", 0.01)
local g_iDotted         = ui_new_checkbox("VISUALS", "Effects", "Dotted")
local g_iInverse        = ui_new_checkbox("VISUALS", "Effects", "Inverse")

local g_Lines = {}
local g_Positions = {}
local g_iOldTickcount = globals_tickcount()
local g_ClassNames = 
{
    "CSmokeGrenadeProjectile",
    "CMolotovProjectile",
    "CBaseCSGrenadeProjectile",
    "CDecoyProjectile",
}

local function g_CreateLine(vecPosOne, vecPosTwo, aColor, flLife)
    local flCurtime = globals_curtime()
    local pLineInfo = 
    {
        m_vecStartPos   = vecPosOne,
        m_vecEndPos     = vecPosTwo,
        m_flSpawntime   = flCurtime,
        m_flDestroyTime = flCurtime + flLife,
        m_aColor = aColor
    }
    table_insert(g_Lines, pLineInfo)
end

-- Fading from CSGO source
local function g_DrawLines()
    for iKey, pLine in pairs(g_Lines) do
        local flLifeAlpha = (pLine.m_flDestroyTime - globals_curtime()) / (pLine.m_flDestroyTime - pLine.m_flSpawntime)
        if flLifeAlpha <= 0 then
            g_Lines[iKey] = nil
        else
            flLifeAlpha = math_min(flLifeAlpha * 4.0, 1.0)
            local x, y = renderer_world_to_screen(pLine.m_vecStartPos:unpack())
            local x2, y2 = renderer_world_to_screen(pLine.m_vecEndPos:unpack())
            if x and x2 then
                local r, g, b, a = unpack(pLine.m_aColor)
                renderer_line(x, y, x2, y2, r, g, b, a * flLifeAlpha)
            end
        end
    end
end

local function g_Paint()
    local iLocalPlayer = entity_get_local_player()
    local szMasterValue = ui_get(g_iMasterCombo)
    if not iLocalPlayer or szMasterValue == "Off" then
        g_Positions = {}
        g_Lines     = {}
        g_iOldTickcount = 0
        return
    end
    local iTickCount = globals_tickcount()
    -- Check if we are more than 100 ticks out of sync (probably left and joined a server with a different tick count)
    if g_iOldTickcount > iTickCount + 100 then
        g_iOldTickcount = iTickCount
    end
    -- Wait 2 ticks for a slightly better preformance
    if g_iOldTickcount + 2 < iTickCount then
        local flDuration    = ui_get(g_iDuration) * 0.1
        local flSize        = ui_get(g_iSize) * 0.01
        local aColor        = {ui_get(g_iColor)}
        local bDotted       = ui_get(g_iDotted)
        local bInverse      = bDotted and ui_get(g_iInverse)
        for iClassNameIndex = 1, #g_ClassNames do
            local ClassEntitys = entity_get_all(g_ClassNames[iClassNameIndex])
            for iKey, iEntityIndex in pairs(ClassEntitys) do
                local bLocalOnly = (ui_get(g_iLocalOnly) and entity_get_prop(iEntityIndex, "m_hOwnerEntity") ~= iLocalPlayer)
                if bLocalOnly or not g_Positions[iEntityIndex] or iTickCount - g_Positions[iEntityIndex][#g_Positions[iEntityIndex]].iTickCount > 4 then
                    g_Positions[iEntityIndex] = {}
                end
                if bLocalOnly then
                    goto continue
                end
                local pEntPosTable = g_Positions[iEntityIndex]
                local iIndex = #pEntPosTable + 1
                pEntPosTable[iIndex] = 
                {
                    iTickCount = iTickCount,
                    vecPos = Vector(entity_get_origin(iEntityIndex)),
                }
                -- Check if we have a previous record and it isnt in the same spot
                local pCurrent = pEntPosTable[iIndex]
                local pPrev = pEntPosTable[iIndex - 1]
                if pPrev then
                    local flDistance = pCurrent.vecPos:dist(pPrev.vecPos)
                    if flDistance ~= 0 then
                        -- Multiple nades can conflicting colors
                        local aUseColor     = {unpack(aColor)}
                        local bUseDotted    = bDotted and (math_fmod(globals_curtime(), 0.1) < 0.05)
                        if bUseDotted then
                            for i = 1, 3 do
                                if bInverse then
                                    aUseColor[i] = 255 - aUseColor[i]
                                else
                                    aUseColor[i] = 0
                                end
                            end
                        end
                        
                        if szMasterValue == "Line" then
                            g_CreateLine(pPrev.vecPos, pEntPosTable[iIndex].vecPos, aUseColor, flDuration)
                        elseif szMasterValue == "Glow" then
                            g_CreateGlowBox(pCurrent.vecPos, g_VectorAngles(pPrev.vecPos - pCurrent.vecPos), Vector(0, flSize, flSize), Vector(flDistance, -flSize, -flSize), aUseColor, flDuration)
                        else
                            g_CreateBeam(pCurrent.vecPos, pPrev.vecPos, flDuration, aUseColor)
                        end
                    end
                end
                ::continue::
            end
        end

        g_iOldTickcount = iTickCount
    end

    g_DrawLines()
end

local function g_SetVisibility()
    local szMasterCombo = ui_get(g_iMasterCombo)
    local bMasterValue = szMasterCombo ~= "Off"
    local bDotted = ui_get(g_iDotted)
    ui_set_visible(g_iDuration, bMasterValue)
    ui_set_visible(g_iSize, szMasterCombo == "Glow")
    ui_set_visible(g_iDotted, bMasterValue)
    ui_set_visible(g_iLocalOnly, bMasterValue)
    ui_set_visible(g_iInverse, bDotted)
end

local function g_SetVisDot()
    local bMaster = ui_get(g_iDotted)
    ui_set_visible(g_iInverse, bMaster)
end

g_SetVisibility()
g_SetVisDot()
ui_set_callback(g_iDotted, g_SetVisDot)
ui_set_callback(g_iMasterCombo, g_SetVisibility)
client_set_event_callback("paint", g_Paint)
