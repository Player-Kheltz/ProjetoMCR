/**
 * Projeto MCR - Servidor de Fantasia Imersiva
 * Baseado no Canary Engine (opentibiabr/canary)
 * Copyright (©) 2019–present OpenTibiaBR <opentibiabr@outlook.com>
 * Modificações para o Projeto MCR © 2026 Equipe MCR
 * Repositório original: https://github.com/opentibiabr/canary
 * Licença: https://github.com/opentibiabr/canary/blob/main/LICENSE
 */

#pragma once

#include "security/rsa.hpp"
#include "server/server.hpp"

class Logger;

// [MCR] Exceção personalizada com mensagem em português
class FailedToInitializeCanary : public std::exception {
private:
	std::string message;

public:
	explicit FailedToInitializeCanary(const std::string &msg) :
		message("Falha na inicialização do Projeto MCR. " + msg) { }

	const char* what() const noexcept override {
		return message.c_str();
	}
};

class CanaryServer {
public:
	explicit CanaryServer(
		Logger &logger,
		RSAManager &rsa,
		ServiceManager &serviceManager
	);

	int run();

private:
	enum class LoaderStatus : uint8_t {
		LOADING,
		LOADED,
		FAILED
	};

	Logger &logger;
	RSAManager &rsa;
	ServiceManager &serviceManager;

	LoaderStatus loaderStatus = LoaderStatus::LOADING;
	std::mutex loaderMutex;
	std::condition_variable loaderCV;

	void logInfos();
	static void toggleForceCloseButton();
	static void badAllocationHandler();
	static void shutdown();

	static std::string getCompiler();
	static std::string getPlatform();

	void loadConfigLua();
	void validateDatapack();
	void initializeDatabase();
	void loadModules();
	void setWorldType();
	void loadMaps() const;
	void setupHousesRent();
	void modulesLoadHelper(bool loaded, std::string moduleName);
};