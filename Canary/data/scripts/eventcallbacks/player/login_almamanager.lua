local SALAO_POS = Position(666, 666, 15)  -- Ajuste conforme seu mapa

function onLogin(player)
    if player:getName() ~= "Alma" then
        return true
    end
    player:setGhostMode(true)
    if player:getPosition() ~= SALAO_POS then
        player:teleportTo(SALAO_POS)
        player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
    end
    player:sendTextMessage(MESSAGE_EVENT_ADVANCE, 
        "Bem-vindo ao Salão dos Destinos. Fale com o Oráculo para gerenciar sua conta.")
    return true
end