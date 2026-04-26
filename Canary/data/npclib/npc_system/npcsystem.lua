-- Advanced NPC System by Jiddo

NpcSystem = {}

-- ParseParameters function
function NpcSystem.parseParameters(npcHandler)
    local npcConfig = {}
    -- Try to load the npc parameters from a file
    local file = io.open("data/npc/" .. npcHandler.npcName .. ".xml", "r")
    if not file then
        file = io.open("data/npc/" .. npcHandler.npcName .. ".lua", "r")
    end
    -- If no file is found, return an empty table
    if not file then
        return npcConfig
    end

    -- Read the file content
    local content = file:read("*all")
    io.close(file)

    -- Parse parameters from the file content
    for key, value in string.gmatch(content, "(%w+)%s*=%s*\"?([^\"\n]+)\"?") do
        npcConfig[key] = value
    end
    return npcConfig
end