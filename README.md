# Projeto MCR

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub stars](https://img.shields.io/github/stars/Player-Kheltz/ProjetoMCR)](https://github.com/Player-Kheltz/ProjetoMCR/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/Player-Kheltz/ProjetoMCR)](https://github.com/Player-Kheltz/ProjetoMCR/network)
[![GitHub issues](https://img.shields.io/github/issues/Player-Kheltz/ProjetoMCR)](https://github.com/Player-Kheltz/ProjetoMCR/issues)

**Git do Projeto MCR, por Kheltz**

O **Projeto MCR** é um servidor de MMORPG independente e profundamente customizado, baseado no emulador [Canary](https://github.com/opentibiabr/canary) (versão 3.4.1, protocolo 15.00). Diferente de distribuições genéricas, o MCR se destaca por sua filosofia de design focada em imersão narrativa em um mundo de fantasia original, com toda a experiência do jogador ocorrendo exclusivamente dentro do cliente OTClient.

---

## 📖 Visão Geral

O MCR não replica o conteúdo do Tibia oficial. Ele se passa em um universo próprio, onde a imaginação é o limite: reinos flutuantes, florestas vivas, cidades goblin industriais, dragões filósofos, maldições temporais e artefatos que desafiam as leis da física. Tudo é possível dentro do escopo técnico do projeto.

### 🎯 Pilares do Projeto

| Pilar | Descrição |
| :--- | :--- |
| **Imersão Narrativa em pt‑BR** | Todo o conteúdo textual é localizado em português do Brasil com correção gramatical impecável. NPCs possuem personalidade, histórias próprias e reagem ao contexto do personagem. |
| **Experiência de Jogo Moderna** | Interface híbrida e intuitiva com chat destacando palavras‑chave, HUD persistente para missões, notificações toast e janelas modais apenas para ações críticas. |
| **Estabilidade e Performance** | Utilização do OTClient Redemption (motor de renderização otimizado) e do servidor Canary, ambos com suporte nativo ao protocolo 15.00. |
| **Independência Criativa** | Embora herde a estrutura do Canary, todas as adições de conteúdo, sistemas e narrativas são originais, construindo um mundo de fantasia coeso. |
| **Jornada 100% no Cliente** | Nenhuma experiência do jogador deve ocorrer fora do OTClient. Desde a criação de conta (via Account Manager "Alma") até o gerenciamento de personagem, tudo é feito dentro do cliente. |

---

## 🗂️ Estrutura do Repositório

O repositório contém os seguintes diretórios principais, cada um com as customizações específicas do Projeto MCR:

| Diretório | Descrição |
| :--- | :--- |
| [`Canary/`](Canary/) | Código‑fonte do servidor Canary (C++, Lua), já com todas as modificações MCR aplicadas. |
| [`OTClient/`](OTClient/) | Código‑fonte do cliente OTClient Redemption (C++17, Lua), já com todas as modificações MCR aplicadas. |
| [`LoginServer/`](LoginServer/) | Código‑fonte do servidor de login em Go, expandido com endpoints customizados (ex.: `/register`). |
| [`docs/`](docs/) | Documentação completa do projeto, incluindo as especificações avançadas (`Projeto MCR.txt`) e o diário de desenvolvimento (`MCR_DevLog.txt`). |
| [`MapEditor/`](MapEditor/) | Editor de mapas (Remere's Map Editor) compatível com o protocolo 15.00 e extensões MCR. |
| [`MyAAC/`](MyAAC/) | (Opcional) Site/AAC para funcionalidades complementares. |

> **Observação**: Os repositórios originais ([opentibiabr/canary](https://github.com/opentibiabr/canary), [opentibiabr/otclient](https://github.com/opentibiabr/otclient), etc.) serviram como base, mas o estado atual do desenvolvimento está integralmente contido nas pastas acima. Toda e qualquer modificação deve ser feita diretamente nesses fontes e versionada neste repositório.[reference:0]

---

## ⚙️ Pré‑requisitos

Antes de iniciar, certifique‑se de ter os seguintes softwares instalados:

- **Git** (para clonar o repositório e seus submódulos)
- **Compilador C++** com suporte a C++17 (MSVC, GCC ou Clang)
- **CMake** (versão 3.21 ou superior)
- **vcpkg** (gerenciador de pacotes para C/C++)
- **Go** (versão 1.20 ou superior, para o Login Server)
- **MySQL** ou **MariaDB** (versão 5.7 ou superior)
- **Lua** (versão 5.4, normalmente gerenciada pelo vcpkg)

---

## 🚀 Instalação e Configuração

Siga os passos abaixo para configurar o ambiente de desenvolvimento do Projeto MCR.

### 1. Clonar o Repositório

```bash
git clone --recurse-submodules https://github.com/Player-Kheltz/ProjetoMCR.git
cd ProjetoMCR
2. Configurar o Banco de Dados
Crie um banco de dados chamado BancoServer no MySQL/MariaDB e importe o schema do Canary:

bash
mysql -u root -p -e "CREATE DATABASE BancoServer CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -u root -p BancoServer < Canary/schema.sql
3. Compilar e Executar o Servidor Canary
Navegue até a pasta Canary/.

Configure o vcpkg (se ainda não estiver configurado):

bash
git clone https://github.com/Microsoft/vcpkg.git
cd vcpkg
./bootstrap-vcpkg.sh   # ou .\bootstrap-vcpkg.bat no Windows
./vcpkg integrate install
Compile o servidor usando CMake:

bash
mkdir build && cd build
cmake .. -DCMAKE_TOOLCHAIN_FILE=[caminho-para-vcpkg]/scripts/buildsystems/vcpkg.cmake
cmake --build . --config Release
Ajuste o arquivo config.lua com as credenciais do banco de dados e outras configurações (veja a seção "Configuração" abaixo).

Execute o servidor:

bash
./canary   # ou canary.exe no Windows
4. Compilar e Executar o OTClient
Navegue até a pasta OTClient/.

Siga as instruções de compilação do repositório oficial do OTClient Redemption. Geralmente envolve:

Instalar dependências via vcpkg.

Executar CMake com o toolchain do vcpkg.

Compilar o projeto.

Após a compilação, execute o cliente e aponte para o servidor local (127.0.0.1, porta 7171 para status e 7173 para jogo).

5. Compilar e Executar o Login Server
Navegue até a pasta LoginServer/.

Instale as dependências Go:

bash
go mod download
Compile e execute:

bash
go build -o loginserver ./cmd/loginserver
./loginserver
O Login Server estará ouvindo na porta 8080 por padrão.

🔧 Configuração Detalhada
Servidor Canary (Canary/config.lua)
As principais configurações já estão ajustadas para o Projeto MCR. Destaques:

Configuração	Valor	Descrição
mysqlDatabase	"BancoServer"	Nome do banco de dados padrão.
mysqlInitCommand	"SET NAMES 'utf8mb4'"	Garante suporte completo a UTF‑8.
passwordType	"sha1"	Algoritmo de hash de senhas (compatível com Login Server).
encryptionType	"aes"	Criptografia de rede (padrão protocolo 15.00).
ip	"0.0.0.0"	Aceita conexões de qualquer interface.
statusPort	7171	Porta para consulta de status.
loginPort	7172	Porta de comunicação interna com Login Server.
gamePort	7173	Porta para conexão dos jogadores.
rateExp	5.0	Taxa de experiência.
rateSkill	3.0	Taxa de habilidades.
rateLoot	2.0	Taxa de drop.
rateMagic	3.0	Taxa de magia.
rateSpawn	2.0	Taxa de respawn.
A tabela OTCFEATURES em config.lua deve ser mantida conforme especificado para informar ao cliente os recursos suportados.

Login Server (LoginServer/config.json)
A configuração padrão inclui os endpoints necessários para autenticação e criação de conta. O endpoint /register já está implementado e funcional.

OTClient
Os módulos customizados (ex.: game_account) estão localizados em OTClient/modules/. O Account Manager "Alma" é o modelo de criação de conta integrado ao cliente.

📚 Documentação
A documentação completa do projeto está disponível na pasta docs/:

Projeto MCR.txt: Especificações avançadas, visão geral, pilares, configuração técnica obrigatória e regras de ouro.

MCR_DevLog.txt: Diário de desenvolvimento com registro cronológico de todas as atividades, problemas, soluções e decisões técnicas.

IMPORTANTE: Ambos os documentos são complementares e indispensáveis para a continuidade do projeto. Consulte‑os frequentemente durante o desenvolvimento.

🤝 Contribuindo
Contribuições são bem‑vindas! Para contribuir com o Projeto MCR:

Faça um fork do repositório.

Crie uma branch para sua feature ou correção (git checkout -b feature/nova-funcionalidade).

Faça commit das suas alterações (git commit -m 'Adiciona nova funcionalidade').

Envie para o branch (git push origin feature/nova-funcionalidade).

Abra um Pull Request.

Regra de Ouro: Se uma funcionalidade desejada não puder ser implementada apenas com scripts, modifique o código‑fonte correspondente e documente a alteração no MCR_DevLog.txt.

📄 Licença
Este projeto é distribuído sob a licença MIT. Veja o arquivo LICENSE para mais detalhes.

🙏 Agradecimentos
À comunidade OpenTibiaBR pelos projetos base (Canary, OTClient Redemption, Login Server).

A todos os contribuidores e testadores que ajudam a moldar o mundo MCR.

Desenvolvido com ❤️ por Kheltz