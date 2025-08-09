--- Test file for LuaLS annotation parsing
--- @module luals_test

local M = {}

--- A simple function with LuaLS annotations
--- @param name string The name of the person
--- @param age integer The age of the person
--- @param active boolean Whether the person is active
--- @return string The formatted greeting
function M.greet(name, age, active)
    return string.format("Hello %s, age %d, active: %s", name, age, tostring(active))
end

--- Function with complex types
--- @param items table[] Array of item tables
--- @param callback function The callback function
--- @param options? table Optional configuration table
--- @return boolean Success status
--- @return string? Error message if failed
function M.processItems(items, callback, options)
    -- Implementation here
    return true
end

--- A class definition with field functions
--- @class Player
--- @field id integer The player's unique ID
--- @field name string The player's name
--- @field health number Current health points
--- @field GetName fun(self: Player): string Gets the player's name
--- @field SetName fun(self: Player, name: string): Player Sets the player's name
--- @field TakeDamage fun(self: Player, amount: number): boolean Deals damage to player
--- @field IsAlive fun(self: Player): boolean Checks if player is alive
local Player = {}

--- Create a new player instance
--- @param name string The player's name
--- @param health? number Initial health (default 100)
--- @return Player The new player instance
function Player.new(name, health)
    local player = setmetatable({}, Player)
    player.name = name
    player.health = health or 100
    player.id = math.random(1000, 9999)
    return player
end

--- Get the player's name
--- @return string The player's name
function Player:GetName()
    return self.name
end

--- Set the player's name
--- @param name string The new name
--- @return Player Returns self for chaining
function Player:SetName(name)
    self.name = name
    return self
end

--- Deal damage to the player
--- @param amount number The damage amount
--- @return boolean True if player is still alive
function Player:TakeDamage(amount)
    self.health = self.health - amount
    return self.health > 0
end

--- Check if player is alive
--- @return boolean True if health > 0
function Player:IsAlive()
    return self.health > 0
end

--- Generic function example
--- @generic T
--- @param value T The input value
--- @return T The same value
function M.identity(value)
    return value
end

--- Function with overloads
--- @overload fun(x: number): number
--- @overload fun(x: string): string
--- @param x any The input value
--- @return any The processed value
function M.process(x)
    return x
end

--- Enum example
--- @enum Color
local Color = {
    RED = 1,
    GREEN = 2,
    BLUE = 3
}

--- Function using enum
--- @param color Color The color to use
--- @return string The color name
function M.getColorName(color)
    local names = { [1] = "red", [2] = "green", [3] = "blue" }
    return names[color] or "unknown"
end

--- Custom realm annotation (should auto-detect from filename)
--- @realm client
--- @param message string The message to display
function M.showClientMessage(message)
    -- Client-side only function
    print("Client: " .. message)
end

--- Async function example
--- @async
--- @param url string The URL to fetch
--- @return string The response data
function M.fetchData(url)
    -- Async implementation
    return "data"
end

--- Vararg function
--- @vararg string
--- @param ... string Multiple string arguments
--- @return string Concatenated result
function M.concat(...)
    return table.concat({...}, " ")
end

--- Meta function
--- @meta
--- @param obj table The object to enhance
--- @return table The enhanced object
function M.enhance(obj)
    return setmetatable(obj, {})
end

--- Operator overload
--- @operator add(Vector): Vector
--- @class Vector
--- @field x number
--- @field y number
local Vector = {}

--- Create a new vector
--- @param x number X component
--- @param y number Y component
--- @return Vector New vector instance
function Vector.new(x, y)
    return setmetatable({x = x, y = y}, Vector)
end

--- Add two vectors
--- @param other Vector The other vector
--- @return Vector The sum vector
function Vector:__add(other)
    return Vector.new(self.x + other.x, self.y + other.y)
end

M.Player = Player
M.Color = Color
M.Vector = Vector

return M
