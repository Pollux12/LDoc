
-- luacheck: ignore 111

--[[--
Global hooks for general use.

Plugin hooks are regular hooks that can be used in your plugin with `PLUGIN:HookName(args)` or elsewhere with `hook.Add("HookName", function(args) end)`.
Every function in a plugin starting with PLUGIN: will automatically become a hook, and can be called with hook.Add.
This means you should probably be mindful of duplicate names, unless it makes sense for a hook to call them all at once.
For example, if you have multiple plugins using a function called "HandlePlayer", using hook.Call("HandlePlayer", ...) will call all of them.

]]
-- @hooks Plugin


--- @realm server
function LoadData()
end

--- @realm server
function SaveData()
end
