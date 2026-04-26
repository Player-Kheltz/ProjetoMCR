--[[
Projeto: MCR
Módulo: Biblioteca de suporte ao Account Manager (Oráculo)
Arquivo: data/scripts/lib/mcr_account_lib.lua
Descrição: Funções de validação e criação de conta/personagem.
]]--

MCR_AccountLib = {}

MCR_AccountLib.ACCOUNT_NAME_MIN_LENGTH = 3
MCR_AccountLib.ACCOUNT_NAME_MAX_LENGTH = 20
MCR_AccountLib.PASSWORD_MIN_LENGTH = 3
MCR_AccountLib.PASSWORD_MAX_LENGTH = 30
MCR_AccountLib.CHARACTER_NAME_FORMAT = "[a-zA-Z%s]+"
MCR_AccountLib.CHARACTER_NAME_MIN_LENGTH = 3
MCR_AccountLib.CHARACTER_NAME_MAX_LENGTH = 20
MCR_AccountLib.CHARACTER_NAME_MAX_WORDS = 3

MCR_AccountLib.CHARACTER_DEFAULT = {
    TOWN = 1,
    POSX = 1000,
    POSY = 1000,
    POSZ = 6,
    LEVEL = 8,
    HEALTH = 185,
    MANA = 35,
    CAPACITY = 420,
    SKILL = 10,
    STAMINA = 2520,
    SOUL = 100,
    MAGIC_LEVEL = 0,
    OUTFIT_MALE = 128,
    OUTFIT_FEMALE = 136,
    OUTFIT_ADDONS = 0,
    OUTFIT_HEAD = 0,
    OUTFIT_BODY = 0,
    OUTFIT_LEGS = 0,
    OUTFIT_FEET = 0
}

local CREATE_ACCOUNT_EXHAUST = 30 * 60
local CREATE_CHARACTER_EXHAUST = 3 * 60
local createAccountIP = {}
local createCharIP = {}

function MCR_AccountLib.getAccountIdByName(name)
    local dbResult = db.storeQuery("SELECT `id` FROM `accounts` WHERE `name` = " .. db.escapeString(name) .. " LIMIT 1;")
    if dbResult then
        local id = result.getNumber(dbResult, "id")
        result.free(dbResult)
        return id
    end
    return nil
end

function MCR_AccountLib.getPlayerIdByName(name)
    local dbResult = db.storeQuery("SELECT `id` FROM `players` WHERE `name` = " .. db.escapeString(name) .. " LIMIT 1;")
    if dbResult then
        local id = result.getNumber(dbResult, "id")
        result.free(dbResult)
        return id
    end
    return nil
end

function MCR_AccountLib.validateAccountName(name)
    local len = name:len()
    if len < MCR_AccountLib.ACCOUNT_NAME_MIN_LENGTH then return "too short" end
    if len > MCR_AccountLib.ACCOUNT_NAME_MAX_LENGTH then return "too long" end
    if not name:match("^[a-zA-Z0-9]+$") then return "invalid characters" end
    return "valid"
end

function MCR_AccountLib.validatePassword(password)
    local len = password:len()
    if len < MCR_AccountLib.PASSWORD_MIN_LENGTH then return "too short" end
    if len > MCR_AccountLib.PASSWORD_MAX_LENGTH then return "too long" end
    return "valid"
end

function MCR_AccountLib.validateCharacterName(name)
    local len = name:len()
    if len < MCR_AccountLib.CHARACTER_NAME_MIN_LENGTH then return "too short" end
    if len > MCR_AccountLib.CHARACTER_NAME_MAX_LENGTH then return "too long" end
    if not name:match("^[A-Z][a-z]+( [A-Z][a-z]+)*$") then
        return "invalid format"
    end
    local words = name:split(" ")
    if #words > MCR_AccountLib.CHARACTER_NAME_MAX_WORDS then return "too many words" end
    return "valid"
end

function MCR_AccountLib.createAccount(accountName, password, ip)
    if MCR_AccountLib.getAccountIdByName(accountName) then
        return nil, "Já existe uma conta com este nome."
    end
    local now = os.time()
    if createAccountIP[ip] and createAccountIP[ip] > now then
        return nil, "Aguarde antes de criar outra conta."
    end
    local hash = transformToSHA1(password)
    local success = db.query("INSERT INTO `accounts` (`name`, `password`, `creation`) VALUES (" ..
        db.escapeString(accountName) .. ", HEX(" .. db.escapeString(hash) .. "), " .. now .. ");")
    if not success then
        return nil, "Falha ao criar a conta."
    end
    local accountId = MCR_AccountLib.getAccountIdByName(accountName)
    if not accountId then
        return nil, "Erro ao recuperar ID da conta."
    end
    createAccountIP[ip] = now + CREATE_ACCOUNT_EXHAUST
    return accountId
end

function MCR_AccountLib.createCharacter(character, ip)
    if MCR_AccountLib.getPlayerIdByName(character.name) then
        return nil, "Já existe um personagem com este nome."
    end
    local now = os.time()
    if createCharIP[ip] and createCharIP[ip] > now then
        return nil, "Aguarde antes de criar outro personagem."
    end
    local def = MCR_AccountLib.CHARACTER_DEFAULT
    local lookType = character.sex == PLAYERSEX_FEMALE and def.OUTFIT_FEMALE or def.OUTFIT_MALE
    local query = string.format([[
        INSERT INTO `players` 
        (`name`, `account_id`, `vocation`, `health`, `healthmax`, `lookbody`, `lookfeet`, `lookhead`, `looklegs`, `looktype`, `lookaddons`, `maglevel`, `mana`, `manamax`, `sex`, `town_id`, `posx`, `posy`, `posz`, `cap`, `lastip`, `stamina`, `skill_fist`, `skill_club`, `skill_sword`, `skill_axe`, `skill_dist`, `skill_shielding`, `skill_fishing`)
        VALUES (%s, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d)
    ]],
        db.escapeString(character.name),
        character.accountId, character.vocation,
        def.HEALTH, def.HEALTH,
        def.OUTFIT_BODY, def.OUTFIT_FEET, def.OUTFIT_HEAD, def.OUTFIT_LEGS, lookType,
        def.OUTFIT_ADDONS, def.MAGIC_LEVEL, def.MANA, def.MANA,
        character.sex, def.TOWN, def.POSX, def.POSY, def.POSZ, def.CAPACITY,
        ip, def.STAMINA,
        def.SKILL, def.SKILL, def.SKILL, def.SKILL, def.SKILL, def.SKILL, def.SKILL
    )
    if not db.query(query) then
        return nil, "Erro ao criar personagem."
    end
    createCharIP[ip] = now + CREATE_CHARACTER_EXHAUST
    return true
end