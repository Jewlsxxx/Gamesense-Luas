-- local variables for API functions. any changes to the line below will be lost on re-generation
local client_set_event_callback, entity_get_all, entity_get_local_player, entity_get_prop, globals_frametime, globals_tickcount, renderer_line, renderer_world_to_screen, table_remove, pairs, ui_get, ui_new_checkbox, ui_new_color_picker, ui_new_slider, ui_set_callback, ui_set_visible, require = client.set_event_callback, entity.get_all, entity.get_local_player, entity.get_prop, globals.frametime, globals.tickcount, renderer.line, renderer.world_to_screen, table.remove, pairs, ui.get, ui.new_checkbox, ui.new_color_picker, ui.new_slider, ui.set_callback, ui.set_visible, require

-- Trying out different coding styles btw
local Vector = require("vector")

local g_iMasterSwitch   = ui_new_checkbox("VISUALS", "Effects", "Grenade trails")
local g_iColor          = ui_new_color_picker("VISUALS",  "Effects", "Grenade trails", 255, 255, 255, 255)
local g_iLocalOnly      = ui_new_checkbox("VISUALS", "Effects", "Local only")
local g_iDuration       = ui_new_slider("VISUALS", "Effects", "Duration", 10, 100, 3, true, "s", 0.1)

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
    local bMasterSwitch = ui_get(g_iMasterSwitch)
    local aColor        = {ui_get(g_iColor)}
    local iDuration     = ui_get(g_iDuration) / 10
    if not bMasterSwitch then
        g_aEntitys = {}
        return
    end

    local flFrameTime = globals_frametime()
    local iTickcount = globals_tickcount()
    
    -- Doing this here because run_command isnt called when in noclip or dead
    if g_iOldTickcount ~= iTickcount then
        local bLocalOnly    = ui_get(g_iLocalOnly)
        local iLocalPlayer  = entity_get_local_player()
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
                -- Check if we are less than 100 units but still greater than 0
                -- This fixes a bug where previous grenades would link to new grenades with the same index
                local flDistance = aInfo.m_vecPosition:dist(aNextInfo.m_vecPosition)
                if flDistance < 100 and flDistance > 0 then
                    local ix, iy = renderer_world_to_screen(aInfo.m_vecPosition.x, aInfo.m_vecPosition.y, aInfo.m_vecPosition.z)
                    local ix2, iy2 = renderer_world_to_screen(aNextInfo.m_vecPosition.x, aNextInfo.m_vecPosition.y, aNextInfo.m_vecPosition.z)
                    if ix then
                        renderer_line(ix, iy, ix2, iy2, aColor[1], aColor[2], aColor[3], aColor[4] * aInfo.m_flAnimTime)
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
    local bMasterValue = ui_get(g_iMasterSwitch)
    ui_set_visible(g_iDuration, bMasterValue)
    ui_set_visible(g_iLocalOnly, bMasterValue)
end

g_SetVisibility()
ui_set_callback(g_iMasterSwitch, g_SetVisibility)
client_set_event_callback("paint", g_Paint)
