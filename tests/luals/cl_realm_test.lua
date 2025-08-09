--- Client-side realm test file
--- This file should auto-detect as client realm due to cl_ prefix
--- @module cl_realm_test

local M = {}

--- Client-side function (should auto-detect realm)
--- @param message string The message to display
function M.showNotification(message)
    -- Client-side notification
    print("CLIENT: " .. message)
end

--- Function with explicit realm override
--- @realm server
--- @param data table Data to process on server
function M.processOnServer(data)
    -- This should be marked as server despite being in cl_ file
    return data
end

--- Function without explicit realm (should inherit client from filename)
--- @param x number X coordinate
--- @param y number Y coordinate
--- @return boolean Success status
function M.drawAt(x, y)
    -- Client-side drawing
    return true
end

return M
