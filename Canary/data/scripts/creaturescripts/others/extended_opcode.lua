-- data/scripts/creaturescripts/others/#extended_opcode.lua
dofile('data/scripts/libs/opcodes.lua')

local extendedOpcode = CreatureEvent("ExtendedOpcode")

function extendedOpcode.onExtendedOpcode(player, opcode, buffer)
    -- Opcode de idioma (existente)
    if opcode == OPCODES.LANGUAGE then
        -- ... (código existente)
        return true
    end

    -- Criação de Personagem
    if opcode == OPCODES.CHARACTER_CREATE_REQUEST then
        local status, data = pcall(json.decode, buffer)
        if not status then
            player:sendExtendedOpcode(OPCODES.CHARACTER_CREATE_RESPONSE, json.encode({ success = false, error_code = "invalid_data", message = "Dados inválidos." }))
            return true
        end

        local charName = data.name
        local vocationId = tonumber(data.vocation)

        -- Validações no servidor (segurança)
        if not charName or #charName < 3 or #charName > 20 then
            player:sendExtendedOpcode(OPCODES.CHARACTER_CREATE_RESPONSE, json.encode({ success = false, error_code = "invalid_name_length", message = "Nome inválido (3-20 caracteres)." }))
            return true
        end

        -- Verifica se o nome já existe
        local resultId = db.storeQuery("SELECT `id` FROM `players` WHERE `name` = " .. db.escapeString(charName))
        if resultId then
            result.free(resultId)
            player:sendExtendedOpcode(OPCODES.CHARACTER_CREATE_RESPONSE, json.encode({ success = false, error_code = "name_taken", message = "Este nome de personagem já está em uso." }))
            return true
        end

        -- Obtém o ID da conta do jogador dummy
        local accountId = player:getAccountId()

        -- Verifica se a conta já atingiu o limite de personagens (exemplo: 5)
        local charCountResult = db.storeQuery("SELECT COUNT(*) AS count FROM `players` WHERE `account_id` = " .. accountId)
        local charCount = result.getNumber(charCountResult, "count")
        result.free(charCountResult)
        if charCount >= 5 then
            player:sendExtendedOpcode(OPCODES.CHARACTER_CREATE_RESPONSE, json.encode({ success = false, error_code = "character_limit", message = "Limite de personagens por conta atingido." }))
            return true
        end

        -- Cria o personagem usando uma função auxiliar (definida abaixo)
        local success, errMsg = createCharacter(player, charName, vocationId, player:getSex(), 1) -- townId = 1
        if success then
            player:sendExtendedOpcode(OPCODES.CHARACTER_CREATE_RESPONSE, json.encode({ success = true, error_code = "", message = "Personagem criado com sucesso!" }))
            -- Remover o personagem dummy da conta? (opcional)
            -- db.query("DELETE FROM `players` WHERE `name` = 'CriadorDeHerois' AND `account_id` = " .. accountId)
        else
            player:sendExtendedOpcode(OPCODES.CHARACTER_CREATE_RESPONSE, json.encode({ success = false, error_code = "database_error", message = errMsg or "Falha ao criar personagem." }))
        end
        return true
    end

    return false
end

-- Função auxiliar para criar personagem (em Lua, sem binding C++)
function createCharacter(player, name, vocationId, sex, townId)
    -- Valores padrão para novos personagens
    local level = 1
    local health = 150
    local healthMax = 150
    local experience = 0
    local mana = 0
    local manaMax = 0
    local soul = 100
    local cap = 400
    local looktype = (sex == PLAYERSEX_FEMALE) and 136 or 128
    local lookaddons = 0
    local lookhead = 78
    local lookbody = 106
    local looklegs = 58
    local lookfeet = 76
    local posx, posy, posz = 1000, 1000, 7 -- Coordenadas iniciais (cidade inicial)

    -- Busca a posição da town
    local townResult = db.storeQuery("SELECT `posx`, `posy`, `posz` FROM `towns` WHERE `id` = " .. townId)
    if townResult then
        posx = result.getNumber(townResult, "posx")
        posy = result.getNumber(townResult, "posy")
        posz = result.getNumber(townResult, "posz")
        result.free(townResult)
    end

    local accountId = player:getAccountId()
    local creationTime = os.time()

    -- Insere o novo personagem na tabela players
    local query = [[
        INSERT INTO `players`
        (`name`, `account_id`, `level`, `vocation`, `health`, `healthmax`, `experience`, `lookbody`, `lookfeet`, `lookhead`, `looklegs`, `looktype`, `lookaddons`, `maglevel`, `mana`, `manamax`, `manaspent`, `soul`, `town_id`, `posx`, `posy`, `posz`, `conditions`, `cap`, `sex`, `lastlogin`, `lastip`, `save`, `skull`, `skulltime`, `lastlogout`, `blessings`, `onlinetime`, `deletion`, `balance`, `offlinetraining_time`, `offlinetraining_skill`, `stamina`, `skill_fist`, `skill_fist_tries`, `skill_club`, `skill_club_tries`, `skill_sword`, `skill_sword_tries`, `skill_axe`, `skill_axe_tries`, `skill_dist`, `skill_dist_tries`, `skill_shielding`, `skill_shielding_tries`, `skill_fishing`, `skill_fishing_tries`, `skill_critical_chance`, `skill_critical_damage`, `skill_life_leech_chance`, `skill_life_leech_amount`, `skill_mana_leech_chance`, `skill_mana_leech_amount`, `skill_star`, `skill_star_tries`, `skill_star_level`, `skill_vitality`, `skill_vitality_tries`, `skill_vitality_level`, `skill_momentum`, `skill_momentum_tries`, `skill_momentum_level`, `skill_focus`, `skill_focus_tries`, `skill_focus_level`, `skill_focus_mastery`, `skill_focus_mastery_tries`)
        VALUES
        (%s, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, '', %d, %d, %d, 0, 1, 0, 0, %d, 0, 0, 0, 0, 0, 0, 201660000, 10, 0, 10, 0, 10, 0, 10, 0, 10, 0, 10, 0, 10, 0, 0, 0, 0, 0, 0, 0, 10, 0, 0, 10, 0, 0, 10, 0, 0, 10, 0, 0, 10, 0)
    ]]

    local insertQuery = string.format(query,
        db.escapeString(name), accountId, level, vocationId, health, healthMax, experience,
        lookbody, lookfeet, lookhead, looklegs, looktype, lookaddons, 0, mana, manaMax, 0, soul,
        townId, posx, posy, posz, cap, sex, creationTime, creationTime, 0
    )

    local success = db.executeQuery(insertQuery)
    if success then
        return true, nil
    else
        return false, "Erro ao inserir personagem no banco de dados."
    end
end

extendedOpcode:register()