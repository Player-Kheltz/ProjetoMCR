--[[
    Projeto: MCR
    Módulo: Registro de Conta (Cliente) - Versão Final com Correção de Encoding
    Descrição: Criação de conta com validação inline, Tab, Enter, foco e correção UTF?8.
    Autor: Equipe MCR
    Data: 21/04/2026
--]]

local apiBaseUrl = "http://127.0.0.1:8080"
local isRequestPending = false

local COLOR_VALID = '#6AAF6A'
local COLOR_INVALID = '#CF6A6A'
local COLOR_NEUTRAL = '#A0A0B0'
local COLOR_DISABLED_BG = '#1A1A2A'
local COLOR_BUTTON_ERROR = '#8B2A2A'
local COLOR_BUTTON_PRESSED = '#5A1A1A'

-- ========== MAPEAMENTO DE CÓDIGOS DE ERRO PARA MENSAGENS EM PORTUGUÊS ==========
local ERROR_MESSAGES = {
    invalid_request              = "Dados inválidos. Verifique os campos.",
    invalid_account_name_length  = "O nome de conta deve ter entre 3 e 32 caracteres.",
    password_too_short           = "A senha deve ter no mínimo 3 caracteres.",
    passwords_do_not_match       = "As senhas não coincidem.",
    account_name_taken           = "Este nome de conta já está em uso.",
    database_error               = "Erro ao criar a conta. Tente novamente mais tarde.",
}

local function getErrorMessage(error_code, fallback)
    return ERROR_MESSAGES[error_code] or fallback or "Erro desconhecido."
end

-- ========== CORREÇÃO DE ENCODING (UTF?8 mal interpretado como Latin?1) ==========
local function fixEncoding(str)
    if not str or type(str) ~= 'string' then return str end
    -- Substitui os padrões de erro mais comuns (ex.: "jÃi" ? "já")
    local fixed = str:gsub("\195\131", "\195\161")   -- Ã ? á
    fixed = fixed:gsub("\195\169", "\195\169")       -- é ? é (mantém)
    fixed = fixed:gsub("\195\173", "\195\173")       -- í ? í
    fixed = fixed:gsub("\195\179", "\195\179")       -- ó ? ó
    fixed = fixed:gsub("\195\186", "\195\186")       -- ú ? ú
    fixed = fixed:gsub("\195\167", "\195\167")       -- ç ? ç
    fixed = fixed:gsub("\195\163", "\195\163")       -- ã ? ã
    fixed = fixed:gsub("\195\181", "\195\181")       -- õ ? õ
    fixed = fixed:gsub("\195\162", "\195\162")       -- â ? â
    fixed = fixed:gsub("\195\170", "\195\170")       -- ê ? ê
    fixed = fixed:gsub("\195\174", "\195\174")       -- î ? î
    fixed = fixed:gsub("\195\180", "\195\180")       -- ô ? ô
    fixed = fixed:gsub("\195\187", "\195\187")       -- û ? û
    return fixed
end

local function isValidHeroName(name)
    return #name >= 3 and #name <= 32
end

local function calculatePasswordStrength(pass)
    if #pass < 3 then return 0, 'Muito curta' end
    local hasLetter = pass:match("%a") ~= nil
    local hasNumber = pass:match("%d") ~= nil
    local hasSpecial = pass:match("[^%w]") ~= nil
    if hasLetter and hasNumber and hasSpecial then
        return 3, 'Forte'
    elseif hasLetter and hasNumber then
        return 2, 'Média'
    else
        return 1, 'Fraca'
    end
end

function showRegisterWindow()
    local window = g_ui.displayUI('register_window.otui')
    if not window then
        print(">>> ERRO: Não foi possível carregar register_window.otui")
        return
    end

    local function getWidget(id)
        return window:recursiveGetChildById(id) or window:getChildById(id)
    end

    local editName = getWidget('accountName')
    local editPass = getWidget('password')
    local editConfirm = getWidget('confirmPassword')
    local nameStatusLabel = getWidget('nameStatusLabel')
    local passwordStatusLabel = getWidget('passwordStatusLabel')
    local confirmStatusLabel = getWidget('confirmStatusLabel')
    local globalStatusLabel = getWidget('globalStatusLabel')
    local btnRegister = getWidget('registerButton')
    local btnCancel = getWidget('cancelButton')
    local closeBtn = getWidget('closeButton')

    if not btnCancel or not btnRegister then
        print(">>> ERRO: Botões não encontrados na UI!")
        return
    end

    local originalButtonColor = btnRegister:getBackgroundColor() or '#5A4A2A'
    local originalButtonText = btnRegister:getText()

    if nameStatusLabel then nameStatusLabel:setText('') end
    if passwordStatusLabel then passwordStatusLabel:setText('') end
    if confirmStatusLabel then confirmStatusLabel:setText('') end
    if globalStatusLabel then globalStatusLabel:setText('') end

    local function closeWindow()
        window:destroy()
    end
    btnCancel.onClick = closeWindow
    if closeBtn then closeBtn.onClick = closeWindow end

    -- ========== LÓGICA DE VALIDAÇÃO ==========
    local function updateFieldStyle(edit, isValid)
        if edit then
            edit:setBorderColor(isValid and COLOR_VALID or COLOR_INVALID)
        end
    end

    local function setGlobalStatus(message, color)
        if globalStatusLabel then
            globalStatusLabel:setText(message)
            globalStatusLabel:setColor(color or COLOR_NEUTRAL)
        end
    end

    local function validateAll()
        local name = editName:getText()
        local pass = editPass:getText()
        local confirm = editConfirm:getText()

        local nameValid = isValidHeroName(name)
        updateFieldStyle(editName, nameValid)
        if nameStatusLabel then
            if name == '' then
                nameStatusLabel:setText('')
            elseif nameValid then
                nameStatusLabel:setText('(Disponível)')
                nameStatusLabel:setColor(COLOR_VALID)
            else
                nameStatusLabel:setText('(3-32 caracteres)')
                nameStatusLabel:setColor(COLOR_INVALID)
            end
        end

        local passValid = #pass >= 3
        local confirmValid = (pass == confirm) and passValid
        updateFieldStyle(editPass, passValid)
        updateFieldStyle(editConfirm, confirmValid)

        if passwordStatusLabel then
            if pass == '' and confirm == '' then
                passwordStatusLabel:setText('')
            elseif pass ~= confirm then
                passwordStatusLabel:setText('(Não Confere)')
                passwordStatusLabel:setColor(COLOR_INVALID)
            else
                passwordStatusLabel:setText('(Confere)')
                passwordStatusLabel:setColor(COLOR_VALID)
            end
        end

        if confirmStatusLabel then
            if pass == confirm and passValid then
                local strength, strengthText = calculatePasswordStrength(pass)
                local strengthColors = { '#CF6A6A', '#DFA040', '#6AAF6A' }
                confirmStatusLabel:setText(string.format('(Segurança: %s)', strengthText))
                confirmStatusLabel:setColor(strengthColors[strength] or COLOR_NEUTRAL)
            else
                confirmStatusLabel:setText('')
            end
        end

        if nameValid and passValid and confirmValid then
            setGlobalStatus('')
        end

        return nameValid and passValid and confirmValid
    end

    -- ========== SUBMISSÃO DO FORMULÁRIO ==========
    local function submitForm()
        if isRequestPending then return end

        if not validateAll() then
            btnRegister:setEnabled(false)
            btnRegister:setBackgroundColor(COLOR_BUTTON_PRESSED)
            setGlobalStatus('Verificar campos!', COLOR_INVALID)
            scheduleEvent(function()
                btnRegister:setEnabled(true)
                btnRegister:setBackgroundColor(originalButtonColor)
                setGlobalStatus('')
                validateAll()
            end, 3000)
            return
        end

        local name = editName:getText()
        local pass = editPass:getText()
        local confirm = editConfirm:getText()

        local postData = json.encode({
            account_name = name,
            password = pass,
            confirm_password = confirm
        })

        isRequestPending = true
        btnRegister:setEnabled(false)
        btnCancel:setEnabled(false)
        btnRegister:setText('Criando...')
        setGlobalStatus('Conectando ao servidor...', COLOR_NEUTRAL)

        HTTP.post(apiBaseUrl .. "/register", postData, function(response)
            isRequestPending = false

            -- ?? Aplica correção de encoding antes de decodificar JSON
            local fixedResponse = fixEncoding(response)

            local ok, result = pcall(json.decode, fixedResponse)
            if not ok then
                -- Fallback para a resposta original
                ok, result = pcall(json.decode, response)
                if not ok then
                    btnRegister:setEnabled(true)
                    btnCancel:setEnabled(true)
                    btnRegister:setText(originalButtonText)
                    btnRegister:setBackgroundColor(COLOR_BUTTON_PRESSED)
                    setGlobalStatus('Erro de conexão. Tente novamente.', COLOR_INVALID)
                    scheduleEvent(function()
                        btnRegister:setBackgroundColor(originalButtonColor)
                        setGlobalStatus('')
                    end, 3000)
                    return
                end
            end

            if result.success then
                editName:setEnabled(false)
                editPass:setEnabled(false)
                editConfirm:setEnabled(false)
                editName:setBackgroundColor(COLOR_DISABLED_BG)
                editPass:setBackgroundColor(COLOR_DISABLED_BG)
                editConfirm:setBackgroundColor(COLOR_DISABLED_BG)

                btnRegister:setEnabled(false)
                btnCancel:setEnabled(false)
                btnRegister:setText('Sucesso!')
                btnRegister:setBackgroundColor(COLOR_VALID)

                setGlobalStatus('Conta criada com sucesso!', COLOR_VALID)
                if nameStatusLabel then nameStatusLabel:setText('') end
                if passwordStatusLabel then passwordStatusLabel:setText('') end
                if confirmStatusLabel then confirmStatusLabel:setText('') end

                scheduleEvent(closeWindow, 3000)
             else
                btnRegister:setEnabled(true)
                btnCancel:setEnabled(true)
                btnRegister:setText(originalButtonText)
                btnRegister:setBackgroundColor(COLOR_BUTTON_PRESSED)

                -- Usa o error_code para obter a mensagem correta em português
                local errorMsg = getErrorMessage(result.error_code, result.message)
                setGlobalStatus(errorMsg, COLOR_INVALID)

                scheduleEvent(function()
                    btnRegister:setBackgroundColor(originalButtonColor)
                    setGlobalStatus('')
                    validateAll()
                end, 3000)
            end
        end)
    end

    btnRegister.onClick = submitForm

    -- ========== CONFIGURAÇÃO DOS CAMPOS (TAB, ENTER) ==========
    local fields = { editName, editPass, editConfirm }

    for _, field in ipairs(fields) do
        field.onKeyPress = function(self, keyCode, keyboardModifiers)
            if keyCode == KeyEnter or keyCode == KeyReturn then
                submitForm()
                return true
            elseif keyCode == KeyTab then
                local currentIndex = table.find(fields, self)
                if currentIndex then
                    if keyboardModifiers == KeyboardShiftModifier then
                        local prevIndex = currentIndex - 1
                        if prevIndex < 1 then prevIndex = #fields end
                        fields[prevIndex]:focus()
                    else
                        local nextIndex = currentIndex + 1
                        if nextIndex > #fields then nextIndex = 1 end
                        fields[nextIndex]:focus()
                    end
                end
                return true
            end
            return false
        end

        field.onTextChange = validateAll
    end

    -- ========== FOCO NO PRIMEIRO CLIQUE ==========
    local firstClickFocused = false
    window.onMousePress = function()
        if not firstClickFocused and not window:isDestroyed() then
            firstClickFocused = true
            editName:focus()
        end
    end

    validateAll()
    window:raise()
    window:focus()
end

print(">>> [REGISTRO] Script de criação de conta (final com encoding) carregado.")