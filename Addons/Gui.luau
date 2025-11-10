local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Player = Players.LocalPlayer

print("Started")

-- Configuration
local Settings = {
    NoCrash = false,
    CacheProperties = true
}

-- Executor compatibility layer
local isfile = isfile or function() return false end
local writefile = writefile or function() end
local readfile = readfile or function() return "" end

-- Performance optimizations
local spawn, wait = task.spawn, task.wait
local tinsert, tfind, tremove, tclear = table.insert, table.find, table.remove, table.clear
local format, sub, match, gsub = string.format, string.sub, string.match, string.gsub
local floor, abs = math.floor, math.abs

-- Property definitions with inheritance
local Properties = {
    GuiObject = {
        "Position", "Size", "AnchorPoint", "AutomaticSize", "BackgroundColor3", 
        "BackgroundTransparency", "BorderSizePixel", "LayoutOrder", "Visible", "ZIndex"
    },
    UIListLayout = {
        "Padding", "SortOrder", "HorizontalAlignment", "FillDirection", "VerticalAlignment"
    },
    UISizeConstraint = {
        "MaxSize", "MinSize"
    },
    UIAspectRatioConstraint = {
        "AspectRatio", "AspectType", "DominantAxis"
    },
    UICorner = {
        "CornerRadius"
    },
    UIStroke = {
        "ApplyStrokeMode", "Color", "Enabled", "LineJoinMode", "Thickness", "Transparency"
    },
    UIPadding = {
        "PaddingBottom", "PaddingLeft", "PaddingRight", "PaddingTop"
    }
}

-- Class inheritance mapping
local ClassInheritance = {
    Frame = "GuiObject",
    TextLabel = "GuiObject",
    TextButton = "GuiObject",
    TextBox = "GuiObject",
    ImageLabel = "GuiObject",
    ImageButton = "GuiObject",
    ScrollingFrame = "GuiObject",
    CanvasGroup = "GuiObject"
}

-- Load and parse API dump
local function LoadAPIDump()
    local jsonData = isfile('robloxproperties.json') and readfile('robloxproperties.json') 
        or game:HttpGet("https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/refs/heads/roblox/Mini-API-Dump.json")
    
    if not isfile("robloxproperties.json") then 
        spawn(writefile, "robloxproperties.json", jsonData) 
    end
    
    return HttpService:JSONDecode(jsonData)
end

local JSON = LoadAPIDump()

-- Build property tables from API dump
for _, Class in ipairs(JSON.Classes) do
    if Class.MemoryCategory == "Gui" then
        local className = Class.Name
        local baseProperties = Properties[className] or Properties[ClassInheritance[className]]
        Properties[className] = Properties[className] or (baseProperties and table.clone(baseProperties) or {})
        
        for _, Member in ipairs(Class.Members) do
            local tags = Member.Tags or {}
            if Member.MemberType == "Property" 
                and not tfind(tags, "ReadOnly") 
                and not tfind(tags, "Deprecated") 
                and not tfind(tags, "Hidden") 
                and not tfind(Properties[className], Member.Name) then
                tinsert(Properties[className], Member.Name)
            end
        end
    end
end

-- Identifier management
local IdentifiersArray = {}
local Identifiers = {}

local function GetUniqueIdentifier(instance)
    local identifier = Identifiers[instance]
    if identifier then
        return identifier
    end
    
    local baseName = instance.Name
    local dupeCount = 1
    
    repeat
        identifier = dupeCount == 1 and baseName or format("%s_%d", baseName, dupeCount)
        dupeCount += 1
    until not tfind(IdentifiersArray, identifier)
    
    tinsert(IdentifiersArray, identifier)
    Identifiers[instance] = identifier
    
    return identifier
end

-- Number formatting with precision
local function FormatNumber(n)
    -- Handle edge cases
    if n == 0 then return "0" end
    if abs(n) < 1e-10 then return "0" end
    
    -- Try to find minimum precision needed
    for precision = 0, 10 do
        local formatted = format("%." .. precision .. "f", n)
        if tonumber(formatted) == n then
            -- Remove leading zero for decimals < 1
            if tonumber(match(formatted, "^(%-?%d+)%.")) == 0 then
                formatted = gsub(formatted, "^0", "")
            end
            return formatted
        end
    end
    
    return tostring(n)
end

-- Value formatting with type handling
local ValueFormatters = {
    string = function(value)
        return format('"%s"', gsub(gsub(value, '"', '\\"'), "\n", "\\n"))
    end,
    
    Vector2 = function(value)
        return format("Vector2.new(%s, %s)", FormatNumber(value.X), FormatNumber(value.Y))
    end,
    
    UDim2 = function(value)
        return format("UDim2.new(%s, %s, %s, %s)", 
            FormatNumber(value.X.Scale), FormatNumber(value.X.Offset),
            FormatNumber(value.Y.Scale), FormatNumber(value.Y.Offset))
    end,
    
    UDim = function(value)
        return format("UDim.new(%s, %s)", FormatNumber(value.Scale), FormatNumber(value.Offset))
    end,
    
    Color3 = function(value)
        return format("Color3.fromRGB(%d, %d, %d)", 
            floor(value.R * 255 + 0.5), 
            floor(value.G * 255 + 0.5), 
            floor(value.B * 255 + 0.5))
    end,
    
    Font = function(value)
        return format("Font.new(%s, %s, %s)", 
            ValueFormatters.string(value.Family), 
            tostring(value.Weight), 
            tostring(value.Style))
    end,
    
    Rect = function(value)
        return format("Rect.new(%s, %s, %s, %s)",
            FormatNumber(value.Min.X), FormatNumber(value.Min.Y),
            FormatNumber(value.Max.X), FormatNumber(value.Max.Y))
    end,
    
    Instance = function(value)
        if value == workspace then return "workspace" end
        if value == game then return "game" end
        
        -- Build path from game root
        local path = {}
        local current = value
        
        while current and current ~= game do
            tinsert(path, 1, current)
            current = current.Parent
        end
        
        if #path < 2 then return "nil" end
        
        local result = format('game:GetService("%s")', path[1].ClassName)
        
        for i = 2, #path do
            result = format('%s:FindFirstChild("%s")', result, path[i].Name)
        end
        
        -- Simplify common patterns
        result = gsub(result, 'game:GetService%("Players"%):FindFirstChild%("' .. Player.Name .. '"%)', 
            'game:GetService("Players").LocalPlayer')
        result = gsub(result, 'game:GetService%("Workspace"%)', "workspace")
        
        return result
    end
}

local function FormatValue(value)
    local valueType = typeof(value)
    local formatter = ValueFormatters[valueType]
    
    if formatter then
        return formatter(value)
    end
    
    return tostring(value)
end

-- Safe property access
local function SafeGetProperty(instance, property)
    local success, value = pcall(function()
        return instance[property]
    end)
    return success, value
end

-- Default instance cache
local DefaultsCache = {}

local function GetDefaultInstance(className)
    if not DefaultsCache[className] then
        DefaultsCache[className] = Instance.new(className)
    end
    return DefaultsCache[className]
end

-- Main GUI stealing function
local function StealGui(gui)
    local startTime = tick()
    local tableName = "GuiTable"
    
    local declarations = {}
    local assignments = {}
    
    tinsert(declarations, format("local %s = {", tableName))
    
    -- Get all instances
    local instances = {gui}
    for _, descendant in ipairs(gui:GetDescendants()) do
        tinsert(instances, descendant)
    end
    
    -- Process each instance
    for index, instance in ipairs(instances) do
        if Settings.NoCrash then wait() end
        
        local className = instance.ClassName
        local identifier = GetUniqueIdentifier(instance)
        
        -- Add to declarations table
        tinsert(declarations, format('\t["%s"] = Instance.new("%s"),', identifier, className))
        
        -- Get properties for this class
        local classProperties = Properties[className] or {}
        
        -- Compare against default instance
        local defaultInstance = GetDefaultInstance(className)
        
        for _, property in ipairs(classProperties) do
            local success, value = SafeGetProperty(instance, property)
            local successDefault, defaultValue = SafeGetProperty(defaultInstance, property)
            
            if success and successDefault and value ~= defaultValue then
                local formattedValue = typeof(value) == "Instance" 
                    and format('%s["%s"]', tableName, GetUniqueIdentifier(value))
                    or FormatValue(value)
                
                tinsert(assignments, format('%s["%s"].%s = %s', 
                    tableName, identifier, property, formattedValue))
            end
        end
        
        -- Set Name property
        tinsert(assignments, format('%s["%s"].Name = %s', 
            tableName, identifier, FormatValue(instance.Name)))
        
        -- Set Parent property
        if index == 1 then
            tinsert(assignments, format('%s["%s"].Parent = %s', 
                tableName, identifier, FormatValue(gui.Parent)))
        else
            tinsert(assignments, format('%s["%s"].Parent = %s["%s"]', 
                tableName, identifier, tableName, GetUniqueIdentifier(instance.Parent)))
        end
        
        tinsert(assignments, "")
    end
    
    tinsert(declarations, "}\n")
    
    local code = table.concat(declarations, "\n") .. "\n" .. table.concat(assignments, "\n")
    local elapsedTime = tick() - startTime
    
    return code, elapsedTime
end

return StealGui
