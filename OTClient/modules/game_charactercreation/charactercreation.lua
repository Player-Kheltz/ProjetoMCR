--[[
    Projeto: MCR
    Módulo: Criação de Personagem (Cliente)
    Descrição: Gerencia o fluxo de criação no Salão dos Destinos.
    Autor: Equipe MCR
    Data: 21/04/2026
--]]

local CharacterCreation = {}

local OPCODE_CHARACTER_CREATE_REQUEST = 160
local OPCODE_CHARACTER_CREATE_RESPONSE = 161

function CharacterCreation.init()
    ProtocolGame.registerExtendedOpcode(OPCODE_CHARACTER_CREATE_RESPONSE, onCharacterCreateResponse)
    print(">>> [MCR] Módulo de Criação de Personagem carregado.")
end

function CharacterCreation.terminate()
    ProtocolGame.unregisterExtendedOpcode(OPCODE_CHARACTER_CREATE_RESPONSE)
end

-- Função chamada pelo console quando um link [texto] é clicado
function CharacterCreation.handleLinkClick(linkText)
    local player = g_game.getLocalPlayer()
    if not player then return end

    -- Envia o comando como fala normal para o NPC processar
    g_game.talk(linkText)

    -- Lógica adicional para capturar a escolha da vocação (para enviar via opcode depois)
    if linkText == "Guerreiro" then
        selectedVocation = 1
    elseif linkText == "Arqueiro" then
        selectedVocation = 2
    elseif linkText == "Mago" then
        selectedVocation = 3
    elseif linkText == "Druida" then
        selectedVocation = 4
    elseif linkText == "Confirmar" then
        -- Enviar opcode com nome e vocação
        -- (A ser implementado com base no estado da conversa)
    end
end

function onCharacterCreateResponse(protocol, opcode, buffer)
    local response = json.decode(buffer)
    if response.success then
        modules.game_toast.show("Personagem criado! Redirecionando...", 3000)
        scheduleEvent(function()
            g_game.safeLogout()
        end, 2000)
    else
        local errorMsg = ERROR_MESSAGES[response.error_code] or response.message or "Erro desconhecido."
        modules.game_toast.show("Erro: " .. errorMsg, 5000, true)
    end
end

return CharacterCreation