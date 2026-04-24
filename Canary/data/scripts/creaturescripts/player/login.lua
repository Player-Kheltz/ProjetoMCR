--[[
Projeto: MCR
Módulo: Script de Login do Jogador
Arquivo: data/scripts/creaturescripts/player/login.lua
Descrição: Gerencia todas as ações executadas quando um jogador faz login no servidor.
Inclui o redirecionamento do personagem "Alma" para o Salão dos Destinos.
--]]

-- Função auxiliar para enviar mensagens de boost
local function sendBoostMessage(player, category, isIncreased)
    local status = isIncreased and "aumentado(a)" or "reduzido(a)"
    return player:sendTextMessage(MESSAGE_BOOSTED_CREATURE, string.format("Evento! %s está %s. Boa caçada!", category, status))
end

-- Evento de Login Global
local playerLoginGlobal = CreatureEvent("PlayerLoginGlobal")

function playerLoginGlobal.onLogin(player)
    -- =========================================================================
    -- BOAS-VINDAS
    -- =========================================================================
    local loginStr
    if player:getLastLoginSaved() == 0 then
        -- Primeiro login
        loginStr = "Por favor, escolha seu visual."
        player:sendOutfitWindow()

        -- Define o streak level inicial, se configurado
        local startStreakLevel = configManager.getNumber(configKeys.START_STREAK_LEVEL)
        if startStreakLevel > 0 then
            player:setStreakLevel(startStreakLevel)
        end

        -- Marca o tutorial como concluído
        db.query("UPDATE `players` SET `istutorial` = 0 WHERE `id` = " .. player:getGuid())
    else
        -- Login de retorno
        loginStr = string.format("Sua última visita em %s: %s.", SERVER_NAME, os.date("%d %b %Y %X", player:getLastLoginSaved()))
    end
    player:sendTextMessage(MESSAGE_LOGIN, loginStr)

    -- =========================================================================
    -- REGISTRO DE EVENTOS
    -- =========================================================================
    -- Registra o evento de Extended Opcode para comunicação cliente-servidor
    player:registerEvent("ExtendedOpcode")

    -- =========================================================================
    -- SALÃO DOS DESTINOS (Account Manager "Alma")
    -- =========================================================================
    if player:getName() == "Alma" then
        local destino = Position(666, 666, 15) -- VERIFICAÇÃO PENDENTE: Coordenadas do Salão dos Destinos
        player:teleportTo(destino)
        player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Você foi convocado ao Salão dos Destinos para forjar seu novo herói.")
        -- O NPC Oráculo iniciará o diálogo automaticamente quando o Alma se aproximar
    end

    -- =========================================================================
    -- GERENCIAMENTO DE PROMOÇÃO
    -- =========================================================================
    local vocation = player:getVocation()
    local promotion = vocation:getPromotion()
    if player:isPremium() then
        local hasPromotion = player:kv():get("promoted")
        if not player:isPromoted() and hasPromotion then
            player:setVocation(promotion)
        end
    elseif player:isPromoted() then
        player:setVocation(vocation:getDemotion())
    end

    -- =========================================================================
    -- CRIATURAS E BOSSES BOOSTADOS
    -- =========================================================================
    player:sendTextMessage(MESSAGE_BOOSTED_CREATURE, string.format("Criatura boostada de hoje: %s.", Game.getBoostedCreature()))
    player:sendTextMessage(MESSAGE_BOOSTED_CREATURE, string.format("Boss boostado de hoje: %s.", Game.getBoostedBoss()))

    -- =========================================================================
    -- BAÚ DE RECOMPENSAS
    -- =========================================================================
    local rewards = #player:getRewardList()
    if rewards > 0 then
        player:sendTextMessage(MESSAGE_LOGIN, string.format("Você tem %d recompensa(s) em seu baú de recompensas.", rewards))
    end

    -- =========================================================================
    -- EVENTOS DE TAXAS (RATES)
    -- =========================================================================
    if SCHEDULE_EXP_RATE ~= 100 then
        sendBoostMessage(player, "Taxa de Experiência", SCHEDULE_EXP_RATE > 100)
    end

    if SCHEDULE_SPAWN_RATE ~= 100 then
        sendBoostMessage(player, "Taxa de Spawn", SCHEDULE_SPAWN_RATE > 100)
    end

    if SCHEDULE_LOOT_RATE ~= 100 then
        sendBoostMessage(player, "Taxa de Loot", SCHEDULE_LOOT_RATE > 100)
    end

    if SCHEDULE_BOSS_LOOT_RATE ~= 100 then
        sendBoostMessage(player, "Taxa de Loot de Boss", SCHEDULE_BOSS_LOOT_RATE > 100)
    end

    if SCHEDULE_SKILL_RATE ~= 100 then
        sendBoostMessage(player, "Taxa de Skill", SCHEDULE_SKILL_RATE > 100)
    end

    -- =========================================================================
    -- OUTFIT DE RECRUTADOR
    -- =========================================================================
    local resultId = db.storeQuery("SELECT `recruiter` FROM `accounts` WHERE `id`= " .. player:getAccountId())
    if resultId then
        local recruiterStatus = result.getNumber(resultId, "recruiter")
        result:free()
        local sex = player:getSex()
        local outfitId = (sex == 1) and 746 or 745
        for outfitAddOn = 0, 2 do
            if recruiterStatus >= outfitAddOn * 3 + 1 then
                if not player:hasOutfit(outfitId, outfitAddOn) then
                    if outfitAddOn == 0 then
                        player:addOutfit(outfitId)
                    else
                        player:addOutfitAddon(outfitId, outfitAddOn)
                    end
                end
            end
        end
    end

    -- =========================================================================
    -- EXIBIÇÃO DE EXPERIÊNCIA NO CLIENTE
    -- =========================================================================
    if configManager.getBoolean(configKeys.XP_DISPLAY_MODE) then
        local baseRate = player:getFinalBaseRateExperience() * 100
        if configManager.getBoolean(configKeys.VIP_SYSTEM_ENABLED) then
            local vipBonusExp = configManager.getNumber(configKeys.VIP_BONUS_EXP)
            if vipBonusExp > 0 and player:isVip() then
                vipBonusExp = (vipBonusExp > 100 and 100) or vipBonusExp
                baseRate = baseRate * (1 + (vipBonusExp / 100))
                player:sendTextMessage(MESSAGE_BOOSTED_CREATURE, string.format("XP base normal: %d%%. Por ser VIP, bônus de %d%%.", baseRate, vipBonusExp))
            end
        end

        player:setBaseXpGain(baseRate)
    end

    -- =========================================================================
    -- BÔNUS DE STAMINA E LOW LEVEL
    -- =========================================================================
    player:setStaminaXpBoost(player:getFinalBonusStamina() * 100)
    player:getFinalLowLevelBonus()

    -- =========================================================================
    -- SISTEMA VIP
    -- =========================================================================
    if configManager.getBoolean(configKeys.VIP_SYSTEM_ENABLED) then
        local isCurrentlyVip = player:isVip()
        local hadVipStatus = player:kv():scoped("account"):get("vip-system") or false

        if hadVipStatus ~= isCurrentlyVip then
            if hadVipStatus then
                player:onRemoveVip()
            else
                player:onAddVip(player:getVipDays())
            end
        end

        if isCurrentlyVip then
            player:sendVipStatus()
        end
    end

    -- =========================================================================
    -- MODO FANTASMA PARA GAMEMASTERS
    -- =========================================================================
    if player:getGroup():getId() >= GROUP_TYPE_GAMEMASTER then
        player:setGhostMode(true)
    end

    -- =========================================================================
    -- RESET DE SISTEMAS DE EXERCÍCIO
    -- =========================================================================
    if _G.OnExerciseTraining[player:getId()] then
        stopEvent(_G.OnExerciseTraining[player:getId()].event)
        _G.OnExerciseTraining[player:getId()] = nil
        player:setTraining(false)
    end

    -- =========================================================================
    -- INICIALIZAÇÃO DE TEMPORIZADORES E RECOMPENSAS DIÁRIAS
    -- =========================================================================
    local playerId = player:getId()
    _G.NextUseStaminaTime[playerId] = 1
    _G.NextUseXpStamina[playerId] = 1
    _G.NextUseConcoctionTime[playerId] = 1
    DailyReward.init(playerId)

    -- =========================================================================
    -- BOSS FIGHT
    -- =========================================================================
    local stats = player:inBossFight()
    if stats then
        stats.playerId = player:getId()
    end

    -- Remove o tempo de boss se o servidor foi salvo após o último login
    if GetDailyRewardLastServerSave() >= player:getLastLoginSaved() then
        player:setRemoveBossTime(1)
    end

    -- =========================================================================
    -- CORREÇÃO DE OUTFIT DE SUPORTE (EVITA CRASHES)
    -- =========================================================================
    local playerOutfit = player:getOutfit()
    if table.contains({ 75, 266, 302 }, playerOutfit.lookType) then
        playerOutfit.lookType = 136
        playerOutfit.lookAddons = 0
        player:setOutfit(playerOutfit)
    end

    -- =========================================================================
    -- REGISTRO DE EVENTOS ADICIONAIS
    -- =========================================================================
    player:initializeLoyaltySystem()
    player:registerEvent("PlayerDeath")
    player:registerEvent("DropLoot")
    player:registerEvent("BossParticipation")
    player:registerEvent("UpdatePlayerOnAdvancedLevel")

    -- =========================================================================
    -- BÔNUS DE ATAQUE BÁSICO PARA MONKS
    -- =========================================================================
    if vocation and vocation:getBaseId() == VOCATION.BASE_ID.MONK then
        local kv = player:kv()
        if (kv:get("monk-basic-atk-bonus") or 0) < 10 then
            logger.info("Definindo bônus de ataque básico do Monk para 10. Jogador: {}.", player:getName())
            kv:set("monk-basic-atk-bonus", 10)
        end
    end

    return true
end

playerLoginGlobal:register()