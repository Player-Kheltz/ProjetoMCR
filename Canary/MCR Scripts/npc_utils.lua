--[[
Projeto: MCR
Módulo: Biblioteca de Suporte a Diálogos (NPC Utils)
Arquivo: data/npc/lib/npc_utils.lua
Descrição: Fornece funções padronizadas para reconhecimento flexível de intenções,
personalização de pronomes/tratamento e variação de respostas.
--]]

NpcUtils = {}

-- Constantes de sexo (conforme definidas no Canary)
local PLAYERSEX_FEMALE = 1
local PLAYERSEX_MALE = 0

--[[
Verifica se a mensagem do jogador contém qualquer um dos sinônimos fornecidos.
A verificação é case‑insensitive e busca a palavra inteira para evitar falsos positivos.

@param mensagem string A mensagem digitada pelo jogador.
@param listaSinonimos table Uma tabela de strings contendo os sinônimos.
@return boolean True se a mensagem corresponder a pelo menos um sinônimo.
]]
function NpcUtils.correspondeAcao(mensagem, listaSinonimos)
    mensagem = mensagem:lower()
    for _, sinonimo in ipairs(listaSinonimos) do
        -- Padrão que busca a palavra inteira, cercada por espaços, pontuação ou início/fim da string
        local padrao = '[%p%c%z%s]' .. sinonimo:lower() .. '[%p%c%z%s]'
        if mensagem:find(padrao) or mensagem:find('^' .. sinonimo:lower() .. '$') or mensagem:find('^' .. sinonimo:lower() .. '[%p%c%z%s]') or mensagem:find('[%p%c%z%s]' .. sinonimo:lower() .. '$') then
            return true
        end
    end
    return false
end

--[[
Retorna uma tabela com pronomes, artigos e vocativos personalizados de acordo com
o sexo e a vocação do jogador. Essencial para uma narrativa imersiva e inclusiva.

@param player userdata O objeto Player do jogador.
@return table Tabela com os campos: artigo, pronome, possessivo, tratamento, bemVindo, sufixoVoc, vocativo.
]]
function NpcUtils.getTratamento(player)
    local sexo = player:getSex()
    local vocacao = player:getVocation():getName()
    local tr = {}

    if sexo == PLAYERSEX_FEMALE then
        tr.artigo = "a"; tr.pronome = "ela"; tr.possessivo = "sua"
        tr.tratamento = "senhorita"; tr.bemVindo = "bem‑vinda"; tr.sufixoVoc = "a"
    else
        tr.artigo = "o"; tr.pronome = "ele"; tr.possessivo = "seu"
        tr.tratamento = "senhor"; tr.bemVindo = "bem‑vindo"; tr.sufixoVoc = ""
    end

    -- Vocativos fantásticos de acordo com a vocação (padrão MCR)
    local vocativos = {
        Knight = "guardião" .. tr.sufixoVoc .. " de armadura reluzente",
        Paladin = "atirador" .. tr.sufixoVoc .. " de flechas sagradas",
        Sorcerer = "tecelão" .. tr.sufixoVoc .. " dos véus arcanos",
        Druid = "guardiã" .. tr.sufixoVoc .. " dos ciclos naturais"
    }
    tr.vocativo = vocativos[vocacao] or "aventureir" .. tr.sufixoVoc .. " dos reinos distantes"

    return tr
end

--[[
Seleciona aleatoriamente uma frase de uma lista e substitui o placeholder %s
pelo nome do jogador, garantindo variação nas interações.

@param listaFrases table Lista de strings com placeholders %s.
@param player userdata O jogador para o qual a frase será personalizada.
@return string A frase escolhida e formatada.
]]
function NpcUtils.escolherFraseVariada(listaFrases, player)
    local nome = player:getName()
    local frase = listaFrases[math.random(#listaFrases)]
    return frase:format(nome)
end

-- Exemplo de lista de frases de agradecimento
NpcUtils.frasesObrigado = {
    "Muito obrigado, %s! Que as estrelas guiem seu caminho.",
    "Seu auxílio é inestimável, %s. Que os Ventos Eternos soprem a seu favor.",
    "Não esquecerei sua generosidade, %s. Até que os mundos colidam novamente!"
}

-- Exemplo de lista de saudações iniciais
NpcUtils.frasesSaudacao = {
    "Ah, %s! Vejo que os ventos o trouxeram de volta.",
    "Saudações, %s. O que o traz a estas terras encantadas?",
    "Pelos bigodes do dragão ancião! É %s em pessoa!"
}