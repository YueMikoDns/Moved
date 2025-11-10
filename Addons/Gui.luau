local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Player = Players.LocalPlayer

print("Started")

-- Configuration
local Settings = {
    NoCrash = false,
    CacheProperties = true
}

-- Compatibility layer for different executors
local isfile = isfile or function() return false end
local readfile = readfile or function() end
local writefile = writefile or function() end

-- Performance optimizations: cache frequently used functions
local spawn, wait = task.spawn, task.wait
local tinsert, tfind, tremove = table.insert, table.find, table.remove
local format, sub, match = string.format, string.sub, string.match
local floor = math.floor

-- Constants
local PROPERTIES_FILE = "robloxproperties.json"
local API_URL = "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/refs/heads/roblox/Mini-API-Dump.json"
local MAX_PRECISION = 30

--[[
    Property Configuration
    Defines which properties to extract for each GUI class
]]
local Properties = {
    GuiObject = {
        "Position", "Size", "AnchorPoint", "AutomaticSize"
    },
    UIListLayout = {
        "Padding", "SortOrder", "HorizontalAlignment", "FillDirection", "VerticalAlignment"
    },
    UISizeConstraint = {
        "MaxSize"
    },
    UIAspectRatioConstraint = {
        "AspectRatio", "AspectType", "DominantAxis"
    },
    UICorner = {
        "CornerRadius"
    },
    UIStroke = {
        "ApplyStrokeMode", "Color", "Enabled", "LineJoinMode", "Thickness", "Transparency"
    }
}

-- Inheritance mapping for GUI classes
local ClassInheritance = {
    Frame = "GuiObject",
    TextLabel = "GuiObject",
    TextButton = "GuiObject",
    TextBox = "GuiObject",
    ImageLabel = "GuiObject",
    ImageButton = "GuiObject",
    ScrollingFrame = "GuiObject"
}

--[[
    Load and parse API dump
]]
local function LoadAPIData()
    local jsonData = isfile(PROPERTIES_FILE) and readfile(PROPERTIES_FILE) 
        or game:HttpGet(API_URL)
    
    if not isfile(PROPERTIES_FILE) then
        spawn(writefile, PROPERTIES_FILE, jsonData)
    end
    
    return HttpService:JSONDecode(jsonData)
end

--[[
    Build property list from API dump
]]
local function BuildPropertyList()
    local JSON = LoadAPIData()
    
    for _, Class in ipairs(JSON.Classes) do
        if Class.MemoryCategory == "Gui" then
            local className = Class.Name
            
            -- Initialize properties table, inheriting from parent class if exists
            Properties[className] = Properties[className] 
                or (Properties[ClassInheritance[className]] and table.clone(Properties[ClassInheritance[className]])) 
                or {}
            
            for _, Member in ipairs(Class.Members) do
                local tags = Member.Tags or {}
                local isValidProperty = Member.MemberType == "Property" 
                    and not tfind(tags, "ReadOnly")
                    and not tfind(tags, "Deprecated") 
                    and not tfind(tags, "Hidden")
                    and not tfind(Properties[className], Member.Name)
                
                if isValidProperty then
                    tinsert(Properties[className], Member.Name)
                end
            end
        end
    end
end

BuildPropertyList()

--[[
    Identifier Management
    Ensures unique names for all instances in the generated code
]]
local IdentifiersArray = {}
local Identifiers = {}

local function GetUniqueIdentifier(instance)
    local cachedIdentifier = Identifiers[instance]
    if cachedIdentifier then
        return cachedIdentifier
    end
    
    local baseName = instance.Name
    local counter = 1
    local identifier = baseName
    
    -- Find unique name by appending counter if needed
    while tfind(IdentifiersArray, identifier) do
        counter += 1
        identifier = baseName .. " " .. counter
    end
    
    tinsert(IdentifiersArray, identifier)
    Identifiers[instance] = identifier
    
    return identifier
end

--[[
    Format numbers with minimal precision
]]
local function FormatNumber(n)
    -- Try different precision levels to find the shortest accurate representation
    for precision = 0, MAX_PRECISION do
        local formatted = format("%." .. precision .. "f", n)
        
        if tonumber(formatted) == n or precision == MAX_PRECISION then
            -- Remove leading zero if number is between -1 and 1
            if tonumber(match(formatted, "(%d+)%.")) == 0 then
                formatted = sub(formatted, 2)
            end
            return formatted
        end
    end
end

--[[
    Format various Roblox data types as Lua code strings
]]
local function FormatValue(value)
    local valueType = typeof(value)
    
    local formatters = {
        ["string"] = function()
            return format('"%s"', value:gsub('"', '\\"'):gsub("\n", "\\n"))
        end,
        
        ["Vector2"] = function()
            return format("Vector2.new(%s, %s)", 
                FormatNumber(value.X), FormatNumber(value.Y))
        end,
        
        ["UDim2"] = function()
            local x, y = value.X, value.Y
            return format("UDim2.new(%s, %s, %s, %s)", 
                FormatNumber(x.Scale), FormatNumber(x.Offset), 
                FormatNumber(y.Scale), FormatNumber(y.Offset))
        end,
        
        ["UDim"] = function()
            return format("UDim.new(%s, %s)", 
                FormatNumber(value.Scale), FormatNumber(value.Offset))
        end,
        
        ["Color3"] = function()
            return format("Color3.fromRGB(%d, %d, %d)", 
                floor(value.R * 255), floor(value.G * 255), floor(value.B * 255))
        end,
        
        ["Font"] = function()
            return format("Font.new(%s, %s, %s)", 
                FormatValue(value.Family), FormatValue(value.Weight), FormatValue(value.Style))
        end,
        
        ["Content"] = function()
            return format("Content.fromUri(%s)", FormatValue(value.Uri))
        end,
        
        ["Rect"] = function()
            local min, max = value.Min, value.Max
            return format("Rect.new(%s, %s, %s, %s)", 
                FormatNumber(min.X), FormatNumber(min.Y), 
                FormatNumber(max.X), FormatNumber(max.Y))
        end,
        
        ["Instance"] = function()
            if value == workspace then
                return "workspace"
            elseif value == game then
                return "game"
            end
            
            -- Build path from instance to game
            local path = {}
            local current = value
            
            while current and current ~= game do
                tinsert(path, 1, current)
                current = current.Parent
            end
            
            if #path < 2 then
                return "nil"
            end
            
            -- Start with GetService for the service
            local result = format('game:GetService("%s")', path[1].ClassName)
            
            -- Add FindFirstChild for descendants
            for i = 2, #path do
                result = result .. format(':FindFirstChild("%s")', path[i].Name)
            end
            
            -- Optimize common patterns
            result = result:gsub('game:GetService%("Players"%):FindFirstChild%("' .. Player.Name .. '"%)', 
                'game:GetService("Players").LocalPlayer')
            result = result:gsub('game:GetService%("Workspace"%)', "workspace")
            
            return result
        end
    }
    
    -- Use specific formatter or fall back to tostring
    return (formatters[valueType] or tostring)(value)
end

--[[
    Safely attempt to get a property value
]]
local function TryGetProperty(instance, propertyName)
    local success, value = pcall(function()
        return instance[propertyName]
    end)
    return success, value
end

--[[
    Generate Lua code to recreate a GUI and its descendants
]]
local function StealGui(gui)
    local startTime = tick()
    local tableName = "instances"
    
    local code = {}
    local declarations = {format("local %s = {", tableName)}
    
    -- Cache for default values to avoid repeated Instance.new calls
    local defaultCache = {}
    
    -- Collect all instances
    local allInstances = {gui}
    for _, descendant in ipairs(gui:GetDescendants()) do
        tinsert(allInstances, descendant)
    end
    
    -- Generate instance declarations
    for _, instance in ipairs(allInstances) do
        if Settings.NoCrash then
            wait()
        end
        
        local identifier = GetUniqueIdentifier(instance)
        local className = instance.ClassName
        
        tinsert(declarations, format('\t["%s"] = Instance.new("%s"),', identifier, className))
    end
    
    tinsert(declarations, "}\n")
    
    -- Generate property assignments
    for index, instance in ipairs(allInstances) do
        local identifier = GetUniqueIdentifier(instance)
        local className = instance.ClassName
        
        -- Get or create default instance for comparison
        if not defaultCache[className] then
            defaultCache[className] = Instance.new(className)
        end
        local defaultInstance = defaultCache[className]
        
        -- Set non-default properties
        local propertyList = Properties[className] or {}
        for _, propertyName in ipairs(propertyList) do
            local success, value = TryGetProperty(instance, propertyName)
            local successDefault, defaultValue = TryGetProperty(defaultInstance, propertyName)
            
            if success and successDefault and value ~= defaultValue then
                local formattedValue = typeof(value) == "Instance" 
                    and format('%s["%s"]', tableName, GetUniqueIdentifier(value))
                    or FormatValue(value)
                
                tinsert(code, format('%s["%s"].%s = %s', 
                    tableName, identifier, propertyName, formattedValue))
            end
        end
        
        -- Always set Name
        tinsert(code, format('%s["%s"].Name = %s', 
            tableName, identifier, FormatValue(instance.Name)))
        
        -- Set Parent (special handling for root)
        if index == 1 then
            tinsert(code, format('%s["%s"].Parent = %s', 
                tableName, identifier, FormatValue(gui.Parent)))
        else
            tinsert(code, format('%s["%s"].Parent = %s["%s"]', 
                tableName, identifier, tableName, GetUniqueIdentifier(instance.Parent)))
        end
        
        tinsert(code, "") -- Empty line for readability
    end
    
    local fullCode = table.concat(declarations, "\n") .. "\n" .. table.concat(code, "\n")
    local elapsedTime = tick() - startTime
    
    return fullCode, elapsedTime
end

return StealGui
