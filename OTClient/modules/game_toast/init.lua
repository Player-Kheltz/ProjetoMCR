-- modules/game_toast/init.lua
-- Projeto MCR - Sistema de Notificações Toast

local Toast = {
    queue = {},
    currentToast = nil,
    defaultDuration = 3000
}

function Toast.init()
    -- Inicialização (se necessária)
end

function Toast.terminate()
    if Toast.currentToast then
        Toast.currentToast:destroy()
        Toast.currentToast = nil
    end
end

function Toast.show(message, duration, type)
    duration = duration or Toast.defaultDuration
    type = type or "info"
    
    if Toast.currentToast then
        Toast.currentToast:destroy()
        Toast.currentToast = nil
    end

    local toast = g_ui.createWidget('Toast', rootWidget)
    toast:setText(message)
    
    local bgColor
    if type == "error" then
        bgColor = "#d32f2f"
    elseif type == "success" then
        bgColor = "#388e3c"
    elseif type == "warning" then
        bgColor = "#f57c00"
    else
        bgColor = "#1976d2"
    end
    toast:setBackgroundColor(bgColor)
    
    toast:setMarginRight(20)
    toast:setMarginBottom(20)
    toast:setAnchor(ANCHOR_BOTTOMRIGHT)
    
    toast:setOpacity(0)
    toast:animate({ opacity = 1.0 }, 200, function()
        scheduleEvent(function()
            toast:animate({ opacity = 0 }, 300, function()
                toast:destroy()
                if Toast.currentToast == toast then
                    Toast.currentToast = nil
                end
            end)
        end, duration)
    end)
    
    Toast.currentToast = toast
end

-- Aliases
function Toast.error(message, duration) Toast.show(message, duration, "error") end
function Toast.success(message, duration) Toast.show(message, duration, "success") end
function Toast.warning(message, duration) Toast.show(message, duration, "warning") end
function Toast.info(message, duration) Toast.show(message, duration, "info") end

-- Registrar no escopo global
modules.game_toast = Toast
return Toast