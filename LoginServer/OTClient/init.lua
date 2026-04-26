-- ============================================================
-- Projeto MCR - init.lua (OTClient)
-- Base: opentibiabr/otclient (Protocolo 15.00)
-- Idioma: Português do Brasil (pt-BR)
-- ============================================================

-- Configuração de Serviços Externos (NÃO UTILIZADOS NO MCR)
-- A filosofia do projeto exige que todas as funcionalidades
-- estejam dentro do cliente. Portanto, comentamos/removemos
-- URLs que apontam para scripts PHP.
Services = {
    -- updater = "http://localhost/api/updater.php",
    -- status = "http://localhost/login.php",
    -- websites = "http://localhost/?subtopic=accountmanagement",
    -- createAccount = "http://localhost/clientcreateaccount.php",
    -- getCoinsUrl = "http://localhost/?subtopic=shop&step=terms",
}

-- Configuração do Servidor de Login (Login Server)
-- Deve apontar para o Login Server em execução na porta 8080
Servers = {
    {
        name = "Projeto MCR",
        host = "127.0.0.1",
        port = 8080,           -- Porta HTTP do Login Server
        client = 1500,         -- Protocolo 15.00
        httpLogin = true,      -- Usar autenticação via HTTP (Login Server)
        url = "http://127.0.0.1/"  -- URL base (opcional)
    }
}

-- ============================================================
-- INICIALIZAÇÃO DO APLICATIVO (NÃO ALTERAR)
-- ============================================================
g_app.setName("MCR Client")
g_app.setCompactName("MCR")
g_app.setOrganizationName("MCR Project")

g_app.hasUpdater = function()
    return (Services.updater and Services.updater ~= "" and g_modules.getModule("updater"))
end

g_logger.setLogFile(g_resources.getWorkDir() .. g_app.getCompactName() .. '.log')
g_logger.info(os.date('== application started at %b %d %Y %X'))
g_logger.info("== operating system: " .. g_platform.getOSName())

g_logger.info(g_app.getName() .. ' ' .. g_app.getVersion() .. ' rev ' .. g_app.getBuildRevision() .. ' (' ..
    g_app.getBuildCommit() .. ') built on ' .. g_app.getBuildDate() .. ' for arch ' ..
    g_app.getBuildArch())

-- Lua debugger (opcional)
if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
    require("lldebugger").start()
    g_logger.debug("Started LUA debugger.")
end

-- Adicionar diretórios de recursos
if not g_resources.addSearchPath(g_resources.getWorkDir() .. 'data', true) then
    g_logger.fatal('Unable to add data directory to the search path.')
end

if not g_resources.addSearchPath(g_resources.getWorkDir() .. 'modules', true) then
    g_logger.fatal('Unable to add modules directory to the search path.')
end

g_html.addGlobalStyle('/data/styles/html.css')
g_html.addGlobalStyle('/data/styles/custom.css')

g_resources.addSearchPath(g_resources.getWorkDir() .. 'mods', true)
g_resources.setWriteDir(g_resources.getWorkDir() .. 'cache')

g_resources.searchAndAddPackages('/', '.otpkg', true)

-- Carregar configurações e descobrir módulos
g_configs.loadSettings('/config.otml')
g_modules.discoverModules()

-- ============================================================
-- CARREGAMENTO DE MÓDULOS (ORDEM AJUSTADA PARA PROJETO MCR)
-- ============================================================

-- Módulos de biblioteca (faixa 0-99)
g_modules.autoLoadModules(99)
g_modules.ensureModuleLoaded('corelib')
g_modules.ensureModuleLoaded('gamelib')
g_modules.ensureModuleLoaded('modulelib')
g_modules.ensureModuleLoaded('startup')


-- Carregar demais módulos da faixa 100-499 (client)
g_modules.autoLoadModules(499)
g_modules.ensureModuleLoaded('client')

-- Módulos de jogo (faixa 500-999)
g_modules.autoLoadModules(999)
g_modules.ensureModuleLoaded('game_interface')

-- Mods (faixa 1000-9999)
g_modules.autoLoadModules(9999)
g_modules.ensureModuleLoaded('client_mods')

-- ============================================================
-- FUNÇÃO PRINCIPAL DE INICIALIZAÇÃO
-- ============================================================
local function loadModules()
    local script = '/' .. g_app.getCompactName() .. 'rc.lua'
    if g_resources.fileExists(script) then
        dofile(script)
    end

    -- Descomente para recarregar módulos automaticamente durante desenvolvimento
    -- g_modules.enableAutoReload()
end

-- Se houver updater, executar via updater; caso contrário, iniciar diretamente
if g_app.hasUpdater() then
    g_modules.ensureModuleLoaded("updater")
    return Updater.init(loadModules)
end


loadModules()