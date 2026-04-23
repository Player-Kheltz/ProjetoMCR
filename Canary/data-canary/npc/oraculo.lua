--[[
    Projeto: MCR
    Módulo: NPC Oráculo dos Caminhos
    Descrição: Gerencia a criação de novos personagens no "Salão dos Destinos".
--]]

-- =============================================================================
-- CONFIGURAÇÃO INICIAL
-- =============================================================================
local internalNpcName = "Oraculo dos Caminhos"

-- =============================================================================
-- HANDLERS E CALLBACKS (Sistema Padrão do Canary)
-- =============================================================================
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)
NpcSystem.parseParameters(npcHandler)

-- =============================================================================
-- CONFIGURAÇÃO DO NPC (Outfit, flags, etc.)
-- =============================================================================
local npcType = Game.createNpcType(internalNpcName)
local npcConfig = {
    name = internalNpcName,
    description = internalNpcName,
    health = 100,
    maxHealth = 100,
    walkInterval = 2000,
    walkRadius = 1,
    outfit = {
        lookType = 141,               -- Aparência de um sábio
        lookHead = 114,
        lookBody = 114,
        lookLegs = 114,
        lookFeet = 114,
        lookAddons = 3
    },
    flags = { floorchange = false }
}

-- =============================================================================
-- REGISTRO DOS CALLBACKS DO NPC
-- =============================================================================
npcType.onThink = function(npc, interval) npcHandler:onThink(npc, interval) end
npcType.onAppear = function(npc, creature) npcHandler:onAppear(npc, creature) end
npcType.onDisappear = function(npc, creature) npcHandler:onDisappear(npc, creature) end
npcType.onMove = function(npc, creature, fromPosition, toPosition) npcHandler:onMove(npc, creature, fromPosition, toPosition) end
npcType.onSay = function(npc, creature, type, message) npcHandler:onSay(npc, creature, type, message) end
npcType.onCloseChannel = function(npc, creature) npcHandler:onCloseChannel(npc, creature) end

-- =============================================================================
-- LÓGICA DO NPC (Criação de Personagem)
-- =============================================================================
local function creatureSayCallback(npc, creature, type, message)
    local player = Player(creature)
    if not player then return false end

    if not npcHandler:checkInteraction(npc, creature) then
        return false
    end

    local lowerMsg = message:lower()

    -- Palavras-chave para iniciar o processo
    if lowerMsg == "criar" then
        npcHandler:say("Ah, um novo herói! Para criá-lo, primeiro me diga qual será o **nome** do seu personagem.", npc, creature)
        npcHandler.topic[creature:getId()] = 1
    elseif npcHandler.topic[creature:getId()] == 1 then
        -- Aguardando o nome
        local newName = message
        if #newName >= 3 and #newName <= 30 then
            -- Verifica se o nome já existe (evitar duplicidade)
            local result = db.storeQuery("SELECT `id` FROM `players` WHERE `name` = " .. db.escapeString(newName))
            if result then
                result:free()
                npcHandler:say("Este nome já está em uso. Por favor, escolha outro.", npc, creature)
                return true
            end

            -- Armazena o nome temporariamente e avança para a vocação
            npcHandler:setPlayerStorage(creature:getId(), "newPlayerName", newName)
            npcHandler:say("Ótimo nome! Agora, qual caminho você seguirá?", npc, creature)
            npcHandler:say("**[1] Guerreiro**, **[2] Arqueiro**, **[3] Mago** ou **[4] Druida**? Escolha pelo número.", npc, creature)
            npcHandler.topic[creature:getId()] = 2
        else
            npcHandler:say("O nome deve ter entre 3 e 30 caracteres. Tente novamente.", npc, creature)
        end
    elseif npcHandler.topic[creature:getId()] == 2 then
        -- Aguardando a vocação
        local vocation = tonumber(message)
        local vocationId = nil
        if vocation == 1 then
            vocationId = 1 -- Guerreiro
        elseif vocation == 2 then
            vocationId = 2 -- Arqueiro
        elseif vocation == 3 then
            vocationId = 3 -- Mago
        elseif vocation == 4 then
            vocationId = 4 -- Druida
        end

        if vocationId then
            local newName = npcHandler:getPlayerStorage(creature:getId(), "newPlayerName")
            if newName then
                -- Criação do personagem no banco de dados
                local accountId = player:getAccountId()
                local query = string.format([[
                    INSERT INTO `players` (`name`, `account_id`, `vocation`, `sex`, `level`, `health`, `healthmax`, `mana`, `manamax`, `experience`, `town_id`, `posx`, `posy`, `posz`)
                    VALUES (%s, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d)
                ]], db.escapeString(newName), accountId, vocationId, 0, 1, 150, 150, 0, 0, 0, 1, 0, 0, 7)

                if db.query(query) then
                    npcHandler:say("Parabéns! O herói **" .. newName .. "** foi criado com sucesso! Agora você pode fazer login com ele.", npc, creature)
                    -- Envia um efeito visual de sucesso
                    player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
                else
                    npcHandler:say("Ocorreu um erro ao criar o personagem. Tente novamente mais tarde.", npc, creature)
                end
                npcHandler:setPlayerStorage(creature:getId(), "newPlayerName", nil)
            else
                npcHandler:say("Ocorreu um erro. Por favor, diga **[criar]** para recomeçar.", npc, creature)
            end
            npcHandler.topic[creature:getId()] = 0
        else
            npcHandler:say("Opção inválida. Escolha 1, 2, 3 ou 4.", npc, creature)
        end
    end
    return true
end

-- =============================================================================
-- REGISTRO FINAL DO NPC
-- =============================================================================
npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new())
npcType:register(npcConfig)