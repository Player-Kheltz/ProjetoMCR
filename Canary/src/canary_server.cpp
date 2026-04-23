/**
 * Projeto MCR - Servidor de Fantasia Imersiva
 * Baseado no Canary Engine (opentibiabr/canary)
 * Copyright (©) 2019–present OpenTibiaBR <opentibiabr@outlook.com>
 * Modificações para o Projeto MCR © 2026 Equipe MCR
 * Repositório original: https://github.com/opentibiabr/canary
 * Licença: https://github.com/opentibiabr/canary/blob/main/LICENSE
 */

#include "canary_server.hpp"

#include "core.hpp"
#include "config/configmanager.hpp"
#include "creatures/npcs/npcs.hpp"
#include "creatures/players/grouping/familiars.hpp"
#include "creatures/players/imbuements/imbuements.hpp"
#include "creatures/players/storages/storages.hpp"
#include "database/databasemanager.hpp"
#include "declarations.hpp"
#include "game/game.hpp"
#include "game/scheduling/dispatcher.hpp"
#include "game/scheduling/events_scheduler.hpp"
#include "game/zones/zone.hpp"
#include "io/io_bosstiary.hpp"
#include "io/iomarket.hpp"
#include "io/ioprey.hpp"
#include "lib/thread/thread_pool.hpp"
#include "lua/creature/events.hpp"
#include "lua/modules/modules.hpp"
#include "lua/scripts/lua_environment.hpp"
#include "lua/scripts/scripts.hpp"
#include "server/network/protocol/protocollogin.hpp"
#include "server/network/protocol/protocolstatus.hpp"
#include "server/network/webhook/webhook.hpp"
#include "creatures/players/vocations/vocation.hpp"

CanaryServer::CanaryServer(
	Logger &logger,
	RSAManager &rsa,
	ServiceManager &serviceManager
) :
	logger(logger),
	rsa(rsa),
	serviceManager(serviceManager) {
	logInfos();
	toggleForceCloseButton();
	g_game().setGameState(GAME_STATE_STARTUP);
	std::set_new_handler(badAllocationHandler);
	srand(static_cast<unsigned int>(OTSYS_TIME()));

	g_dispatcher().init();

#ifdef _WIN32
	// [MCR] Define o título da janela do console como "Projeto MCR"
	SetConsoleTitleA("Projeto MCR");
#endif
}

int CanaryServer::run() {
	g_dispatcher().addEvent(
		[this] {
			try {
				loadConfigLua();
				validateDatapack();

				// [MCR] Log do protocolo em português
				logger.info("Protocolo do servidor: {}.{:02d}{}", 
				            CLIENT_VERSION_UPPER, CLIENT_VERSION_LOWER, 
				            g_configManager().getBoolean(OLD_PROTOCOL) ? " e 10x permitido!" : "");

#ifdef FEATURE_METRICS
				metrics::Options metricsOptions;
				metricsOptions.enablePrometheusExporter = g_configManager().getBoolean(METRICS_ENABLE_PROMETHEUS);
				if (metricsOptions.enablePrometheusExporter) {
					metricsOptions.prometheusOptions.url = g_configManager().getString(METRICS_PROMETHEUS_ADDRESS);
				}
				metricsOptions.enableOStreamExporter = g_configManager().getBoolean(METRICS_ENABLE_OSTREAM);
				if (metricsOptions.enableOStreamExporter) {
					metricsOptions.ostreamOptions.export_interval_millis = std::chrono::milliseconds(g_configManager().getNumber(METRICS_OSTREAM_INTERVAL));
				}
				g_metrics().init(metricsOptions);
#endif
				rsa.start();
				initializeDatabase();
				loadModules();
				setWorldType();
				loadMaps();

				logger.info("Inicializando estado do jogo...");
				g_game().setGameState(GAME_STATE_INIT);

				setupHousesRent();
				g_game().transferHouseItemsToDepot();

				IOMarket::checkExpiredOffers();
				IOMarket::getInstance().updateStatistics();

				logger.info("Todos os módulos carregados. Iniciando servidor...");

#ifndef _WIN32
				if (getuid() == 0 || geteuid() == 0) {
					logger.warn("{} foi executado como root. Considere executar como um usuário normal.",
					            "Projeto MCR");
				}
#endif

				g_game().start(&serviceManager);
				if (g_configManager().getBoolean(TOGGLE_MAINTAIN_MODE)) {
					g_game().setGameState(GAME_STATE_CLOSED);
					g_logger().warn("Inicializado em modo de manutenção!");
					g_webhook().sendMessage(":yellow_square: Servidor agora **online** _(acesso restrito à equipe)_");
				} else {
					g_game().setGameState(GAME_STATE_NORMAL);
					g_webhook().sendMessage(":green_circle: Servidor agora **online**");
				}

				{
					std::scoped_lock lock(loaderMutex);
					loaderStatus = LoaderStatus::LOADED;
					loaderCV.notify_all();
				}
			} catch (FailedToInitializeCanary &err) {
				{
					std::scoped_lock lock(loaderMutex);
					loaderStatus = LoaderStatus::FAILED;
				}
				logger.error(err.what());
			}
		},
		__FUNCTION__
	);

	constexpr auto timeout = std::chrono::minutes(10);
	constexpr auto warnEvery = std::chrono::seconds(120);
	auto start = std::chrono::steady_clock::now();
	auto lastLog = start;

	while (true) {
		{
			std::scoped_lock lock(loaderMutex);
			if (loaderStatus != LoaderStatus::LOADING) {
				break;
			}
		}

		auto now = std::chrono::steady_clock::now();

		if (now - lastLog >= warnEvery) {
			logger.warn("Inicialização ainda em andamento ({} s)...", 
			            std::chrono::duration_cast<std::chrono::seconds>(now - start).count());
			lastLog = now;
		}

		if (now - start > timeout) {
			logger.error("Inicialização excedeu {} minutos - abortando.", 
			             std::chrono::duration_cast<std::chrono::minutes>(timeout).count());
			shutdown();
			return EXIT_FAILURE;
		}

		std::this_thread::sleep_for(std::chrono::milliseconds(10));
	}

	if (loaderStatus == LoaderStatus::FAILED || !serviceManager.is_running()) {
		logger.error("Nenhum serviço em execução. O servidor NÃO está online!");
		logger.error("O programa será fechado após pressionar ENTER...");
		if (isatty(STDIN_FILENO)) {
			std::cin.get();
		}

		shutdown();
		return EXIT_FAILURE;
	}

	logger.info("{} {}", g_configManager().getString(SERVER_NAME), "online!");
	g_logger().setLevel(g_configManager().getString(LOGLEVEL));

	serviceManager.run();

	shutdown();
	return EXIT_SUCCESS;
}

void CanaryServer::setWorldType() {
	const std::string worldType = asLowerCaseString(g_configManager().getString(WORLD_TYPE));
	if (worldType == "pvp") {
		g_game().setWorldType(WORLD_TYPE_PVP);
	} else if (worldType == "no-pvp") {
		g_game().setWorldType(WORLD_TYPE_NO_PVP);
	} else if (worldType == "pvp-enforced") {
		g_game().setWorldType(WORLD_TYPE_PVP_ENFORCED);
	} else {
		throw FailedToInitializeCanary(
			fmt::format(
				"Tipo de mundo desconhecido: {}. Tipos válidos: pvp, no-pvp e pvp-enforced",
				g_configManager().getString(WORLD_TYPE)
			)
		);
	}

	logger.debug("Tipo de mundo definido como {}", asUpperCaseString(worldType));
}

void CanaryServer::loadMaps() const {
	try {
		g_game().loadMainMap(g_configManager().getString(MAP_NAME));

		if (g_configManager().getBoolean(TOGGLE_MAP_CUSTOM)) {
			g_game().loadCustomMaps(g_configManager().getString(DATA_DIRECTORY) + "/world/custom/");
		}
		Zone::refreshAll();
	} catch (const std::exception &err) {
		throw FailedToInitializeCanary(err.what());
	}
}

void CanaryServer::setupHousesRent() {
	RentPeriod_t rentPeriod;
	std::string strRentPeriod = asLowerCaseString(g_configManager().getString(HOUSE_RENT_PERIOD));

	if (strRentPeriod == "yearly") {
		rentPeriod = RENTPERIOD_YEARLY;
	} else if (strRentPeriod == "weekly") {
		rentPeriod = RENTPERIOD_WEEKLY;
	} else if (strRentPeriod == "monthly") {
		rentPeriod = RENTPERIOD_MONTHLY;
	} else if (strRentPeriod == "daily") {
		rentPeriod = RENTPERIOD_DAILY;
	} else {
		rentPeriod = RENTPERIOD_NEVER;
	}

	g_game().map.houses.payHouses(rentPeriod);
}

void CanaryServer::logInfos() {
	// [MCR] Logs de inicialização em português, com nome e versão do Projeto MCR
#if defined(GIT_RETRIEVED_STATE) && GIT_RETRIEVED_STATE
	logger.debug("Projeto MCR - Versão [{}] datada de [{}]", SERVER_RELEASE_VERSION, GIT_COMMIT_DATE_ISO8601);
	#if GIT_IS_DIRTY
	logger.debug("VERSÃO DE DESENVOLVIMENTO - NÃO OFICIAL");
	#endif
#else
	logger.info("Projeto MCR - Versão {}", SERVER_RELEASE_VERSION);
#endif

	logger.debug("Compilado com {}, em {} {}, para plataforma {}", getCompiler(), __DATE__, __TIME__, getPlatform());

#if defined(LUAJIT_VERSION)
	logger.debug("Vinculado com {} para suporte a Lua", LUAJIT_VERSION);
#endif

	logger.info("Desenvolvido por: Equipe MCR");
	logger.info("Visite nosso site para atualizações, suporte e recursos: "
	            "https://projetomcr.com/"); // [MCR] Substituir pelo site oficial quando disponível
}

void CanaryServer::toggleForceCloseButton() {
#ifdef OS_WINDOWS
	const HWND hwnd = GetConsoleWindow();
	const HMENU hmenu = GetSystemMenu(hwnd, FALSE);
	EnableMenuItem(hmenu, SC_CLOSE, MF_GRAYED);
#endif
}

void CanaryServer::badAllocationHandler() {
	g_logger().error("Falha na alocação de memória. Servidor sem memória. "
	                 "Reduza o tamanho do mapa ou compile em modo 64 bits.");

	if (isatty(STDIN_FILENO)) {
		getchar();
	}

	shutdown();
	exit(-1);
}

std::string CanaryServer::getPlatform() {
#if defined(__amd64__) || defined(_M_X64)
	return "x64";
#elif defined(__i386__) || defined(_M_IX86) || defined(_X86_)
	return "x86";
#elif defined(__arm__)
	return "ARM";
#else
	return "desconhecida";
#endif
}

std::string CanaryServer::getCompiler() {
	std::string compiler;
#if defined(__clang__)
	return compiler = fmt::format("Clang++ {}.{}.{}", __clang_major__, __clang_minor__, __clang_patchlevel__);
#elif defined(_MSC_VER)
	return compiler = fmt::format("Microsoft Visual Studio {}", _MSC_VER);
#elif defined(__GNUC__)
	return compiler = fmt::format("G++ {}.{}.{}", __GNUC__, __GNUC_MINOR__, __GNUC_PATCHLEVEL__);
#else
	return compiler = "desconhecido";
#endif
}

void CanaryServer::loadConfigLua() {
	std::string configName = "config.lua";
	std::ifstream c_test("./" + configName);
	if (!c_test.is_open()) {
		std::ifstream config_lua_dist(configName + ".dist");
		if (config_lua_dist.is_open()) {
			logger.info("Copiando {}.dist para {}", configName, configName);
			std::ofstream config_lua(configName);
			config_lua << config_lua_dist.rdbuf();
			config_lua.close();
			config_lua_dist.close();
		}
	} else {
		c_test.close();
	}

	g_configManager().setConfigFileLua(configName);

	modulesLoadHelper(g_configManager().load(), g_configManager().getConfigFileLua());

#ifdef _WIN32
	const std::string &defaultPriority = g_configManager().getString(DEFAULT_PRIORITY);
	if (strcasecmp(defaultPriority.c_str(), "high") == 0) {
		SetPriorityClass(GetCurrentProcess(), HIGH_PRIORITY_CLASS);
	} else if (strcasecmp(defaultPriority.c_str(), "above-normal") == 0) {
		SetPriorityClass(GetCurrentProcess(), ABOVE_NORMAL_PRIORITY_CLASS);
	}
#endif
}

void CanaryServer::validateDatapack() {
	const auto useAnyDatapack = g_configManager().getBoolean(USE_ANY_DATAPACK_FOLDER);
	const auto datapackName = g_configManager().getString(DATA_DIRECTORY);

	if (!useAnyDatapack && datapackName != "data-canary" && datapackName != "data-otservbr-global") {
		throw FailedToInitializeCanary(fmt::format("O nome da pasta datapack '{}' é inválido. Nomes válidos: 'data-canary', "
		                                           "'data-otservbr-global', ou defina USE_ANY_DATAPACK_FOLDER = true em config.lua.",
		                                           datapackName));
	}
}

void CanaryServer::initializeDatabase() {
	logger.info("Estabelecendo conexão com o banco de dados...");
	if (!Database::getInstance().connect()) {
		throw FailedToInitializeCanary("Falha ao conectar ao banco de dados!");
	}
	logger.debug("Versão do MySQL: {}", Database::getClientVersion());

	logger.debug("Executando gerenciador de banco de dados...");
	if (!DatabaseManager::isDatabaseSetup()) {
		throw FailedToInitializeCanary(fmt::format("O banco de dados especificado em {} está vazio. Importe o schema.sql para seu banco de dados.", g_configManager().getConfigFileLua()));
	}

	DatabaseManager::updateDatabase();

	if (g_configManager().getBoolean(OPTIMIZE_DATABASE)
	    && !DatabaseManager::optimizeTables()) {
		logger.debug("Nenhuma tabela foi otimizada");
	}
	g_logger().info("Conexão com o banco de dados estabelecida!");
}

void CanaryServer::loadModules() {
	logger.info("Inicializando ambiente Lua...");
	if (!g_luaEnvironment().getLuaState()) {
		g_luaEnvironment().initState();
	}

	logger.info("Carregando módulos e scripts...");

	auto coreFolder = g_configManager().getString(CORE_DIRECTORY);
	modulesLoadHelper((g_game().loadAppearanceProtobuf(coreFolder + "/items/appearances.dat") == ERROR_NONE), "appearances.dat");

	modulesLoadHelper(g_vocations().loadFromXml(), "XML/vocations.xml");
	modulesLoadHelper(Outfits::getInstance().loadFromXml(), "XML/outfits.xml");
	modulesLoadHelper(Familiars::getInstance().loadFromXml(), "XML/familiars.xml");
	modulesLoadHelper(g_imbuements().loadFromXml(), "XML/imbuements.xml");
	modulesLoadHelper(g_storages().loadFromXML(), "XML/storages.xml");

	modulesLoadHelper(Item::items.loadFromXml(), "items.xml");

	const auto datapackFolder = g_configManager().getString(DATA_DIRECTORY);
	logger.debug("Carregando scripts do núcleo na pasta: {}/", coreFolder);
	modulesLoadHelper((g_luaEnvironment().loadFile(coreFolder + "/core.lua", "core.lua") == 0), "core.lua");
	modulesLoadHelper(g_scripts().loadScripts(coreFolder + "/scripts/lib", true, false), coreFolder + "/scripts/libs");
	modulesLoadHelper(g_scripts().loadScripts(coreFolder + "/scripts", false, false), coreFolder + "/scripts");
	modulesLoadHelper((g_npcs().load(true, false)), "npclib");

	modulesLoadHelper(g_events().loadFromXml(), "events/events.xml");
	modulesLoadHelper(g_modules().loadFromXml(), "modules/modules.xml");

	logger.debug("Carregando scripts do datapack na pasta: {}/", datapackFolder);
	modulesLoadHelper(g_scripts().loadScripts(datapackFolder + "/scripts/lib", true, false), datapackFolder + "/scripts/libs");
	modulesLoadHelper(g_scripts().loadScripts(datapackFolder + "/scripts", false, false), datapackFolder + "/scripts");
	modulesLoadHelper(g_scripts().loadScripts(datapackFolder + "/monster", false, false), datapackFolder + "/monster");
	modulesLoadHelper((g_npcs().load(false, true)), "npc");

	modulesLoadHelper(g_eventsScheduler().loadScheduleEventFromXml(), "XML/events.xml");
	modulesLoadHelper(g_eventsScheduler().loadScheduleEventFromJson(), "json/eventscheduler/events.json");

	g_game().loadBoostedCreature();
	g_ioBosstiary().loadBoostedBoss();
	g_ioprey().initializeTaskHuntOptions();
	g_game().logCyclopediaStats();
}

void CanaryServer::modulesLoadHelper(bool loaded, std::string moduleName) {
	logger.debug("Carregando {}", moduleName);
	if (!loaded) {
		throw FailedToInitializeCanary(fmt::format("Não foi possível carregar: {}", moduleName));
	}
}

void CanaryServer::shutdown() {
	g_database().createDatabaseBackup(true);
	g_dispatcher().shutdown();
	g_metrics().shutdown();
	g_threadPool().shutdown();
}