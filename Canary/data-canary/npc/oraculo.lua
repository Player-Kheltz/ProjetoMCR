--[[
Projeto: MCR
Módulo: Account Manager "Alma" – NPC Oráculo dos Caminhos
Arquivo: data/npc/scripts/oraculo.lua
Descrição: NPC responsável por guiar o jogador no "Salão dos Destinos",
oferecendo criação de personagem, alteração de senha e exclusão de personagens.
Implementa a experiência 100% no cliente, substituindo interfaces externas.
--]]

dofile('MCR Scripts/npc_utils.lua')

-- Configuração do NPC
local npcName = "Oráculo dos Caminhos"
local npcType = Game.createNpcType(npcName)
local npcConfig = {
    name = npcName,
    outfit = { lookType = 160, lookHead = 0, lookBody = 0, lookLegs = 0, lookFeet = 0, lookAddons = 0 },
    floorChange = false
}

-- Constantes do Sistema (Storages e Opcodes)
local STORAGE_ALMA_ACCOUNT_MANAGER = 50010      -- Indica que o personagem é o "Alma" da conta
local STORAGE_CREATION_STEP = 50011            -- Etapa do fluxo de criação (1=nome, 2=sexo, 3=vocacao)
local STORAGE_TEMP_NAME = 50012                -- Nome temporário escolhido
local STORAGE_TEMP_SEX = 50013                 -- Sexo temporário (0=masc, 1=fem)
local STORAGE_DELETE_TARGET = 50014            -- GUID do personagem a ser deletado (para confirmação)

local OPCODE_QUEST_UPDATE = 180                -- Reservado para atualizações de HUD/Toast (conforme seção 6.6)
local OPCODE_ACCOUNT_MANAGER = 200             -- Comunicações específicas do Account Manager

-- Lista branca de caracteres seguros para nomes (evita corrupção visual no OTClient)
local function isNameAllowed(name)
    if not name or #name < 3 or #name > 20 then return false end
    for b in string.gmatch(name, ".") do
        local byte = string.byte(b)
        if byte == 0xE3 or byte == 0xF5 or byte == 0xED or byte == 0xFA or byte == 0xE9 or byte == 0xE1 then
            return false
        end
    end
    return true
end

-- Verifica se o nome já existe no banco
local function isNameTaken(name)
    local result = db.storeQuery("SELECT `id` FROM `players` WHERE `name` = " .. db.escapeString(name))
    if result then
        result:free()
        return true
    end
    return false
end

-- Cria o personagem no banco de dados
local function createCharacter(accountId, name, sex, vocationId)
    local townId = 1 -- VERIFICAÇÃO PENDENTE: ID da cidade inicial (Temple) no mapa MCR
    local posX, posY, posZ = 100, 100, 7 -- VERIFICAÇÃO PENDENTE: Coordenadas de spawn inicial

    db.query("INSERT INTO `players` (`name`, `account_id`, `vocation`, `sex`, `town_id`, `posx`, `posy`, `posz`, `level`, `health`, `healthmax`, `experience`, `looktype`, `lookhead`, `lookbody`, `looklegs`, `lookfeet`, `lookaddons`, `maglevel`, `mana`, `manamax`, `manaspent`, `soul`, `conditions`, `cap`, `lastlogin`, `lastip`, `save`, `skull`, `skulltime`, `deleted`) VALUES (" ..
        db.escapeString(name) .. ", " .. accountId .. ", " .. vocationId .. ", " .. sex .. ", " .. townId .. ", " .. posX .. ", " .. posY .. ", " .. posZ .. ", 1, 150, 150, 0, " .. (sex == 0 and 128 or 136) .. ", 0, 0, 0, 0, 0, 0, 5, 5, 0, 100, '', 400, 0, 0, 1, 0, 0, 0)")

    return true
end

-- Callbacks e Handlers
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)

-- Callback de saudação (chamado quando o jogador diz "hi", "olá", etc.)
function onGreet(cid)
    local player = Player(cid)
    if not player then return false end

    -- Verifica se o jogador é o "Alma" da conta (Account Manager)
    local isAlma = (player:getName():lower() == "alma") or (player:getStorageValue(STORAGE_ALMA_ACCOUNT_MANAGER) == 1)
    if not isAlma then
        npcHandler:say("Apenas aquele que carrega o nome de 'Alma' pode adentrar os segredos do destino. Se você não é Alma, sua jornada ainda não começou...", cid)
        return false -- Não inicia o diálogo
    end

    -- Inicia o diálogo normalmente
    npcHandler.topic[cid] = 0
    local tr = NpcUtils.getTratamento(player)
    npcHandler:say("Saudações, " .. tr.artigo .. " " .. tr.vocativo .. "! Sou o Oráculo dos Caminhos, guardião do Salão dos Destinos. Você pode:\n" ..
                   "{{#00FF00}}criar personagem{{/}} - forjar um novo herói\n" ..
                   "{{#00FF00}}alterar senha{{/}} - modificar a senha da conta\n" ..
                   "{{#00FF00}}deletar personagem{{/}} - apagar um herói existente\n" ..
                   "{{#00FF00}}sair{{/}} - encerrar nossa conversa", cid)
    return true
end

-- Callback de despedida (opcional, para limpar estado)
function onFarewell(cid)
    npcHandler.topic[cid] = nil
    npcHandler:releaseFocus(cid)
    return true
end

function creatureSayCallback(cid, type, msg)
    local player = Player(cid)
    if not player then return true end
    local msgLower = msg:lower()

    -- Verifica novamente se é o Alma (segurança extra)
    local isAlma = (player:getName():lower() == "alma") or (player:getStorageValue(STORAGE_ALMA_ACCOUNT_MANAGER) == 1)
    if not isAlma then
        return true
    end

    -- Se o jogador disser "sair" em qualquer momento, encerra o diálogo
    if NpcUtils.correspondeAcao(msgLower, {"sair", "terminar", "fechar", "adeus"}) then
        npcHandler:say("Que os ventos do destino o guiem, Alma. Retorne quando precisar de meus serviços.", cid)
        npcHandler:releaseFocus(cid)
        npcHandler.topic[cid] = nil
        return true
    end

    -- Diálogo Principal (Menu do Account Manager)
    if npcHandler.topic[cid] == 0 then
        if NpcUtils.correspondeAcao(msgLower, {"criar", "criar personagem", "novo personagem", "heroi"}) then
            npcHandler:say("Ah... você deseja forjar um novo herói para trilhar os caminhos deste mundo. Primeiro, preciso saber o {{#00BFFF}}nome{{/}} que ele carregará. Diga-me o nome desejado.", cid)
            npcHandler.topic[cid] = 1
            player:setStorageValue(STORAGE_CREATION_STEP, 1)
        elseif NpcUtils.correspondeAcao(msgLower, {"senha", "alterar senha", "mudar senha", "password"}) then
            npcHandler:say("Você deseja alterar a senha de sua conta. Diga a {{#00FF00}}senha atual{{/}} para prosseguir.", cid)
            npcHandler.topic[cid] = 10
        elseif NpcUtils.correspondeAcao(msgLower, {"deletar", "excluir", "apagar personagem", "remover personagem"}) then
            local result = db.storeQuery("SELECT `id`, `name`, `vocation`, `level` FROM `players` WHERE `account_id` = " .. player:getAccountId() .. " AND `name` != 'Alma' AND `deleted` = 0")
            if result then
                local list = {}
                repeat
                    local id = result.getNumber(result, "id")
                    local name = result.getString(result, "name")
                    local vocation = result.getNumber(result, "vocation")
                    local level = result.getNumber(result, "level")
                    table.insert(list, string.format("{{#00BFFF}}%s{{/}} (Nível %d) - ID %d", name, level, id))
                until not result.next(result)
                result:free()
                if #list > 0 then
                    npcHandler:say("Estes são os heróis vinculados à sua conta:\n" .. table.concat(list, "\n") .. "\n\nPara deletar um personagem, diga {{#00FF00}}deletar [ID]{{/}}. Exemplo: {{#00FF00}}deletar 5{{/}}.", cid)
                    npcHandler.topic[cid] = 20
                else
                    npcHandler:say("Sua conta não possui outros personagens além de mim, Alma. Crie um novo herói primeiro.", cid)
                    npcHandler.topic[cid] = 0
                end
            else
                npcHandler:say("Houve um erro ao consultar seus personagens. Tente novamente mais tarde.", cid)
            end
        else
            local tr = NpcUtils.getTratamento(player)
            npcHandler:say("Sou o Oráculo dos Caminhos, guardião do Salão dos Destinos. Você pode:\n" ..
                           "{{#00FF00}}criar personagem{{/}} - forjar um novo herói\n" ..
                           "{{#00FF00}}alterar senha{{/}} - modificar a senha da conta\n" ..
                           "{{#00FF00}}deletar personagem{{/}} - apagar um herói existente\n" ..
                           "{{#00FF00}}sair{{/}} - encerrar nossa conversa", cid)
        end
        return true
    end

    -- Fluxo de Criação de Personagem
    local step = player:getStorageValue(STORAGE_CREATION_STEP)
    if step == 1 then
        local name = msg:match("^%s*(.-)%s*$")
        if not isNameAllowed(name) then
            npcHandler:say("O nome '" .. name .. "' contém caracteres não permitidos ou não atende ao comprimento (3-20). Por favor, escolha outro.", cid)
            return true
        end
        if isNameTaken(name) then
            npcHandler:say("Esse nome já pertence a outro herói neste mundo. Escolha um nome diferente.", cid)
            return true
        end
        player:setStorageValue(STORAGE_TEMP_NAME, name)
        player:setStorageValue(STORAGE_CREATION_STEP, 2)
        npcHandler:say("Ótimo, o nome '" .. name .. "' está disponível. Agora, escolha o {{#00FF00}}sexo{{/}} do seu personagem: {{#00BFFF}}masculino{{/}} ou {{#00BFFF}}feminino{{/}}.", cid)
        npcHandler.topic[cid] = 1
    elseif step == 2 then
        local sexChoice = nil
        if NpcUtils.correspondeAcao(msgLower, {"masculino", "homem", "male", "masc"}) then
            sexChoice = 0
        elseif NpcUtils.correspondeAcao(msgLower, {"feminino", "mulher", "female", "fem"}) then
            sexChoice = 1
        end
        if sexChoice == nil then
            npcHandler:say("Por favor, especifique 'masculino' ou 'feminino'.", cid)
            return true
        end
        player:setStorageValue(STORAGE_TEMP_SEX, sexChoice)
        player:setStorageValue(STORAGE_CREATION_STEP, 3)
        npcHandler:say("Muito bem. Por fim, escolha a {{#00FF00}}vocação{{/}} que guiará o destino de seu herói:\n" ..
                       "{{#00BFFF}}guerreiro{{/}} - mestre da espada e escudo\n" ..
                       "{{#00BFFF}}arqueiro{{/}} - atirador preciso com arco e flecha\n" ..
                       "{{#00BFFF}}mago{{/}} - tecelão dos véus arcanos\n" ..
                       "{{#00BFFF}}druida{{/}} - guardião dos ciclos naturais", cid)
        npcHandler.topic[cid] = 1
    elseif step == 3 then
        local vocMap = {
            guerreiro = 1, knight = 1,
            arqueiro = 2, paladin = 2,
            mago = 3, sorcerer = 3,
            druida = 4, druid = 4
        }
        local vocId = nil
        for k, v in pairs(vocMap) do
            if msgLower:find(k, 1, true) then
                vocId = v
                break
            end
        end
        if not vocId then
            npcHandler:say("Não reconheci essa vocação. Por favor, diga 'guerreiro', 'arqueiro', 'mago' ou 'druida'.", cid)
            return true
        end

        local accountId = player:getAccountId()
        local name = player:getStorageValue(STORAGE_TEMP_NAME)
        local sex = player:getStorageValue(STORAGE_TEMP_SEX)

        local vocNames = {"Guerreiro", "Arqueiro", "Mago", "Druida"}
        local sexNames = {"masculino", "feminino"}
        npcHandler:say("Confirme os dados do novo herói:\n" ..
                       "Nome: {{#00BFFF}}" .. name .. "{{/}}\n" ..
                       "Sexo: {{#00BFFF}}" .. sexNames[sex+1] .. "{{/}}\n" ..
                       "Vocação: {{#00BFFF}}" .. vocNames[vocId] .. "{{/}}\n\n" ..
                       "Se estiver correto, diga {{#00FF00}}confirmar{{/}}. Para cancelar, diga {{#00FF00}}cancelar{{/}}.", cid)
        npcHandler.topic[cid] = 4
        player:setStorageValue(STORAGE_CREATION_STEP, 4)
        player:setStorageValue("temp_voc", vocId)
    elseif step == 4 then
        if NpcUtils.correspondeAcao(msgLower, {"confirmar", "sim", "criar"}) then
            local name = player:getStorageValue(STORAGE_TEMP_NAME)
            local sex = player:getStorageValue(STORAGE_TEMP_SEX)
            local vocId = player:getStorageValue("temp_voc")
            local accountId = player:getAccountId()

            if createCharacter(accountId, name, sex, vocId) then
                npcHandler:say("Seu novo herói, " .. name .. ", foi forjado com sucesso! Que sua jornada seja épica. Agora, devo libertá-lo deste Salão... Até breve.", cid)
                player:remove()
            else
                npcHandler:say("Ocorreu um erro inesperado ao criar o personagem. Por favor, tente novamente.", cid)
                player:setStorageValue(STORAGE_CREATION_STEP, -1)
                npcHandler.topic[cid] = 0
            end
        elseif NpcUtils.correspondeAcao(msgLower, {"cancelar", "nao", "abortar"}) then
            npcHandler:say("Entendo. A criação foi cancelada. O que mais deseja fazer?", cid)
            player:setStorageValue(STORAGE_CREATION_STEP, -1)
            npcHandler.topic[cid] = 0
        else
            npcHandler:say("Por favor, diga 'confirmar' para criar ou 'cancelar' para abortar.", cid)
        end
        return true
    end

    -- Fluxo de Alteração de Senha
    if npcHandler.topic[cid] == 10 then
        local currentPass = msg
        local accountId = player:getAccountId()
        local result = db.storeQuery("SELECT `password` FROM `accounts` WHERE `id` = " .. accountId)
        if result then
            local storedHash = result.getString(result, "password")
            result:free()
            if crypto.sha1(currentPass) == storedHash then
                npcHandler:say("Senha atual confirmada. Agora, diga a {{#00FF00}}nova senha{{/}} que deseja utilizar (mínimo 8 caracteres, letras e números).", cid)
                npcHandler.topic[cid] = 11
                player:setStorageValue("temp_pass_verified", 1)
            else
                npcHandler:say("A senha informada está incorreta. Operação cancelada.", cid)
                npcHandler.topic[cid] = 0
            end
        else
            npcHandler:say("Não foi possível verificar sua conta. Tente novamente.", cid)
            npcHandler.topic[cid] = 0
        end
        return true
    elseif npcHandler.topic[cid] == 11 then
        if player:getStorageValue("temp_pass_verified") ~= 1 then
            npcHandler.topic[cid] = 0
            return true
        end
        local newPass = msg
        if #newPass < 8 or not newPass:match("%a") or not newPass:match("%d") then
            npcHandler:say("A nova senha deve ter no mínimo 8 caracteres e conter pelo menos uma letra e um número. Tente novamente.", cid)
            return true
        end
        local accountId = player:getAccountId()
        local newHash = crypto.sha1(newPass)
        db.query("UPDATE `accounts` SET `password` = " .. db.escapeString(newHash) .. " WHERE `id` = " .. accountId)
        npcHandler:say("Sua senha foi alterada com sucesso! Guarde-a bem, pois ela é a chave para seu destino.", cid)
        player:setStorageValue("temp_pass_verified", -1)
        npcHandler.topic[cid] = 0
        return true
    end

    -- Fluxo de Exclusão de Personagem
    if npcHandler.topic[cid] == 20 then
        local guid = tonumber(msgLower:match("deletar%s+(%d+)"))
        if not guid then
            npcHandler:say("Para deletar um personagem, diga 'deletar [ID]' conforme listado. Exemplo: 'deletar 5'.", cid)
            return true
        end
        local result = db.storeQuery("SELECT `name` FROM `players` WHERE `id` = " .. guid .. " AND `account_id` = " .. player:getAccountId() .. " AND `name` != 'Alma' AND `deleted` = 0")
        if result then
            local name = result.getString(result, "name")
            result:free()
            player:setStorageValue(STORAGE_DELETE_TARGET, guid)
            npcHandler:say("Você tem certeza que deseja deletar permanentemente o personagem {{#00BFFF}}" .. name .. "{{/}}? Esta ação é {{#FF0000}}irreversível{{/}}. Diga {{#00FF00}}sim{{/}} para confirmar ou {{#00FF00}}não{{/}} para cancelar.", cid)
            npcHandler.topic[cid] = 21
        else
            npcHandler:say("Personagem não encontrado ou você não tem permissão para deletá-lo.", cid)
        end
        return true
    elseif npcHandler.topic[cid] == 21 then
        if NpcUtils.correspondeAcao(msgLower, {"sim", "confirmo", "delete"}) then
            local guid = player:getStorageValue(STORAGE_DELETE_TARGET)
            if guid and guid > 0 then
                db.query("UPDATE `players` SET `deleted` = 1 WHERE `id` = " .. guid)
                npcHandler:say("O personagem foi deletado. Que seu espírito encontre paz nos reinos esquecidos.", cid)
            end
            player:setStorageValue(STORAGE_DELETE_TARGET, -1)
            npcHandler.topic[cid] = 0
        elseif NpcUtils.correspondeAcao(msgLower, {"nao", "cancelar"}) then
            npcHandler:say("A exclusão foi cancelada. O que mais deseja fazer?", cid)
            player:setStorageValue(STORAGE_DELETE_TARGET, -1)
            npcHandler.topic[cid] = 0
        else
            npcHandler:say("Responda 'sim' para confirmar a exclusão ou 'não' para cancelar.", cid)
        end
        return true
    end

    return true
end

-- Configuração dos callbacks
npcHandler:setCallback(CALLBACK_GREET, onGreet)
npcHandler:setCallback(CALLBACK_FAREWELL, onFarewell)
npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)
npcHandler:addModule(FocusModule:new())

-- Registro do tipo de NPC
npcType:register(npcConfig)