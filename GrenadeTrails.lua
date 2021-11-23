-- local variables for API functions. any changes to the line below will be lost on re-generation
local client_find_signature, client_set_event_callback, entity_get_all, entity_get_local_player, entity_get_prop, globals_frametime, globals_tickcount, materialsystem_find_materials, renderer_line, renderer_world_to_screen, table_remove, pairs, ui_get, ui_new_checkbox, ui_new_color_picker, ui_new_combobox, ui_new_slider, ui_set_callback, ui_set_visible, error, require = client.find_signature, client.set_event_callback, entity.get_all, entity.get_local_player, entity.get_prop, globals.frametime, globals.tickcount, materialsystem.find_materials, renderer.line, renderer.world_to_screen, table.remove, pairs, ui.get, ui.new_checkbox, ui.new_color_picker, ui.new_combobox, ui.new_slider, ui.set_callback, ui.set_visible, error, require

local Vector = require("vector")
-- @Aviarita local player tracers
local ffi = require("ffi")
ffi.cdef[[
    typedef struct  {
		float x;
		float y;
		float z;	
	}vec3_t;
    struct beam_info_t {
        int			m_type;
        void* m_start_ent;
        int			m_start_attachment;
        void* m_end_ent;
        int			m_end_attachment;
        vec3_t		m_start;
        vec3_t		m_end;
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
        vec3_t		m_center;
        float		m_start_radius;
        float		m_end_radius;
    };
    typedef void (__thiscall* draw_beams_t)(void*, void*);
    typedef void*(__thiscall* create_beam_points_t)(void*, struct beam_info_t&);
]]

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
    pBeamInfo.m_start       = {Start.x, Start.y, Start.z}
    pBeamInfo.m_end         = {End.x, End.y, End.z}

    local pBeam = g_CreateBeamPoints(g_RenderBeamClass, pBeamInfo)
    if pBeam ~= nil then
        g_DrawBeam(g_RenderBeams, pBeam)
    end
end
local g_iMasterCombo    = ui_new_combobox("VISUALS",  "Effects", "Grenade trails", {"Off", "Line", "Beam"})
local g_iColor          = ui_new_color_picker("VISUALS",  "Effects", "Grenade trails", 255, 255, 255, 255)
local g_iLocalOnly      = ui_new_checkbox("VISUALS", "Effects", "Local only")
local g_iDuration       = ui_new_slider("VISUALS", "Effects", "Duration", 10, 100, 3, true, "s", 0.1)

local g_bReset = true
local g_aEntitys = {}
local g_iOldTickcount = globals_tickcount()
local g_aClassNames = 
{
    "CSmokeGrenadeProjectile",
    "CMolotovProjectile",
    "CBaseCSGrenadeProjectile",
    "CDecoyProjectile",
}

local function g_Paint()
    local szMasterCombo = ui_get(g_iMasterCombo)
    local aColor        = {ui_get(g_iColor)}
    local iDuration     = ui_get(g_iDuration) / 10
    local iLocalPlayer  = entity_get_local_player()


    if not iLocalPlayer or szMasterCombo == "Off" then
        g_aEntitys = {}
        g_bReset = true
        return
    end

    if g_bReset then
        local aBeamMaterials      = materialsystem_find_materials(g_szBeamMaterialName)
        for iKey, pMaterial in pairs(aBeamMaterials or {}) do
            pMaterial:set_material_var_flag(15, true) -- IgnoreZ
        end
        g_bReset = false
    end

    local flFrameTime = globals_frametime()
    local iTickcount = globals_tickcount()
    
    -- Doing this here because run_command isnt called when in noclip or dead
    if g_iOldTickcount ~= iTickcount then
        local bLocalOnly    = ui_get(g_iLocalOnly)
        -- Loop through all entity class names
        for i = 1, #g_aClassNames do
            -- Get entitys for this class
            local aClassEntitys = entity_get_all(g_aClassNames[i])

            -- Loop through all entitys in this class
            for iKey, iIndex in pairs(aClassEntitys) do
                -- If we are in local only mode, skip nades thrown by other players
                if bLocalOnly and entity_get_prop(iIndex, "m_hOwnerEntity") ~= iLocalPlayer then
                    goto continue
                end
                if not g_aEntitys[iIndex] then
                    g_aEntitys[iIndex] = {}
                end
                -- Add new variables
                g_aEntitys[iIndex][#g_aEntitys[iIndex] + 1] = 
                {
                    m_vecPosition   = Vector(entity_get_prop(iIndex, "m_vecOrigin")),
                    m_flWaitTime    = 1,
                    m_flAnimTime    = 1,
                    m_bCreateBeam   = true,
                }
                ::continue::
            end
        end
        g_iOldTickcount = iTickcount
    end

    -- Loop through all entitys
    for iEntityIndex, aEntityInfo in pairs(g_aEntitys) do
        -- Loop through their positions
        for iInfoIndex, aInfo in pairs(aEntityInfo) do
            local aNextInfo = aEntityInfo[iInfoIndex + 1]
            -- Check if there is a valid table position at index + 1
            if aNextInfo then
                -- This fixes a bug where previous grenades would link to new grenades with the same index
                local flDistance = aInfo.m_vecPosition:dist(aNextInfo.m_vecPosition)
                if flDistance < 200 and flDistance > 0 then
                    if szMasterCombo == "Line" then
                        local ix, iy = renderer_world_to_screen(aInfo.m_vecPosition.x, aInfo.m_vecPosition.y, aInfo.m_vecPosition.z)
                        local ix2, iy2 = renderer_world_to_screen(aNextInfo.m_vecPosition.x, aNextInfo.m_vecPosition.y, aNextInfo.m_vecPosition.z)
                        if ix then
                            renderer_line(ix, iy, ix2, iy2, aColor[1], aColor[2], aColor[3], aColor[4] * aInfo.m_flAnimTime)
                        end
                    else
                        if aInfo.m_bCreateBeam then
                            g_CreateBeam(aInfo.m_vecPosition, aNextInfo.m_vecPosition, iDuration, aColor)
                            aInfo.m_bCreateBeam = false
                        end
                    end
                end
            end

            aInfo.m_flWaitTime = aInfo.m_flWaitTime - ((1 / iDuration) * flFrameTime)
            -- Check if we have waited our duration
            if aInfo.m_flWaitTime <= 0 then
                aInfo.m_flAnimTime = aInfo.m_flAnimTime - ((1 / 0.5) * flFrameTime)
                if aInfo.m_flAnimTime <= 0 then
                    table_remove(g_aEntitys[iEntityIndex], iInfoIndex)
                end
            end
        end
    end
end

local function g_SetVisibility()
    local bMasterValue = ui_get(g_iMasterCombo) ~= "Off"
    ui_set_visible(g_iDuration, bMasterValue)
    ui_set_visible(g_iLocalOnly, bMasterValue)
end

g_SetVisibility()
ui_set_callback(g_iMasterCombo, g_SetVisibility)
client_set_event_callback("paint", g_Paint)
