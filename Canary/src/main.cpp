/**
 * Canary - A free and open-source MMORPG server emulator
 * Copyright (©) 2019–present OpenTibiaBR <opentibiabr@outlook.com>
 * Repository: https://github.com/opentibiabr/canary
 * License: https://github.com/opentibiabr/canary/blob/main/LICENSE
 * Contributors: https://github.com/opentibiabr/canary/graphs/contributors
 * Website: https://docs.opentibiabr.com/
 */

#ifdef _WIN32
#include <windows.h>
#endif
#include "canary_server.hpp"
#include "lib/di/container.hpp"

int main() {
    // [MCR] Força o console do Windows a usar UTF‑8 para exibição correta de acentos
    #ifdef _WIN32
        SetConsoleOutputCP(CP_UTF8);      // Codificação da saída
        SetConsoleCP(CP_UTF8);            // Codificação da entrada
    #endif

    return inject<CanaryServer>().run();
}