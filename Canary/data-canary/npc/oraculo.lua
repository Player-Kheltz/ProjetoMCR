--[[
	Projeto MCR ? NPC Oráculo do Salão dos Destinos
	Funções: criar conta, criar personagem, gerenciar conta (senha, deletar/alterar personagem).
	Método: acesso direto ao banco de dados (sem HTTP).
	Salvar como: ISO-8859-1
--]]

dofile('data/MCR Scripts/npc_utils.lua')

local npcName = "Oraculo"
local npcType = Game.createNpcType(npcName)
local npcConfig = {
	name = npcName,
	description = "Um ancião místico que guarda os caminhos entre os mundos.",
	health = 100,
	maxHealth = 100,
	outfit = { lookType = 128, lookHead = 0, lookBody = 0, lookLegs = 0, lookFeet = 0, lookAddons = 0 }
}

local keywordHandler = KeywordHandler:new()
local npcHandler = NpcHandler:new(keywordHandler)

-- Tabela temporária para dados da conversa
local tempData = {}

-- Callbacks de engine
npcType.onThink = function(npc, interval) npcHandler:onThink(npc, interval) end
npcType.onAppear = function(npc, creature) npcHandler:onAppear(npc, creature) end
npcType.onDisappear = function(npc, creature) npcHandler:onDisappear(npc, creature) end
npcType.onMove = function(npc, creature, from, to) npcHandler:onMove(npc, creature, from, to) end
npcType.onSay = function(npc, creature, type, msg) npcHandler:onSay(npc, creature, type, msg) end
npcType.onCloseChannel = function(npc, player) npcHandler:onCloseChannel(npc, player) end

local function isGuestAccount(player)
	print("DEBUG: isGuestAccount para accountId=" .. player:getAccountId())
	local query = db.storeQuery("SELECT name FROM accounts WHERE id = " .. player:getAccountId())
	if not query then return false end
	local accountName = result.getDataString(query, "name")
	result.free(query)
	print("DEBUG: isGuestAccount - conta=" .. (accountName or "nil"))
	return accountName and string.sub(accountName, 1, 6) == "guest_"
end

local function greetCallback(npc, player)
	print("DEBUG: greetCallback - player=" .. player:getName())
	if player:getName():sub(1, 6) ~= "Guest_" then
		npcHandler:say("Apenas almas convidadas podem falar comigo.", npc, player)
		return false
	end
	if not isGuestAccount(player) then
		npcHandler:say("Você não é um convidado... Algo está errado.", npc, player)
		return false
	end
	tempData[player:getId()] = {}
	npcHandler:setMessage(MESSAGE_GREET, "Bem-vindo ao Salão dos Destinos, viajante. Você deseja {criar} uma nova conta ou {gerenciar} uma existente?")
	return true
end
npcHandler:setCallback(CALLBACK_GREET, greetCallback)

local function creatureSayCallback(npc, player, type, msg)
	print("DEBUG: creatureSayCallback - msg=" .. msg .. " type=" .. type .. " player=" .. player:getName())
	if not npcHandler:checkInteraction(npc, player) then return false end
	if not isGuestAccount(player) then return false end

	local pid = player:getId()
	local topic = npcHandler:getTopic(pid)
	local data = tempData[pid] or {}
	tempData[pid] = data

	print("DEBUG: topic atual=" .. topic)

	-- ========== MENU PRINCIPAL (topic 0) ==========
	if topic == 0 then
		if NpcUtils.correspondeAcao(msg, {"criar", "nova", "criar conta"}) then
			npcHandler:say("Vamos criar sua conta permanente! Primeiro, escolha um nome de conta (3 a 32 caracteres alfanuméricos, sem espaços).", npc, player)
			npcHandler:setTopic(pid, 10)
		elseif NpcUtils.correspondeAcao(msg, {"gerenciar", "existente", "gerenciar conta"}) then
			npcHandler:say("Digite o nome da sua conta e sua senha, separados por um espaço.", npc, player)
			npcHandler:setTopic(pid, 20)
		elseif NpcUtils.correspondeAcao(msg, {"sair", "tchau", "adeus"}) then
			npcHandler:say("Até logo, viajante.", npc, player)
			npcHandler:closeNpc(npc, player)
			tempData[pid] = nil
		end

	-- ========== CRIAÇÃO DE CONTA NOVA (topics 10-13) ==========
	elseif topic == 10 then
		local accountName = msg:match("^%S+$")
		if not accountName or #accountName < 3 or #accountName > 32 then
			npcHandler:say("Nome inválido. Use de 3 a 32 caracteres alfanuméricos, sem espaços.", npc, player)
			return true
		end
		if string.sub(accountName, 1, 6) == "guest_" then
			npcHandler:say("Nome não permitido. Escolha outro.", npc, player)
			return true
		end
		local query = db.storeQuery("SELECT id FROM accounts WHERE name = " .. db.escapeString(accountName))
		if query then
			npcHandler:say("Esse nome de conta já está em uso. Escolha outro.", npc, player)
			result.free(query)
			return true
		end
		data.accountName = accountName
		npcHandler:say("Agora, digite uma senha (mínimo 8 caracteres, com letras e números).", npc, player)
		npcHandler:setTopic(pid, 11)

	elseif topic == 11 then
		local password = msg
		if #password < 8 or not (password:match("%a") and password:match("%d")) then
			npcHandler:say("A senha deve ter ao menos 8 caracteres e conter letras e números.", npc, player)
			return true
		end
		data.password = password
		npcHandler:say("Confirme a senha, digitando novamente.", npc, player)
		npcHandler:setTopic(pid, 12)

	elseif topic == 12 then
		if msg ~= data.password then
			npcHandler:say("As senhas não coincidem. Vamos recomeçar...", npc, player)
			tempData[pid] = {}
			npcHandler:setTopic(pid, 0)
			return true
		end
		local accountName = data.accountName
		local password = data.password

		local insertSuccess = db.query("INSERT INTO accounts (name, password, email) VALUES (" ..
			db.escapeString(accountName) .. ", SHA1(" .. db.escapeString(password) .. "), " ..
			db.escapeString(accountName) .. ")")
		if not insertSuccess then
			npcHandler:say("Erro ao criar a conta. Tente novamente.", npc, player)
			npcHandler:setTopic(pid, 0)
			return true
		end

		local query = db.storeQuery("SELECT id FROM accounts WHERE name = " .. db.escapeString(accountName))
		if not query then
			npcHandler:say("Erro ao recuperar a conta. Contate um administrador.", npc, player)
			npcHandler:setTopic(pid, 0)
			return true
		end
		local accountId = result.getDataInt(query, "id")
		result.free(query)

		player:setStorageValue(90001, accountId)
		data.password = nil
		data.accountName = nil

		npcHandler:say("Conta criada com sucesso! Agora vamos forjar seu primeiro herói. Diga o nome do personagem (3-20 caracteres, sem acentos especiais).", npc, player)
		npcHandler:setTopic(pid, 50)

	-- ========== GERENCIAR CONTA EXISTENTE (topic 20) ==========
	elseif topic == 20 then
		local acc, pass = msg:match("^(%S+)%s+(%S+)$")
		if not acc or not pass then
			npcHandler:say("Formato incorreto. Digite 'nomedaConta senha' (sem as aspas).", npc, player)
			return true
		end
		local query = db.storeQuery("SELECT id FROM accounts WHERE name = " .. db.escapeString(acc) ..
			" AND password = SHA1(" .. db.escapeString(pass) .. ")")
		if not query then
			npcHandler:say("Nome de conta ou senha incorretos.", npc, player)
			npcHandler:setTopic(pid, 0)
			return true
		end
		local accountId = result.getDataInt(query, "id")
		result.free(query)

		player:setStorageValue(90001, accountId)
		npcHandler:say("Autenticado! O que deseja fazer? Você pode: {senha} (alterar senha), {personagem} (gerenciar personagens), {criar} (criar novo personagem) ou {entrar} (jogar com um personagem existente).", npc, player)
		npcHandler:setTopic(pid, 30)

	-- ========== MENU DE GERENCIAMENTO (topic 30) ==========
	elseif topic == 30 then
		local accountId = player:getStorageValue(90001)
		if NpcUtils.correspondeAcao(msg, {"senha", "alterar senha", "trocar senha"}) then
			npcHandler:say("Digite a nova senha (mínimo 8 caracteres, com letras e números).", npc, player)
			npcHandler:setTopic(pid, 40)
		elseif NpcUtils.correspondeAcao(msg, {"personagem", "gerenciar personagem"}) then
			local query = db.storeQuery("SELECT name FROM players WHERE account_id = " .. accountId)
			if not query then
				npcHandler:say("Você não possui personagens nessa conta.", npc, player)
				npcHandler:setTopic(pid, 30)
				return true
			end
			local chars = {}
			repeat
				local charName = result.getDataString(query, "name")
				table.insert(chars, charName)
			until not result.next(query)
			result.free(query)
			local lista = "Seus personagens: " .. table.concat(chars, ", ") .. ". Digite o nome do personagem que deseja gerenciar ou diga {voltar}."
			npcHandler:say(lista, npc, player)
			npcHandler:setTopic(pid, 31)
		elseif NpcUtils.correspondeAcao(msg, {"criar", "criar personagem", "novo personagem"}) then
			npcHandler:say("Vamos criar um novo personagem. Escolha o nome (3-20 caracteres, sem acentos especiais).", npc, player)
			npcHandler:setTopic(pid, 50)
		elseif NpcUtils.correspondeAcao(msg, {"entrar", "jogar", "logar"}) then
			local query = db.storeQuery("SELECT name FROM players WHERE account_id = " .. accountId)
			if not query then
				npcHandler:say("Você não possui personagens para entrar.", npc, player)
				npcHandler:setTopic(pid, 30)
				return true
			end
			local chars = {}
			repeat
				table.insert(chars, result.getDataString(query, "name"))
			until not result.next(query)
			result.free(query)
			npcHandler:say("Qual personagem você deseja usar? " .. table.concat(chars, ", "), npc, player)
			npcHandler:setTopic(pid, 60)
		elseif NpcUtils.correspondeAcao(msg, {"voltar", "cancelar", "sair"}) then
			npcHandler:say("De volta ao menu principal.", npc, player)
			npcHandler:setTopic(pid, 0)
			player:setStorageValue(90001, -1)
			tempData[pid] = {}
		end

	-- ========== ALTERAR SENHA (topic 40) ==========
	elseif topic == 40 then
		local newPass = msg
		if #newPass < 8 or not (newPass:match("%a") and newPass:match("%d")) then
			npcHandler:say("Senha fraca. Tente novamente.", npc, player)
			return true
		end
		local accountId = player:getStorageValue(90001)
		db.asyncQuery("UPDATE accounts SET password = SHA1(" .. db.escapeString(newPass) .. ") WHERE id = " .. accountId)
		npcHandler:say("Senha alterada com sucesso!", npc, player)
		npcHandler:setTopic(pid, 30)

	-- ========== SELEÇÃO DE PERSONAGEM PARA GERENCIAR (topic 31) ==========
	elseif topic == 31 then
		if NpcUtils.correspondeAcao(msg, {"voltar", "cancelar"}) then
			npcHandler:say("Retornando ao menu de gerenciamento.", npc, player)
			npcHandler:setTopic(pid, 30)
			return true
		end
		local accountId = player:getStorageValue(90001)
		local charName = msg:match("^%S+$")  -- sem espaços
		if not charName then
			npcHandler:say("Digite um nome válido.", npc, player)
			return true
		end
		local query = db.storeQuery("SELECT name FROM players WHERE name = " .. db.escapeString(charName) .. " AND account_id = " .. accountId)
		if not query then
			npcHandler:say("Personagem não encontrado na sua conta.", npc, player)
			return true
		end
		result.free(query)
		-- Segurança: impede gerenciar personagens convidados (Guest_)
		if string.sub(charName, 1, 6) == "Guest_" then
			npcHandler:say("Você não pode gerenciar personagens convidados.", npc, player)
			return true
		end
		data.selectedChar = charName
		npcHandler:say("Personagem \"" .. charName .. "\" selecionado. O que deseja fazer? {apagar} ou {alterar}?", npc, player)
		npcHandler:setTopic(pid, 32)

	-- ========== ESCOLHA ENTRE APAGAR OU ALTERAR (topic 32) ==========
	elseif topic == 32 then
		if NpcUtils.correspondeAcao(msg, {"apagar", "deletar", "excluir"}) then
			data.action = "delete"
			npcHandler:say("Tem certeza que deseja apagar " .. data.selectedChar .. " permanentemente? Digite {sim} para confirmar ou {não} para cancelar.", npc, player)
			npcHandler:setTopic(pid, 33)
		elseif NpcUtils.correspondeAcao(msg, {"alterar", "modificar", "mudar"}) then
			data.action = "alter"
			npcHandler:say("O que deseja alterar em " .. data.selectedChar .. "? {nome} ou {sexo}?", npc, player)
			npcHandler:setTopic(pid, 70)
		else
			npcHandler:say("Opção inválida. Escolha {apagar} ou {alterar}.", npc, player)
		end

	-- ========== CONFIRMAÇÃO DE DELEÇÃO (topic 33) ==========
	elseif topic == 33 then
		if data.action ~= "delete" then
			npcHandler:say("Erro interno. Retornando ao menu.", npc, player)
			npcHandler:setTopic(pid, 30)
			return true
		end
		if NpcUtils.correspondeAcao(msg, {"sim"}) then
			db.asyncQuery("DELETE FROM players WHERE name = " .. db.escapeString(data.selectedChar))
			npcHandler:say("Personagem apagado permanentemente.", npc, player)
		else
			npcHandler:say("Operação cancelada.", npc, player)
		end
		data.selectedChar = nil
		data.action = nil
		npcHandler:setTopic(pid, 30)

	-- ========== ALTERAÇÃO DE PERSONAGEM (topics 70, 71, 72) ==========
	elseif topic == 70 then
		if NpcUtils.correspondeAcao(msg, {"nome"}) then
			npcHandler:say("Digite o novo nome para " .. data.selectedChar .. " (3-20 caracteres, sem acentos especiais).", npc, player)
			npcHandler:setTopic(pid, 71)
		elseif NpcUtils.correspondeAcao(msg, {"sexo"}) then
			npcHandler:say("Escolha o novo sexo para " .. data.selectedChar .. ": {masculino} ou {feminino}.", npc, player)
			npcHandler:setTopic(pid, 72)
		else
			npcHandler:say("Opção inválida. Escolha {nome} ou {sexo}.", npc, player)
		end

	elseif topic == 71 then
		local newName = msg:match("^%S+$")
		if not newName or #newName < 3 or #newName > 20 then
			npcHandler:say("Nome inválido. Use de 3 a 20 caracteres alfanuméricos, sem espaços.", npc, player)
			return true
		end
		if not newName:match("^[a-zA-Z0-9áéíóúàâêôç ]+$") then
			npcHandler:say("Nome contém caracteres inválidos. Evite acentos como ã, õ.", npc, player)
			return true
		end
		-- Verificar se já existe
		local query = db.storeQuery("SELECT name FROM players WHERE name = " .. db.escapeString(newName))
		if query then
			npcHandler:say("Esse nome já está em uso. Escolha outro.", npc, player)
			result.free(query)
			return true
		end
		db.asyncQuery("UPDATE players SET name = " .. db.escapeString(newName) .. " WHERE name = " .. db.escapeString(data.selectedChar))
		npcHandler:say("Nome alterado para " .. newName .. ".", npc, player)
		data.selectedChar = nil
		npcHandler:setTopic(pid, 30)

	elseif topic == 72 then
		local sex = nil
		local looktype = nil
		if NpcUtils.correspondeAcao(msg, {"masculino", "homem", "male"}) then
			sex = 1
			looktype = 128
		elseif NpcUtils.correspondeAcao(msg, {"feminino", "mulher", "female"}) then
			sex = 0
			looktype = 136
		else
			npcHandler:say("Opção inválida. Digite {masculino} ou {feminino}.", npc, player)
			return true
		end
		db.asyncQuery("UPDATE players SET sex = " .. sex .. ", looktype = " .. looktype .. " WHERE name = " .. db.escapeString(data.selectedChar))
		npcHandler:say("Sexo alterado e visual atualizado para " .. (sex == 1 and "masculino" or "feminino") .. ".", npc, player)
		data.selectedChar = nil
		npcHandler:setTopic(pid, 30)

	-- ========== CRIAÇÃO DE PERSONAGEM (topics 50-52) ==========
	elseif topic == 50 then
		local nome = msg
		if not nome or #nome < 3 or #nome > 20 then
			npcHandler:say("O nome deve ter entre 3 e 20 caracteres.", npc, player)
			return true
		end
		if not nome:match("^[a-zA-Z0-9áéíóúàâêôç ]+$") then
			npcHandler:say("Nome contém caracteres inválidos. Evite acentos como ã, õ. Use apenas os permitidos.", npc, player)
			return true
		end
		local query = db.storeQuery("SELECT name FROM players WHERE name = " .. db.escapeString(nome))
		if query then
			npcHandler:say("Esse nome de personagem já existe. Escolha outro.", npc, player)
			result.free(query)
			return true
		end
		data.charName = nome
		npcHandler:say("Seu herói será {masculino} ou {feminino}?", npc, player)
		npcHandler:setTopic(pid, 51)

	elseif topic == 51 then
		local sex = nil
		if NpcUtils.correspondeAcao(msg, {"masculino", "homem", "male"}) then
			sex = 1
		elseif NpcUtils.correspondeAcao(msg, {"feminino", "mulher", "female"}) then
			sex = 0
		else
			npcHandler:say("Opção inválida. Digite {masculino} ou {feminino}.", npc, player)
			return true
		end
		data.sex = sex
		npcHandler:say({
			"As vocações disponíveis são:",
			"{Guerreiro} ? mestre da espada.",
			"{Arqueiro} ? mestre dos arcos.",
			"{Mago} ? mestre dos elementos.",
			"{Druida} ? mestre da natureza."
		}, npc, player, 4000)
		npcHandler:setTopic(pid, 52)

	elseif topic == 52 then
		local voc = nil
		if NpcUtils.correspondeAcao(msg, {"guerreiro", "knight", "warrior", "cavaleiro"}) then
			voc = 1
		elseif NpcUtils.correspondeAcao(msg, {"arqueiro", "paladin", "archer", "ranger"}) then
			voc = 2
		elseif NpcUtils.correspondeAcao(msg, {"mago", "sorcerer", "feiticeiro", "magic"}) then
			voc = 3
		elseif NpcUtils.correspondeAcao(msg, {"druida", "druid"}) then
			voc = 4
		else
			npcHandler:say("Escolha uma vocação válida: {guerreiro}, {arqueiro}, {mago} ou {druida}.", npc, player)
			return true
		end

		local nome = data.charName
		local sex = data.sex
		local accountId = player:getStorageValue(90001)
		local looktype = (sex == 1) and 128 or 136

		-- Timestamp atual para marcar que o personagem "já logou" e evitar o script de first items
		local nowTimestamp = os.time()

		local success = db.query(
			"INSERT INTO players (name, account_id, level, vocation, sex, posx, posy, posz, town_id, " ..
			"health, healthmax, mana, manamax, looktype, lookhead, lookbody, looklegs, lookfeet, lookaddons, " ..
			"cap, lastlogin, lastip) " ..
			"VALUES (" .. db.escapeString(nome) .. ", " .. accountId .. ", 1, " .. voc .. ", " .. sex .. ", " ..
			"666, 666, 15, 1, " ..
			"100, 100, 0, 0, " ..
			looktype .. ", 0, 0, 0, 0, 0, " ..
			"400, " .. nowTimestamp .. ", 0)"
		)
		if not success then
			npcHandler:say("Erro ao criar o personagem. Tente novamente.", npc, player)
			npcHandler:setTopic(pid, 0)
			return true
		end

		npcHandler:say("Parabéns! " .. nome .. " foi criado com sucesso. Agora você pode sair e fazer login com sua conta permanente para jogar com seu personagem.", npc, player)
		data.charName = nil
		data.sex = nil
		npcHandler:setTopic(pid, 0)

	-- ========== ENTRAR COM PERSONAGEM EXISTENTE (topic 60) ==========
	elseif topic == 60 then
		npcHandler:say("Por enquanto, você deve sair e fazer login manualmente com sua conta permanente para entrar com o personagem. Esse recurso será automatizado em breve.", npc, player)
		npcHandler:setTopic(pid, 0)

	else
		print("DEBUG: tópico desconhecido:" .. topic)
	end

	return true
end
npcHandler:setCallback(CALLBACK_MESSAGE_DEFAULT, creatureSayCallback)

npcHandler:setMessage(MESSAGE_FAREWELL, "Que os ventos lhe guiem, viajante.")
npcHandler:setMessage(MESSAGE_WALKAWAY, "O viajante se afastou sem concluir seu destino.")
npcHandler:addModule(FocusModule:new(), npcConfig.name, true, true, true)

npcType:register(npcConfig)