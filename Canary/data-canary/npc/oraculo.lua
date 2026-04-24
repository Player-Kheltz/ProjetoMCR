--[[
Projeto: MCR
Módulo: NPC Oráculo dos Caminhos (Criação de Personagem)
Arquivo: data-canary/npc/oraculo.lua
Descrição: Guia o Account Manager "Alma" na criação de um novo herói.
           Valida o nome, recebe sexo e vocação, cria o personagem e desconecta Alma.
--]]

-- Ajuste o caminho para a biblioteca de utilidades NPC (verifique local exato)
dofile('data/npc/lib/npc_utils.lua')

-- Configuração do NPC
local npcName = "Oráculo dos Caminhos"
local npcType = Game.createNpcType(npcName)
local npcConfig = {
    name = npcName,
    outfit = {
        lookType = 128,
        lookHead = 0,
        lookBody = 0,
        lookLegs = 0,
        lookFeet = 0
    },
    needReset = false,
    resetTime = 60
}

-- Registra o tipo de NPC (agora no início, como é padrão)
npcType:register(npcConfig)

-- Inicialização do sistema de palavras-chave e foco
local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)

-- ? Essencial: parseia os parâmetros (mas aqui não temos tabela 'parameters', é seguro)
NpcSystem.parseParameters(npcHandler)

-- Constantes
local VOCATIONS = {
    ["guerreiro"] = {id = 1, nome = "Guerreiro"},
    ["arqueiro"]  = {id = 2, nome = "Arqueiro"},
    ["mago"]      = {id = 3, nome = "Mago"},
    ["druida"]    = {id = 4, nome = "Druida"}
}
local VALID_CHARS_PATTERN = "^[a-zA-Z0-9áéíóúàèìòùâêîôûãõçÁÉÍÓÚÀÈÌÒÙÂÊÎÔÛÃÕÇ .'-]+$"
local START_POS = {x = 1000, y = 1000, z = 7} -- VERIFICAÇÃO PENDENTE: coordenadas reais da cidade inicial

-- Funções de validação e criação
local function isValidName(name)
    if not name or name:len() < 3 or name:len() > 20 then return false end
    return name:match(VALID_CHARS_PATTERN) ~= nil
end

local function isNameTaken(name)
    local result = db.storeQuery("SELECT `id` FROM `players` WHERE `name` = " .. db.escapeString(name) .. " LIMIT 1")
    local taken = result and result:getRows(true) > 0
    if result then Result.free(result) end
    return taken
end

local function createCharacter(accountId, name, sex, vocationId, pos)
    local success, err = pcall(function()
        db.query(
            "INSERT INTO `players` (`name`, `account_id`, `sex`, `vocation`, `level`, `health`, `healthmax`, `experience`, `looktype`, `posx`, `posy`, `posz`, `town_id`) " ..
            "VALUES (%s, %d, %d, %d, 8, 185, 185, 4200, %d, %d, %d, %d, 2)",
            db.escapeString(name), accountId, sex, vocationId,
            sex == 1 and 136 or 128,
            pos.x, pos.y, pos.z
        )
    end)
    return success
end

-- Callback de saudação automática
function greetCallback(cid)
    local player = Player(cid)
    if not player then return true end

    if player:getName() == "Alma" then
        npcHandler:say("Saudações, Alma! Sou o guardião dos destinos. Se deseja criar um novo herói, diga {{#00FF00}}criar personagem{{/}}.", cid)
    else
        npcHandler:say("Apenas a entidade conhecida como 'Alma' pode criar novos destinos.", cid)
    end
    return true
end

-- Callback principal de diálogo (completa)
function creatureSayCallback(cid, type, msg)
    local player = Player(cid)
    if not player then return true end

    if player:getName() ~= "Alma" then
        npcHandler:say("Apenas a entidade conhecida como 'Alma' pode criar novos destinos.", cid)
        return true
    end

    msg = msg:lower()
    local topic = npcHandler.topic[cid] or 0

    -- Estado 0: aguardando "criar personagem"
    if topic == 0 then
        if NpcUtils.correspondeAcao(msg, {"criar personagem", "novo heroi", "criar"}) then
            npcHandler:say("Muito bem! Vamos moldar um novo destino. Primeiro, diga o nome que deseja para o herói.", cid)
            npcHandler.topic[cid] = 1
        end
        return true
    end

    -- Estado 1: recebendo o nome
    if topic == 1 then
        local name = msg:gsub("^%l", string.upper)
        if not isValidName(name) then
            npcHandler:say("Esse nome não é válido. Use de 3 a 20 caracteres e apenas letras, números, espaços, apóstrofos e hífens.", cid)
            return true
        end
        if isNameTaken(name) then
            npcHandler:say("Já existe um herói com esse nome. Escolha outro.", cid)
            return true
        end
        npcHandler.topic[cid] = 2
        npcHandler:say("Nome '" .. name .. "' aceito! Agora, escolha o sexo do herói: {{#00FF00}}masculino{{/}} ou {{#00FF00}}feminino{{/}}.", cid)
        if not npcHandler.data then npcHandler.data = {} end
        npcHandler.data[cid] = { name = name }
        return true
    end

    -- Estado 2: escolha do sexo
    if topic == 2 then
        local sexo = nil
        if NpcUtils.correspondeAcao(msg, {"masculino"}) then
            sexo = 0
        elseif NpcUtils.correspondeAcao(msg, {"feminino"}) then
            sexo = 1
        end
        if not sexo then
            npcHandler:say("Por favor, diga {{#00FF00}}masculino{{/}} ou {{#00FF00}}feminino{{/}}.", cid)
            return true
        end
        npcHandler.data[cid].sex = sexo
        npcHandler.topic[cid] = 3
        npcHandler:say("Ótimo! Agora escolha a vocação do herói:\n" ..
            "{{#00BFFF}}Guerreiro{{/}} - mestre da espada\n" ..
            "{{#00BFFF}}Arqueiro{{/}} - perito em ataques à distância\n" ..
            "{{#00BFFF}}Mago{{/}} - manipulador das artes arcanas\n" ..
            "{{#00BFFF}}Druida{{/}} - guardião da natureza\n" ..
            "Diga o nome da vocação desejada.", cid)
        return true
    end

    -- Estado 3: escolha da vocação
    if topic == 3 then
        local voc = VOCATIONS[msg]
        if not voc then
            npcHandler:say("Vocação desconhecida. Escolha entre: Guerreiro, Arqueiro, Mago ou Druida.", cid)
            return true
        end
        npcHandler.data[cid].vocation = voc.id
        npcHandler.topic[cid] = 4
        local dados = npcHandler.data[cid]
        npcHandler:say("Resumo da criação:\n" ..
            "Nome: " .. dados.name .. "\n" ..
            "Sexo: " .. (dados.sex == 0 and "Masculino" or "Feminino") .. "\n" ..
            "Vocação: " .. VOCATIONS[msg].nome .. "\n" ..
            "Digite {{#00FF00}}confirmar{{/}} para concluir ou {{#00FF00}}cancelar{{/}} para reiniciar.", cid)
        return true
    end

    -- Estado 4: confirmação final
    if topic == 4 then
        if NpcUtils.correspondeAcao(msg, {"confirmar"}) then
            local dados = npcHandler.data[cid]
            local success = createCharacter(player:getAccountId(), dados.name, dados.sex, dados.vocation, START_POS)
            if success then
                npcHandler:say("O herói " .. dados.name .. " foi criado com sucesso! Quando estiver pronto, ele aguardará na lista de personagens.\n" ..
                    "Alma, sua missão está cumprida. Até o próximo destino!", cid)
                addEvent(function()
                    local alma = Player(cid)
                    if alma then alma:remove() end
                end, 2000)
            else
                npcHandler:say("Houve um erro ao criar o personagem. Verifique os logs do servidor.", cid)
            end
            npcHandler.topic[cid] = 0
            npcHandler.data[cid] = nil
            return true
        end
        if NpcUtils.correspondeAcao(msg, {"cancelar"}) then
            npcHandler:say("Criação cancelada. Podemos recomeçar quando quiser.", cid)
            npcHandler.topic[cid] = 0
            npcHandler.data[cid] = nil
            return true
        end
        npcHandler:say("Por favor, diga {{#00FF00}}confirmar{{/}} ou {{#00FF00}}cancelar{{/}}.", cid)
        return true
    end

    return true
end

-- Registro das callbacks
npcHandler:setCallback(CALLBACK_GREET, greetCallback)
npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)

-- ??? FUNÇÕES OBRIGATÓRIAS DE CICLO DE VIDA (fazem o vínculo com o NPC) ???
function onCreatureAppear(cid)
    npcHandler:onCreatureAppear(cid)
end

function onCreatureDisappear(cid)
    npcHandler:onCreatureDisappear(cid)
end

function onCreatureSay(cid, type, msg)
    npcHandler:onCreatureSay(cid, type, msg)
end

function onThink()
    npcHandler:onThink()
end

-- Agora sim, após tudo configurado, adiciona o módulo de foco
npcHandler:addModule(FocusModule:new())