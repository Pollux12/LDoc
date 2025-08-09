--- Mixed annotation test file
--- Tests both LuaLS and LDoc annotations in the same file
--- @module mixed_test

local M = {}

--- LuaLS style function
--- @param name string The person's name
--- @param age integer The person's age
--- @return string Formatted greeting
function M.lualsGreeting(name, age)
    return string.format("Hello %s, you are %d years old", name, age)
end

----
-- LDoc style function
-- @tparam string name The person's name
-- @tparam int age The person's age
-- @treturn string Formatted greeting
function M.ldocGreeting(name, age)
    return string.format("Hi %s, age %d", name, age)
end

--- LuaLS class with field functions
--- @class Item
--- @field id integer Unique identifier
--- @field name string Item name
--- @field GetCost fun(self: Item): number Gets the item cost
--- @field SetCost fun(self: Item, cost: number): Item Sets the item cost
local Item = {}

----
-- LDoc style class
-- @type Vehicle
-- @field make string The vehicle make
-- @field model string The vehicle model

local Vehicle = {}

--- Mixed parameter styles in same function (should prioritize LuaLS)
--- @param itemId string The item identifier
-- @tparam number quantity The quantity (this should be ignored in favor of LuaLS)
--- @param quantity integer The quantity to purchase
--- @return boolean Success status
function M.purchaseItem(itemId, quantity)
    return true
end

----
-- Function with only LDoc annotations
-- @string message The message to log
-- @bool verbose Whether to log verbosely
function M.logMessage(message, verbose)
    if verbose then
        print("VERBOSE: " .. message)
    else
        print(message)
    end
end

--- Function with realm detection (filename starts with cl_)
--- @param data table The data to send
--- @return boolean Success status
function M.sendToServer(data)
    -- This should auto-detect as client realm
    return true
end

M.Item = Item
M.Vehicle = Vehicle

return M
