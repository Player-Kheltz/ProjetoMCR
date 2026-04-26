EnterGame = {}

-- Tabela de mensagens de erro em português (ISO-8859-1)
local ERROR_MESSAGES = {
    account_name_taken = "O nome de conta já está em uso.",
    password_too_weak = "A senha deve ter 8+ caracteres com letras e números.",
    invalid_fields = "Preencha todos os campos corretamente.",
    invalid_credentials = "Nome de conta ou senha incorretos.",
    registration_success = "Conta criada com sucesso!"
}

-- private variables
local loadBox
local enterGame
local motdWindow
local enterGameButton
local clientBox
local protocolLogin
local motdEnabled = true
local isGuestSession = false

-- private functions
local function onError(protocol, message, errorCode)
    if loadBox then
        loadBox:destroy()
        loadBox = nil
    end

    if not errorCode then
        EnterGame.clearAccountFields()
    end

    local errorBox = displayErrorBox(tr('Login Error'), message)
    connect(errorBox, {
        onOk = EnterGame.show
    })
end

local function onMotd(protocol, motd)
    G.motdNumber = tonumber(motd:sub(0, motd:find('\n')))
    G.motdMessage = motd:sub(motd:find('\n') + 1, #motd)
end

local function onSessionKey(protocol, sessionKey)
    G.sessionKey = sessionKey
end

local function onCharacterList(protocol, characters, account, otui)
    local httpLogin = enterGame:getChildById('httpLoginBox'):isChecked()

    -- Try add server to the server list
    ServerList.add(G.host, G.port, g_game.getClientVersion(), httpLogin)

    -- Save 'Stay logged in' setting
    g_settings.set('staylogged', enterGame:getChildById('stayLoggedBox'):isChecked())
    g_settings.set('httpLogin', httpLogin)

    if enterGame:getChildById('rememberEmailBox'):isChecked() then
        local account = g_crypt.encrypt(G.account)
        local password = g_crypt.encrypt(G.password)

        g_settings.set('account', account)
        g_settings.set('password', password)

        ServerList.setServerAccount(G.host, account)
        ServerList.setServerPassword(G.host, password)

        g_settings.set('autologin', enterGame:getChildById('autoLoginBox'):isChecked())
    else
        -- reset server list account/password
        ServerList.setServerAccount(G.host, '')
        ServerList.setServerPassword(G.host, '')

        EnterGame.clearAccountFields()
    end

    if loadBox then
        loadBox:destroy()
        loadBox = nil
    end

    for _, characterInfo in pairs(characters) do
        if characterInfo.previewState and characterInfo.previewState ~= PreviewState.Default then
            characterInfo.worldName = characterInfo.worldName .. ', Preview'
        end
    end

    CharacterList.create(characters, account, otui)
    CharacterList.show()

    if motdEnabled then
        local lastMotdNumber = g_settings.getNumber('motd')
        if G.motdNumber and G.motdNumber ~= lastMotdNumber then
            g_settings.set('motd', G.motdNumber)
            motdWindow = displayInfoBox(tr('Message of the day'), G.motdMessage)
            connect(motdWindow, {
                onOk = function()
                    CharacterList.show()
                    motdWindow = nil
                end
            })
            CharacterList.hide()
        end
    end
end

local function onUpdateNeeded(protocol, signature)
    if loadBox then
        loadBox:destroy()
        loadBox = nil
    end

    if EnterGame.updateFunc then
        local continueFunc = EnterGame.show
        local cancelFunc = EnterGame.show
        EnterGame.updateFunc(signature, continueFunc, cancelFunc)
    else
        local errorBox = displayErrorBox(tr('Update needed'), tr('Your client needs updating, try redownloading it.'))
        connect(errorBox, {
            onOk = EnterGame.show
        })
    end
end

local function updateLabelText()
    if enterGame:getChildById('clientComboBox') and tonumber(enterGame:getChildById('clientComboBox'):getText()) > 1080 then
        enterGame:setText("Projeto MCR")
        enterGame:getChildById('emailLabel'):setText("Email:")
        enterGame:getChildById('rememberEmailBox'):setText("Remember Email:")
    else
        enterGame:setText("Enter Game")
        enterGame:getChildById('emailLabel'):setText("Conta:")
        enterGame:getChildById('rememberEmailBox'):setText("Lembrar Conta")
    end
end

-- =====================================================
-- NOVA FUNÇÃO: openSalaoDestinos (chamada pelo botão)
-- =====================================================
function EnterGame.openSalaoDestinos()
    EnterGame.clearCharacterList()   -- remove qualquer lista anterior
    EnterGame.hide()  -- esconde a janela de login
    local host = enterGame:getChildById('serverHostTextEdit'):getText()
    local port = tonumber(enterGame:getChildById('serverPortTextEdit'):getText())
    if not host or host == '' or not port then
        displayErrorBox(tr('Erro'), 'Configure o servidor primeiro.')
        return
    end

    isGuestSession = true
    EnterGame.clearCharacterList()  -- garante que nenhuma lista antiga interfira

    local guestLoginUrl = "http://" .. host .. ":" .. tostring(port) .. "/guest_login"
    print(">>> [DEBUG] Solicitando conta guest: " .. guestLoginUrl)

    HTTP.get(guestLoginUrl, function(response, err)
        if err then
            displayErrorBox(tr('Erro'), 'Falha ao conectar ao Salão dos Destinos.')
            return
        end

        local success, data = pcall(json.decode, response)
        if not success or not data or data.status ~= "success" then
            displayErrorBox(tr('Erro'), 'Não foi possível obter uma conta convidada.')
            return
        end

        print(">>> [DEBUG] Guest account obtida: " .. data.account)
        EnterGame.doAutoLogin(data.account, data.password, data.character)
    end)
end

-- =====================================================
-- NOVA FUNÇÃO: doAutoLogin(account, password, character)
-- =====================================================
function EnterGame.doAutoLogin(account, password, character)
    isGuestSession = true
    local host = enterGame:getChildById('serverHostTextEdit'):getText()
    local port = tonumber(enterGame:getChildById('serverPortTextEdit'):getText())

    G.account = account
    G.password = password
    G.host = host
    G.port = port
    G.authenticatorToken = ''

    local clientVersion = tonumber(clientBox:getText())
    g_game.setClientVersion(clientVersion)
    g_game.setProtocolVersion(g_game.getClientProtocolVersion(clientVersion))
    g_game.chooseRsa(G.host)

    local payload = json.encode({
        email = account,
        password = password,
        type = "login"
    })

    local loginUrl = "http://" .. host .. ":" .. tostring(port) .. "/login"
    print(">>> [DEBUG] Auto-login: " .. loginUrl)

    HTTP.post(loginUrl, payload, function(response, err)
        if err then
            displayErrorBox(tr('Erro'), 'Falha na conexão com o servidor de login.')
            return
        end

        local success, result = pcall(json.decode, response)
        if not success then
            displayErrorBox(tr('Erro'), 'Resposta inválida do servidor.')
            return
        end

        if result.errorCode and result.errorCode ~= 0 then
            local msg = ERROR_MESSAGES[result.error_code] or result.errorMessage or "Erro desconhecido."
            displayErrorBox(tr('Erro'), msg)
            return
        end

        local session = result.session
        local playData = result.playdata

        if not session or not playData then
            displayErrorBox(tr('Erro'), 'Resposta incompleta do servidor.')
            return
        end

        G.sessionKey = session.sessionkey

        -- Monta a lista de personagens (apenas para achar o alvo)
        local characters = {}
        if playData.characters then
            for _, char in ipairs(playData.characters) do
                local world = nil
                if playData.worlds then
                    for _, w in ipairs(playData.worlds) do
                        if w.id == char.worldid then
                            world = w
                            break
                        end
                    end
                end
                characters[#characters + 1] = {
                    name = char.name,
                    worldName = world and world.name or "Unknown",
                    worldIp = world and (world.externaladdressprotected or world.ip) or "127.0.0.1",
                    worldPort = world and (world.externalportprotected or world.port) or 7173
                }
            end
        end

        -- Encontra o personagem convidado
        local targetChar = nil
        for _, char in ipairs(characters) do
            if char.name == character then
                targetChar = char
                break
            end
        end

        if not targetChar then
            displayErrorBox(tr('Erro'), 'Personagem convidado não encontrado.')
            return
        end

        -- Conecta diretamente ao servidor de jogo
        g_game.loginWorld(
            G.account,
            G.password,
            targetChar.worldName,
            targetChar.worldIp,
            targetChar.worldPort,
            targetChar.name,
            G.authenticatorToken,
            G.sessionKey
        )

        loadBox = displayCancelBox(tr('Please wait'), tr('Conectando ao servidor de jogo...'))
        connect(loadBox, {
            onCancel = function()
                loadBox = nil
                g_game.cancelLogin()
                EnterGame.show()
            end
        })
    end)
end

-- =====================================================
-- LISTENER DO OPCODE 200 (MIGRAÇÃO FUTURA)
-- =====================================================
ProtocolGame.registerExtendedOpcode(200, function(protocol, opcode, buffer)
    if not buffer then return end
    local status, data = pcall(json.decode, buffer)
    if not status then return end

    if data.account and data.password then
        g_game.logout(false)
        scheduleEvent(function()
            EnterGame.doAutoLogin(data.account, data.password, data.character)
        end, 100)
    end
end)

-- (Restante das funções originais do EnterGame permanecem inalteradas)

-- public functions
function EnterGame.init()
    enterGame = g_ui.displayUI('entergame')
    Keybind.new("Misc.", "Change Character", "Ctrl+G", "")
    Keybind.bind("Misc.", "Change Character", {
      {
        type = KEY_DOWN,
        callback = EnterGame.openWindow,
      }
    })

    local account = g_settings.get('account')
    local password = g_settings.get('password')
    local host = g_settings.get('host')
    local port = g_settings.get('port')
    local stayLogged = g_settings.getBoolean('staylogged')
    local autologin = g_settings.getBoolean('autologin')
    local httpLogin = g_settings.getBoolean('httpLogin')
    local clientVersion = g_settings.getInteger('client-version')

    if not clientVersion or clientVersion == 0 then
        clientVersion = 1500   -- Projeto MCR usa protocolo 15.00
    end

    if not port or port == 0 then
        port = 8080            -- Porta padrão do Login Server
    end

    EnterGame.setAccountName(account)
    EnterGame.setPassword(password)

    enterGame:getChildById('serverHostTextEdit'):setText(host)
    enterGame:getChildById('serverPortTextEdit'):setText(port)
    enterGame:getChildById('autoLoginBox'):setChecked(autologin)
    enterGame:getChildById('stayLoggedBox'):setChecked(stayLogged)
    enterGame:getChildById('httpLoginBox'):setChecked(httpLogin)

    local installedClients = {}
    local amountInstalledClients = 0
    for _, dirItem in ipairs(g_resources.listDirectoryFiles('/data/things/')) do
        if tonumber(dirItem) then
            installedClients[dirItem] = true
            amountInstalledClients = amountInstalledClients + 1
        end
    end

    clientBox = enterGame:getChildById('clientComboBox')

    for _, proto in pairs(g_game.getSupportedClients()) do
        local protoStr = tostring(proto)
        if installedClients[protoStr] or amountInstalledClients == 0 then
            installedClients[protoStr] = nil
            clientBox:addOption(proto)
        end
    end

    for protoStr, status in pairs(installedClients) do
        if status then
            print(string.format('Warning: %s recognized as an installed client, but not supported.', protoStr))
        end
    end

    clientBox:setCurrentOption(clientVersion)

    connect(clientBox, {
        onOptionChange = EnterGame.onClientVersionChange
    })

    if Servers_init then
        if table.size(Servers_init) == 1 then
            local hostInit, valuesInit = next(Servers_init)
            EnterGame.setUniqueServer(hostInit, valuesInit.port, valuesInit.protocol)
            EnterGame.setHttpLogin(valuesInit.httpLogin)
        elseif not host or host == "" then
            local hostInit, valuesInit = next(Servers_init)
            EnterGame.setDefaultServer(hostInit, valuesInit.port, valuesInit.protocol)
            EnterGame.setHttpLogin(valuesInit.httpLogin)
        end
    else
        EnterGame.toggleAuthenticatorToken(clientVersion, true)
        EnterGame.toggleStayLoggedBox(clientVersion, true)
    end

    updateLabelText()


    connect(g_game, {
        onGameStart = EnterGame.hidePanels
    })

    if g_app.isRunning() and not g_game.isOnline() then
        enterGame:show()
    end
end

-- public functions
function EnterGame.init()
    enterGame = g_ui.displayUI('entergame')
    Keybind.new("Misc.", "Change Character", "Ctrl+G", "")
    Keybind.bind("Misc.", "Change Character", {
      {
        type = KEY_DOWN,
        callback = EnterGame.openWindow,
      }
    })

    local account = g_settings.get('account')
    local password = g_settings.get('password')
    local host = g_settings.get('host')
    local port = g_settings.get('port')
    local stayLogged = g_settings.getBoolean('staylogged')
    local autologin = g_settings.getBoolean('autologin')
    local httpLogin = g_settings.getBoolean('httpLogin')
    local clientVersion = g_settings.getInteger('client-version')

    if not clientVersion or clientVersion == 0 then
        clientVersion = 1500   -- Projeto MCR usa protocolo 15.00
    end

    if not port or port == 0 then
        port = 8080            -- Porta padr?o do Login Server
    end

    EnterGame.setAccountName(account)
    EnterGame.setPassword(password)

    enterGame:getChildById('serverHostTextEdit'):setText(host)
    enterGame:getChildById('serverPortTextEdit'):setText(port)
    enterGame:getChildById('autoLoginBox'):setChecked(autologin)
    enterGame:getChildById('stayLoggedBox'):setChecked(stayLogged)
    enterGame:getChildById('httpLoginBox'):setChecked(httpLogin)

    local installedClients = {}
    local amountInstalledClients = 0
    for _, dirItem in ipairs(g_resources.listDirectoryFiles('/data/things/')) do
        if tonumber(dirItem) then
            installedClients[dirItem] = true
            amountInstalledClients = amountInstalledClients + 1
        end
    end

    clientBox = enterGame:getChildById('clientComboBox')

    for _, proto in pairs(g_game.getSupportedClients()) do
        local protoStr = tostring(proto)
        if installedClients[protoStr] or amountInstalledClients == 0 then
            installedClients[protoStr] = nil
            clientBox:addOption(proto)
        end
    end

    for protoStr, status in pairs(installedClients) do
        if status then
            print(string.format('Warning: %s recognized as an installed client, but not supported.', protoStr))
        end
    end

    clientBox:setCurrentOption(clientVersion)

    connect(clientBox, {
        onOptionChange = EnterGame.onClientVersionChange
    })

    if Servers_init then
        if table.size(Servers_init) == 1 then
            local hostInit, valuesInit = next(Servers_init)
            EnterGame.setUniqueServer(hostInit, valuesInit.port, valuesInit.protocol)
            EnterGame.setHttpLogin(valuesInit.httpLogin)
        elseif not host or host == "" then
            local hostInit, valuesInit = next(Servers_init)
            EnterGame.setDefaultServer(hostInit, valuesInit.port, valuesInit.protocol)
            EnterGame.setHttpLogin(valuesInit.httpLogin)
        end
    else
        EnterGame.toggleAuthenticatorToken(clientVersion, true)
        EnterGame.toggleStayLoggedBox(clientVersion, true)
    end

    updateLabelText()

    enterGame:hide()

    connect(g_game, {
        onGameStart = EnterGame.hidePanels
    })

    connect(g_game, {
        onGameEnd = EnterGame.showPanels
    })

    if g_app.isRunning() and not g_game.isOnline() then
        enterGame:show()
    end
end

function EnterGame.hidePanels()
    if loadBox then
        loadBox:destroy()
        loadBox = nil
    end
    if g_modules.getModule("client_bottommenu"):isLoaded() then
        modules.client_bottommenu.hide()
    end
    modules.client_topmenu.hide()
    EnterGame.hide()   -- esconde a janela de login quando o jogo começa
end

function EnterGame.showPanels()
    if g_modules.getModule("client_bottommenu"):isLoaded() then
        modules.client_bottommenu.show()
    end
    modules.client_topmenu.show()

    if not g_game.isOnline() then
        if isGuestSession then
            EnterGame.clearCharacterList()
            isGuestSession = false
            EnterGame.show()
        else
            -- Conta normal: só mostra login se a lista não estiver visível
            if not CharacterList.isVisible() then
                EnterGame.show()
            end
        end
    end
end

function EnterGame.clearCharacterList()
    pcall(CharacterList.destroy)   -- ignora erro se a janela não existir
    G.characters = nil
    G.characterAccount = nil
end

function EnterGame.firstShow()
    EnterGame.show()

    local account = g_crypt.decrypt(g_settings.get('account'))
    local password = g_crypt.decrypt(g_settings.get('password'))
    local host = g_settings.get('host')
    local autologin = g_settings.getBoolean('autologin')
    if #host > 0 and #password > 0 and #account > 0 and autologin then
        addEvent(function()
            if not g_settings.getBoolean('autologin') then
                return
            end
            EnterGame.doLogin()
        end)
    end

    if Services and Services.status then
        if g_modules.getModule("client_bottommenu"):isLoaded()  then
            EnterGame.postCacheInfo()
            EnterGame.postEventScheduler()
            -- EnterGame.postShowOff()
            EnterGame.postShowCreatureBoost()
        end
    end
end

function EnterGame.terminate()
    Keybind.delete("Misc.", "Change Character")

    disconnect(clientBox, {
        onOptionChange = EnterGame.onClientVersionChange
    })
    disconnect(g_game, {
        onGameStart = EnterGame.hidePanels
    })
    disconnect(g_game, {
        onGameEnd = EnterGame.showPanels
    })

    if enterGame then
        enterGame:destroy()
        enterGame = nil
    end

    if clientBox then
        clientBox = nil
    end

    if motdWindow then
        motdWindow:destroy()
        motdWindow = nil
    end

    if loadBox then
        loadBox:destroy()
        loadBox = nil
    end

    if protocolLogin then
        protocolLogin:cancelLogin()
        protocolLogin = nil
    end

    EnterGame = nil
end

local function reportRequestWarning(requestType, msg, errorCode)
    g_logger.warning(("[Webscraping - %s] %s"):format(requestType, msg), errorCode)
end

function EnterGame.postCacheInfo()
    local requestType = 'cacheinfo'

    local onRecvInfo = function(message, err)
        if not enterGame then return end
        if err then
            reportRequestWarning(requestType, "Bad Request. Game_entergame postCacheInfo1")
            return
        end
        local jsonString = message:match("{.*}")
        if not jsonString then
            reportRequestWarning(requestType, "Invalid JSON response format")
            return
        end
        local success, response = pcall(function() return json.decode(jsonString) end)
        if not success or not response then
            reportRequestWarning(requestType, "Failed to parse JSON response")
            return
        end
        if response.errorMessage then
            reportRequestWarning(requestType, response.errorMessage, response.errorCode)
            return
        end
        if not modules or not modules.client_topmenu then return end
        modules.client_topmenu.setPlayersOnline(response.playersonline)
        modules.client_topmenu.setDiscordStreams(response.discord_online)
        modules.client_topmenu.setYoutubeStreams(response.gamingyoutubestreams)
        modules.client_topmenu.setYoutubeViewers(response.gamingyoutubeviewer)
        modules.client_topmenu.setLinkYoutube(response.youtube_link)
        modules.client_topmenu.setLinkDiscord(response.discord_link)
    end

    HTTP.post(Services.status, json.encode({ type = requestType }), onRecvInfo, false)
end

function EnterGame.postEventScheduler()
    local requestType = 'eventschedule'
    local onRecvInfo = function(message, err)
        if err then
            reportRequestWarning(requestType, "Bad Request.Game_entergame postEventScheduler1")
            return
        end
        local jsonString = message:match("{.*}")
        if not jsonString then
            reportRequestWarning(requestType, "Invalid JSON response format")
            return
        end
        local success, response = pcall(function() return json.decode(jsonString) end)
        if not success or not response then
            reportRequestWarning(requestType, "Failed to parse JSON response")
            return
        end
        if response.errorMessage then
            reportRequestWarning(requestType, response.errorMessage, response.errorCode)
            return
        end
        modules.client_bottommenu.setEventsSchedulerTimestamp(response.lastupdatetimestamp)
        modules.client_bottommenu.setEventsSchedulerCalender(response.eventlist)
    end

    HTTP.post(Services.status, json.encode({ type = requestType }), onRecvInfo, false)
end

function EnterGame.postShowOff()
    local requestType = 'showoff'
    local onRecvInfo = function(message, err)
        if err then
            reportRequestWarning(requestType, "Bad Request.Game_entergame postShowOff")
            return
        end
        local jsonString = message:match("{.*}")
        if not jsonString then
            reportRequestWarning(requestType, "Invalid JSON response format")
            return
        end
        local success, response = pcall(function() return json.decode(jsonString) end)
        if not success or not response then
            reportRequestWarning(requestType, "Failed to parse JSON response")
            return
        end
        if response.errorMessage then
            reportRequestWarning(requestType, response.errorMessage, response.errorCode)
            return
        end
        modules.client_bottommenu.setShowOffData(response)
    end

    HTTP.post(Services.status, json.encode({ type = requestType }), onRecvInfo, false)
end

function EnterGame.postShowCreatureBoost()
    local requestType = 'boostedcreature'
    local onRecvInfo = function(message, err)
        if err then
            reportRequestWarning(requestType, "Bad Request.Game_entergame postShowCreatureBoost1")
            return
        end
        local jsonString = message:match("{.*}")
        if not jsonString then
            reportRequestWarning(requestType, "Invalid JSON response format")
            return
        end
        local success, response = pcall(function() return json.decode(jsonString) end)
        if not success or not response then
            reportRequestWarning(requestType, "Failed to parse JSON response")
            return
        end
        if response.errorMessage then
            reportRequestWarning(requestType, response.errorMessage, response.errorCode)
            return
        end
        modules.client_bottommenu.setBoostedCreatureAndBoss(response)
    end

    HTTP.post(Services.status, json.encode({ type = requestType }), onRecvInfo, false)
end

function EnterGame.show()
    if g_game.isOnline() or CharacterList.isVisible() then
        return
    end
    if loadBox then
        return
    end
    enterGame:show()
    enterGame:raise()
    enterGame:focus()
end

function EnterGame.hide()
    enterGame:hide()
end

function EnterGame.openWindow()
    if g_game.isOnline() then
        CharacterList.show()
    elseif not g_game.isLogging() and not CharacterList.isVisible() then
        EnterGame.show()
    end
end

function EnterGame.setAccountName(account)
    local account = g_crypt.decrypt(account)
    enterGame:getChildById('accountNameTextEdit'):setText(account)
    enterGame:getChildById('accountNameTextEdit'):setCursorPos(-1)
    enterGame:getChildById('rememberEmailBox'):setChecked(#account > 0)
end

function EnterGame.setPassword(password)
    local password = g_crypt.decrypt(password)
    enterGame:getChildById('accountPasswordTextEdit'):setText(password)
end

function EnterGame.setHttpLogin(httpLogin)
    if type(httpLogin) == "boolean" then
        enterGame:getChildById('httpLoginBox'):setChecked(httpLogin)
    else
        enterGame:getChildById('httpLoginBox'):setChecked(#httpLogin > 0)
    end
end

function EnterGame.clearAccountFields()
    enterGame:getChildById('accountNameTextEdit'):clearText()
    enterGame:getChildById('accountPasswordTextEdit'):clearText()
    enterGame:getChildById('authenticatorTokenTextEdit'):clearText()
    enterGame:getChildById('accountNameTextEdit'):focus()
    g_settings.remove('account')
    g_settings.remove('password')
end

function EnterGame.toggleAuthenticatorToken(clientVersion, init)
    if not enterGame.disableToken then return end
    local enabled = (clientVersion >= 1072)
    if enabled == enterGame.authenticatorEnabled then return end
    enterGame:getChildById('authenticatorTokenLabel'):setOn(enabled)
    enterGame:getChildById('authenticatorTokenTextEdit'):setOn(enabled)
    local newHeight = enterGame:getHeight()
    local newY = enterGame:getY()
    if enabled then
        newY = newY - enterGame.authenticatorHeight
        newHeight = newHeight + enterGame.authenticatorHeight
    else
        newY = newY + enterGame.authenticatorHeight
        newHeight = newHeight - enterGame.authenticatorHeight
    end
    if not init then
        enterGame:breakAnchors()
        enterGame:setY(newY)
        enterGame:bindRectToParent()
    end
    enterGame:setHeight(newHeight)
    enterGame.authenticatorEnabled = enabled
end

function EnterGame.toggleStayLoggedBox(clientVersion, init)
    if not enterGame.disableToken then return end
    local enabled = (clientVersion >= 1074)
    if enabled == enterGame.stayLoggedBoxEnabled then return end
    enterGame:getChildById('stayLoggedBox'):setOn(enabled)
    local newHeight = enterGame:getHeight()
    local newY = enterGame:getY()
    if enabled then
        newY = newY - enterGame.stayLoggedBoxHeight
        newHeight = newHeight + enterGame.stayLoggedBoxHeight
    else
        newY = newY + enterGame.stayLoggedBoxHeight
        newHeight = newHeight - enterGame.stayLoggedBoxHeight
    end
    if not init then
        enterGame:breakAnchors()
        enterGame:setY(newY)
        enterGame:bindRectToParent()
    end
    enterGame:setHeight(newHeight)
    enterGame.stayLoggedBoxEnabled = enabled
end

function EnterGame.onClientVersionChange(comboBox, text, data)
    local clientVersion = tonumber(text)
    EnterGame.toggleAuthenticatorToken(clientVersion)
    EnterGame.toggleStayLoggedBox(clientVersion)
    updateLabelText()
end

function EnterGame.tryHttpLogin(clientVersion, httpLogin)
    -- Fun??o mantida apenas para compatibilidade, mas N?O deve ser chamada no Projeto MCR.
    -- O fluxo correto usa ProtocolLogin com httpLogin=true.
    g_game.setClientVersion(clientVersion)
    g_game.setProtocolVersion(g_game.getClientProtocolVersion(clientVersion))
    g_game.chooseRsa(G.host)
    if not modules.game_things.isLoaded() then
        if loadBox then
            loadBox:destroy()
            loadBox = nil
        end
        local errorBox = displayErrorBox(tr("Login Error"), string.format("Things are not loaded, please put assets in things/%d/<assets>.", clientVersion))
        connect(errorBox, { onOk = EnterGame.show })
        return
    end
    local host, path = G.host:match("([^/]+)/([^/].*)")
    local url = G.host
    if not G.port then
        local isHttps, _ = string.find(host, "https")
        if not isHttps then
            G.port = 443
        else
            G.port = 80
        end
    end
    if not path then path = "" else path = '/' .. path end
    if not host then
        loadBox = displayCancelBox(tr('Please wait'), tr('ERROR , try adding \n- ip/login.php \n- Enable HTTP login'))
    else
        loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to login server...\nServer: [%s]', host .. ":" .. tostring(G.port) .. path))
    end
    connect(loadBox, {
        onCancel = function(msgbox)
            loadBox = nil
            G.requestId = 0
            EnterGame.show()
        end
    })
    math.randomseed(os.time())
    G.requestId = math.random(1)
    local http = LoginHttp.create()
    http:httpLogin(host, path, G.port, G.account, G.password, G.requestId, httpLogin)
    connect(loadBox, {
        onCancel = function(msgbox)
            loadBox = nil
            G.requestId = 0
            if http and http.cancel then http:cancel() end
            EnterGame.show()
        end
    })
end

function EnterGame.loginSuccess(requestId, jsonSession, jsonWorlds, jsonCharacters)
    if G.requestId ~= requestId then return end
    local worlds = {}
    for _, world in ipairs(json.decode(jsonWorlds)) do
        worlds[world.id] = {
            name = world.name,
            ip = world.externaladdressprotected,
            port = world.externalportprotected,
            previewState = world.previewstate == 1
        }
    end
    local characters = {}
    for index, character in ipairs(json.decode(jsonCharacters)) do
        local world = worlds[character.worldid]
        characters[index] = {
            name = character.name,
            level = character.level,
            main = character.ismaincharacter,
            dailyreward = character.dailyrewardstate,
            hidden = character.ishidden,
            vocation = character.vocation,
            outfitid = character.outfitid,
            headcolor = character.headcolor,
            torsocolor = character.torsocolor,
            legscolor = character.legscolor,
            detailcolor = character.detailcolor,
            addonsflags = character.addonsflags,
            worldName = world.name,
            worldIp = world.ip,
            worldPort = world.port,
            previewState = world.previewstate
        }
    end
    local session = json.decode(jsonSession)
    local premiumUntil = tonumber(session.premiumuntil)
    local account = {
        status = '',
        premDays = math.floor((premiumUntil - os.time()) / 86400),
        subStatus = premiumUntil > os.time() and SubscriptionStatus.Premium or SubscriptionStatus.Free
    }
    G.sessionKey = session.sessionkey
    onCharacterList(nil, characters, account)
end

function EnterGame.loginFailed(requestId, msg, result)
    if G.requestId ~= requestId then return end
    onError(nil, msg, result)
end

function EnterGame.doLogin()
    G.account = enterGame:getChildById('accountNameTextEdit'):getText()
    G.password = enterGame:getChildById('accountPasswordTextEdit'):getText()
    G.authenticatorToken = enterGame:getChildById('authenticatorTokenTextEdit'):getText()
    G.stayLogged = enterGame:getChildById('stayLoggedBox'):isChecked()
    G.host = enterGame:getChildById('serverHostTextEdit'):getText()
    G.port = tonumber(enterGame:getChildById('serverPortTextEdit'):getText())
    local clientVersion = tonumber(clientBox:getText())
    local httpLogin = enterGame:getChildById('httpLoginBox'):isChecked()
    EnterGame.hide()

    if g_game.isOnline() then
        local errorBox = displayErrorBox(tr('Login Error'), tr('Cannot login while already in game.'))
        connect(errorBox, { onOk = EnterGame.show })
        return
    end

        g_settings.set('host', G.host)
    g_settings.set('port', G.port)
    g_settings.set('client-version', clientVersion)

    -- Os assets s�o carregados automaticamente ao definir a vers�o do cliente
    g_game.setClientVersion(clientVersion)
    g_game.setProtocolVersion(g_game.getClientProtocolVersion(clientVersion))
    g_game.chooseRsa(G.host)

    -- Mostra a caixa de "Conectando..."
    loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to login server...'))
    connect(loadBox, {
        onCancel = function(msgbox)
            loadBox = nil
            EnterGame.show()
        end
    })

    local payload = json.encode({
        email = G.account,
        password = G.password,
        type = "login"
    })

    local loginUrl = "http://" .. G.host .. ":" .. tostring(G.port) .. "/login"
    print(">>> [DEBUG] Enviando HTTP POST para " .. loginUrl)

    HTTP.post(loginUrl, payload, function(response, err)
        if loadBox then
            loadBox:destroy()
            loadBox = nil
        end

        if err then
            print(">>> [ERRO] HTTP POST falhou: " .. err)
            onError(nil, "Falha na conex�o com o servidor de login.")
            return
        end

        print(">>> [DEBUG] Resposta recebida: " .. response)

        local success, result = pcall(json.decode, response)
        if not success then
            onError(nil, "Resposta inv�lida do servidor.")
            return
        end

        if result.errorCode and result.errorCode ~= 0 then
            onError(nil, result.errorMessage or "Erro desconhecido.")
            return
        end

        local session = result.session
        local playData = result.playdata

        if not session or not playData then
            onError(nil, "Resposta incompleta do servidor.")
            return
        end

        G.sessionKey = session.sessionkey

        local worlds = {}
        if playData.worlds then
            for _, world in ipairs(playData.worlds) do
                worlds[world.id] = {
                    name = world.name,
                    ip = world.externaladdressprotected or world.ip,
                    port = world.externalportprotected or world.port,
                    previewState = world.previewstate == 1
                }
            end
        end

        local characters = {}
        if playData.characters then
            for index, char in ipairs(playData.characters) do
                local world = worlds[char.worldid]
                characters[index] = {
                    name = char.name,
                    level = char.level,
                    main = char.ismaincharacter,
                    dailyreward = char.dailyrewardstate,
                    hidden = char.ishidden,
                    vocation = char.vocation,
                    outfitid = char.outfitid,
                    headcolor = char.headcolor,
                    torsocolor = char.torsocolor,
                    legscolor = char.legscolor,
                    detailcolor = char.detailcolor,
                    addonsflags = char.addonsflags,
                    worldName = world and world.name or "Unknown",
                    worldIp = world and world.ip or "127.0.0.1",
                    worldPort = world and world.port or 7173,
                    previewState = world and world.previewState or false
                }
            end
        end

        local accountInfo = {
            status = '',
            premDays = 0,
            subStatus = SubscriptionStatus.Free
        }
        if session.premiumuntil then
            local premiumUntil = tonumber(session.premiumuntil)
            accountInfo.premDays = math.floor((premiumUntil - os.time()) / 86400)
            accountInfo.subStatus = premiumUntil > os.time() and SubscriptionStatus.Premium or SubscriptionStatus.Free
        end

        onCharacterList(nil, characters, accountInfo)
    end)
end

function EnterGame.displayMotd()
    if not motdWindow then
        motdWindow = displayInfoBox(tr('Message of the day'), G.motdMessage)
        motdWindow.onOk = function() motdWindow = nil end
    end
end

function EnterGame.setDefaultServer(host, port, protocol)
    local hostTextEdit = enterGame:getChildById('serverHostTextEdit')
    local portTextEdit = enterGame:getChildById('serverPortTextEdit')
    local clientLabel = enterGame:getChildById('clientLabel')
    local accountTextEdit = enterGame:getChildById('accountNameTextEdit')
    local passwordTextEdit = enterGame:getChildById('accountPasswordTextEdit')
    local authenticatorTokenTextEdit = enterGame:getChildById('authenticatorTokenTextEdit')
    if hostTextEdit:getText() ~= host then
        hostTextEdit:setText(host)
        portTextEdit:setText(port)
        clientBox:setCurrentOption(protocol)
        accountTextEdit:setText('')
        passwordTextEdit:setText('')
        authenticatorTokenTextEdit:setText('')
    end
end

function EnterGame.setUniqueServer(host, port, protocol, windowWidth, windowHeight)
    local hostTextEdit = enterGame:getChildById('serverHostTextEdit')
    hostTextEdit:setText(host)
    hostTextEdit:setVisible(false)
    hostTextEdit:setHeight(0)
    local portTextEdit = enterGame:getChildById('serverPortTextEdit')
    portTextEdit:setText(port)
    portTextEdit:setVisible(false)
    portTextEdit:setHeight(0)
    local authenticatorTokenTextEdit = enterGame:getChildById('authenticatorTokenTextEdit')
    authenticatorTokenTextEdit:setText('')
    authenticatorTokenTextEdit:setOn(false)
    local authenticatorTokenLabel = enterGame:getChildById('authenticatorTokenLabel')
    authenticatorTokenLabel:setOn(false)
    local stayLoggedBox = enterGame:getChildById('stayLoggedBox')
    stayLoggedBox:setChecked(false)
    stayLoggedBox:setOn(false)
    local clientVersion = tonumber(protocol)
    clientBox:setCurrentOption(clientVersion)
    clientBox:setVisible(false)
    clientBox:setHeight(0)
    local serverLabel = enterGame:getChildById('serverLabel')
    serverLabel:setVisible(false)
    serverLabel:setHeight(0)
    local portLabel = enterGame:getChildById('portLabel')
    portLabel:setVisible(false)
    portLabel:setHeight(0)
    local clientLabel = enterGame:getChildById('clientLabel')
    clientLabel:setVisible(false)
    clientLabel:setHeight(0)
    local httpLoginBox = enterGame:getChildById('httpLoginBox')
    httpLoginBox:setVisible(false)
    httpLoginBox:setHeight(0)
    local serverListButton = enterGame:getChildById('serverListButton')
    serverListButton:setVisible(false)
    serverListButton:setHeight(0)
    serverListButton:setWidth(0)
    local rememberEmailBox = enterGame:getChildById('rememberEmailBox')
    rememberEmailBox:setMarginTop(5)
    if not windowWidth then windowWidth = 380 end
    enterGame:setWidth(windowWidth)
    if not windowHeight then windowHeight = 210 end
    enterGame:setHeight(windowHeight)
    enterGame.disableToken = true
    g_game.setClientVersion(clientVersion)
    g_game.setProtocolVersion(g_game.getClientProtocolVersion(clientVersion))
end

function EnterGame.setServerInfo(message)
    local label = enterGame:getChildById('serverInfoLabel')
    label:setText(message)
end

function EnterGame.disableMotd()
    motdEnabled = false
end