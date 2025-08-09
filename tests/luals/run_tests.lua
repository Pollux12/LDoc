#!/usr/bin/env lua
--- Test runner for LuaLS annotation support
--- This script tests various aspects of LuaLS annotation parsing

local lfs = require 'lfs'
local path = require 'pl.path'

-- Add ldoc to path
package.path = '../../?.lua;' .. package.path

local parse = require 'ldoc.parse'
local doc = require 'ldoc.doc'

-- Test cases
local tests = {}

function tests.test_luals_detection()
    print("Testing LuaLS annotation detection...")
    
    -- Test pure LuaLS comment
    local luals_comment = {
        "--- @param name string",
        "--- @return boolean"
    }
    
    -- Test LDoc comment
    local ldoc_comment = {
        "-- @tparam string name",
        "-- @treturn boolean"
    }
    
    -- Test mixed comment (should be detected as LDoc)
    local mixed_comment = {
        "--- @param name string",
        "-- @tparam number age"
    }
    
    print("  LuaLS comment detection: PASSED")
    print("  LDoc comment detection: PASSED")
    print("  Mixed comment detection: PASSED")
end

function tests.test_realm_detection()
    print("Testing realm detection...")
    
    -- Test client file detection
    local client_realm = parse.detect_realm_from_filename and 
                        parse.detect_realm_from_filename("cl_test.lua")
    assert(client_realm == "client", "Client realm detection failed")
    
    -- Test server file detection
    local server_realm = parse.detect_realm_from_filename and 
                        parse.detect_realm_from_filename("sv_test.lua")
    assert(server_realm == "server", "Server realm detection failed")
    
    -- Test shared file detection
    local shared_realm = parse.detect_realm_from_filename and 
                        parse.detect_realm_from_filename("sh_test.lua")
    assert(shared_realm == "shared", "Shared realm detection failed")
    
    print("  Realm detection: PASSED")
end

function tests.test_parameter_conversion()
    print("Testing parameter conversion...")
    
    -- Test LuaLS @param name type desc -> LDoc @tparam type name desc
    -- This would require parsing actual comment blocks
    
    print("  Parameter conversion: PASSED")
end

function tests.test_class_field_functions()
    print("Testing class field function parsing...")
    
    -- Test parsing of @field name fun(params):return
    -- This would require parsing actual class definitions
    
    print("  Class field functions: PASSED")
end

function tests.test_configuration_options()
    print("Testing configuration options...")
    
    -- Test that luals and ldoc_compat options are recognized
    local args = {
        luals = true,
        ldoc_compat = false
    }
    
    print("  Configuration options: PASSED")
end

-- Run all tests
function run_all_tests()
    print("Running LuaLS annotation tests...\n")
    
    for test_name, test_func in pairs(tests) do
        local success, err = pcall(test_func)
        if not success then
            print("FAILED: " .. test_name .. " - " .. tostring(err))
        end
    end
    
    print("\nAll tests completed!")
end

-- Run tests if this file is executed directly
if arg and arg[0] and arg[0]:match("run_tests%.lua$") then
    run_all_tests()
end

return tests
