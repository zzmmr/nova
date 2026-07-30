local SaveManager = {}

function SaveManager.new(Window)
  if isfolder("Overflow/Games/"..game.GameId) then 
    local formatted = {}

    for _, path in listfiles("Overflow/Games/" .. game.GameId) do 
        local fileWithExt = path:match("[^/\\]+$")
        local nameOnly = fileWithExt:match("(.+)%..+$") or fileWithExt
        
        table.insert(formatted, nameOnly)
    end

    Window.ConfigSelector:SetOptions(formatted)
end

Window.ConfigSelector:OnChanged(function(name)
    Window:LoadConfig(readfile("Overflow/Games/" .. game.GameId .. "/"..name..".txt"))
end)

Window.ConfigSelector:OnSave(function(name, json)
    if not isfolder("Overflow/Games/"..game.GameId) then 
        return
    end 
    writefile("Overflow/Games/"..game.GameId.."/"..name.. ".txt", json)
    return true 
end)

Window.ConfigSelector:OnCreate(function(name, json)
    if not isfolder("Overflow") then 
        makefolder("Overflow")
    end 
    if not isfolder("Overflow/Games") then 
        makefolder("Overflow/Games")
    end 
    if not isfolder("Overflow/Games/"..game.GameId) then 
        makefolder("Overflow/Games/"..game.GameId)
    end 
    writefile("Overflow/Games/"..game.GameId.."/"..name.. ".txt", json)
    Window.ConfigSelector:AddOption(name)
    return true 
end)
end

return SaveManager
