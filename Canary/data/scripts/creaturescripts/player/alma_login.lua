local loginEvent = CreatureEvent("AlmaLogin")
function loginEvent.onLogin(player)
    if player:getName():lower() == "alma" then
        local realId = player:getStorageValue(50000)
        if realId > 0 then
            player:setAccountId(realId)   -- método Lua
        end
        player:registerEvent("AlmaMove")
        player:registerEvent("AlmaAttack")
    end
    return true
end
loginEvent:register()