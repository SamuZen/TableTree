-- ### Roblox Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Class = {
    toTree: (name: string, parent: Instance, data: {any}) -> ClassInstance,
    toTable: (root: Folder) -> table,
    waitTreeSync: (name: string, parent: Instance) -> ClassInstance,
    waitPlayerTreeSync: (player: Player, name: string?) -> ClassInstance,
}
export type PrivateClass = {
    create: (nil, data: {any}, name: string, parent: Instance) -> Folder,
}
export type PrivateClassInstance = {
    mapTables: {[string]: Folder},
}
export type ClassInstance = {
    name: string,
    root: Folder,

    set: (nil, path: string, key: string, newValue: any) -> nil,
    get: (nil, path: string) -> any,
    add: (nil, path: string, key: string, value: any) -> nil,
    remove: (nil, path: string, key: string) -> nil,

    increment: (nil, path: string, value: number) -> nil,
    delete: (nil, fullPath: string) -> nil,

    keepUpdated: (nil, fullPath: string, callback: () -> nil) -> RBXScriptConnection,
    onChanged: (nil, path: string, callback:( string, any) -> nil) -> RBXScriptConnection,

    destroy: () -> nil,
    log: () -> nil,
}
--[=[
	@class TableTree
	Main Class.
]=]
local TableTree: Class | PrivateClass | ClassInstance | PrivateClassInstance = {}
TableTree.__index = TableTree

local sharedTrees = {}
local folder

-- ### Class

--[=[
	@within TableTree
	Create a new folder structure with attributes

	@param name string -- The name of the folder
	@param parent Instance -- The parent of the folder
    @param data {any} -- The data to create
]=]
function TableTree.toTree(name, parent, data)
    local self = setmetatable({}, TableTree)

    if parent == nil then
        parent = folder
        sharedTrees[name] = self
    end

    self.name = name
    self.mapTables = {}
    self.root = self:createTree(name, parent, data)

    return self
end

function TableTree.toTable(instance)
    local self = setmetatable({}, TableTree)

    self.name = instance.Name
    self.mapTables = {}
    self.root = instance
    self:createFromTree(instance)

    return self
end

function TableTree.waitPlayerTree(player: Player, name: string)
    if name == nil then name = "_replicationFolder" end
    return TableTree.waitTreeSync(name, player)
end

function TableTree.waitTreeSync(name, parent)
    local tree = sharedTrees[name]
    local addToShared = false

    if tree == nil and parent == nil then
        -- parentless do not exist yet
        parent = folder
        addToShared = true
    end

    if parent ~= nil then
        local root = parent:FindFirstChild(name)
        if root == nil then
            root = parent:WaitForChild(name)
            if sharedTrees[name] ~= nil then
                return sharedTrees[name]
            end

        end
        local newTree = TableTree.toTable(root)
        if addToShared then
            sharedTrees[name] = newTree
        end
        return newTree
    end

    return tree
end

-- ### Instance

-- values

function TableTree:get(fullPath)
    local splitted = self:splitFullPath(fullPath)
    return self:getPathWithKey(splitted.path, splitted.key)
end

function TableTree:set(fullPath, newValue)
    local splitted = self:splitFullPath(fullPath)
    self:setPathKeyValue(splitted.path, splitted.key, newValue)
end

function TableTree:increment(fullPath, value)
    assert(value ~= nil, "Value needs to be different of nil")
	assert(type(value) == "number", "Value needs to be a number")
    self:set(self:get(fullPath) + value)
end

function TableTree:remove(path, key)
    self.setPathKeyValue(path, key, nil)
end

function TableTree:keepUpdated(fullPath: string, callback: (any) -> nil)
    local splitted = self:splitFullPath(fullPath)

    local folder = self.mapTables[splitted.path]
    assert(folder, "There is no structure with name " .. fullPath)

    callback(folder:GetAttribute(splitted.key))
    return folder:GetAttributeChangedSignal(splitted.key):Connect(function()
        callback(folder:GetAttribute(splitted.key))
    end)
end

-- table
function TableTree:getTable(path: string)
    local folder = self.mapTables[path]
    assert(folder, 'failed to find folder with path: ' .. path)
    return folder:GetAttributes()
end

-- geral

function TableTree:delete(fullPath)
    local folder = self.mapTables[fullPath]
    if folder ~= nil then
        folder:Destroy()
        return
    end

    local splitted = self:splitFullPath(fullPath)
    local folder = self.mapTables[splitted.path]
    assert(folder, "Could not find structure to delete with path " .. fullPath)

    folder:SetAttribute(splitted.key, nil)
end

function TableTree:onChanged(path: string, callback: (string, any) -> nil)
    local folder = self.mapTables[path]
    return folder.AttributeChanged:Connect(function(attribute)
        callback(attribute, folder:GetAttribute(attribute))
    end)
end

--

function TableTree:Destroy()
    self.mapTables = nil
    self.root:Destroy()
end

-- Utils
function TableTree:log()
    for path, folder in self.mapTables do
        warn(path)
        local attributes = folder:GetAttributes()
        for key, value in attributes do
            print(key, value)
        end
    end
end

-- ### Class Private

function TableTree:createTree(name, parent, data)
    local root = Instance.new("Folder")
    root.Name = name

    local path = ""
    local function writeTable(self, path, array, folder)

        if folder:GetFullName() ~= root:GetFullName() then
            if path == "" then
                path = folder.Name
            else
                path = path .. "." .. folder.Name
            end
            self.mapTables[path] = folder
        end

		for i, j in pairs(array) do
			if type(j) == "table" then
				local newFolder = Instance.new("Folder")
				newFolder.Name = i
				writeTable(self, path, j, newFolder)
				newFolder.Parent = folder
			else
				folder:SetAttribute(i, j)
			end
		end
	end
	writeTable(self, path, data, root)

    local existing = parent:FindFirstChild(name)
    if existing ~= nil then existing:Destroy() end

    root.Parent = parent
    return root
end

function TableTree:createFromTree(root)
    local rootFullName = root:GetFullName()
    local fullNameSize = string.len(rootFullName)
	
    for _, child in root:GetDescendants() do
        if child:IsA("Folder") then
            local childFullName = child:GetFullName()
			local childPath = string.sub(childFullName, fullNameSize + 2)
            self.mapTables[childPath] = child
        end
    end
end

function TableTree:splitFullPath(fullPath)
    local lastDotIndex = string.find(fullPath, ".[^.]*$")
    return {
        path = string.sub(fullPath, 1, lastDotIndex - 1),
        key = string.sub(fullPath, lastDotIndex + 1),
        lastDotIndex = lastDotIndex,
    }
end

function TableTree:setPathKeyValue(path, key, newValue)
    local folder = self.mapTables[path]
    assert(folder, "There is no structure with name " .. path)

    if typeof(newValue) == "table" then
        self:createTree(key, folder, newValue)
    else
        folder:SetAttribute(key, newValue)
    end
end

function TableTree:getPathWithKey(path, key)
    local folder = self.mapTables[path]
    assert(folder, "There is no structure with name " .. path)
    return folder:GetAttribute(key)
end

-- ### Initial Setup
if RunService:IsServer() then
    folder = ReplicatedStorage:FindFirstChild("tableTree")
    if folder == nil then
        folder = Instance.new("Folder")
        folder.Name = 'tableTree'
        folder.Parent = ReplicatedStorage
    end
else
    folder = ReplicatedStorage:WaitForChild("tableTree", 2)
    if folder == nil then
        folder = Instance.new("Folder")
        folder.Name = 'tableTree'
        folder.Parent = ReplicatedStorage
    end
end

-- ### Load & Save parentless tabletress
local function load(root)
    if sharedTrees[root.Name] ~= nil then return end
    local tree = TableTree.toTable(root)
    sharedTrees[root.Name] = tree
end

for _, child in folder:GetChildren() do
    load(child)
end
folder.ChildAdded:Connect(function(child)
    task.defer(function()
        load(child)
    end)
end)

return TableTree :: Class