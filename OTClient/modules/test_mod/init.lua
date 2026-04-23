-- modules/test_mod/init.lua
print("TestMod carregado com sucesso!")

local TestMod = {}

function TestMod.init()
    print("TestMod.init() executado.")
end

function TestMod.terminate()
    print("TestMod.terminate() executado.")
end

modules.test_mod = TestMod
return TestMod