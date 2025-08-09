-- parsing code for doc comments

local utils = require 'pl.utils'
local List = require 'pl.List'
-- local Map = require 'pl.Map'
local stringio = require 'pl.stringio'
local lexer = require 'ldoc.lexer'
local tools = require 'ldoc.tools'
local doc = require 'ldoc.doc'
local Item, File = doc.Item, doc.File
local unpack = utils.unpack

------ Parsing the Source --------------
-- This uses the lexer from PL, but it should be possible to use Peter Odding's
-- excellent Lpeg based lexer instead.

local parse = {}

local tnext, append = lexer.skipws, table.insert

-- a pattern particular to LuaDoc tag lines: the line must begin with @TAG,
-- followed by the value, which may extend over several lines.
local luadoc_tag = '^%s*@(%w+)'
local luadoc_tag_value = luadoc_tag .. '(.*)'
local luadoc_tag_mod_and_value = luadoc_tag .. '%[([^%]]*)%](.*)'

-- assumes that the doc comment consists of distinct tag lines
local function parse_at_tags(text)
   local lines = stringio.lines(text)
   local preamble, line = tools.grab_while_not(lines, luadoc_tag)
   local tag_items = {}
   local follows
   while line do
      local tag, mod_string, rest = line:match(luadoc_tag_mod_and_value)
      if not tag then tag, rest = line:match(luadoc_tag_value) end
      local modifiers
      if mod_string then
         modifiers = {}
         for x in mod_string:gmatch "[^,]+" do
            local k, v = x:match "^([^=]+)=(.*)$"
            if not k then k, v = x, true end -- wuz x, x
            modifiers[k] = v
         end
      end
      -- follows: end of current tag
      -- line: beginning of next tag (for next iteration)
      follows, line = tools.grab_while_not(lines, luadoc_tag)
      append(tag_items, { tag, rest .. '\n' .. follows, modifiers })
   end
   return preamble, tag_items
end

-- Detect if a comment block uses LuaLS annotation style
-- LuaLS uses only triple dashes (---) and specific annotation patterns
-- LDoc can use double or triple dashes and uses different @ tag patterns
local function detect_annotation_style(comment_lines)
   local has_triple_dash_only = true
   local has_double_dash = false
   local has_luals_tags = false
   local has_ldoc_tags = false

   for _, line in ipairs(comment_lines) do
      -- Detect comment dash styles
      if line:match('^%-%-[^%-]') then
         has_double_dash = true
         has_triple_dash_only = false
      elseif line:match('^%-%-%-%-+') then
         has_triple_dash_only = false
      end

      -- LuaLS-style tags we care about
      if line:match('@param%s+%S+%s+%S+') or line:match('@return%s+%S+') or
          line:match('@field%s+%S+%s+%S+') or line:match('@class%s+%S+') or
          line:match('@overload%s+') or line:match('@realm%s+') or
          line:match('@alias%s+') or line:match('@module%s+') then
         has_luals_tags = true
      end

      -- Classic LDoc tags that should force LDoc mode
      if line:match('@tparam%s+') or line:match('@treturn%s+') or
          line:match('@string%s+') or line:match('@number%s+') or
          line:match('@bool%s+') or line:match('@tab%s+') or
          line:match('@entity%s+') or line:match('@player%s+') or
          line:match('@rnum%s+') or line:match('@warn%s+') or
          line:match('@code%s+') or line:match('@char%s+') or
          line:match('@table%s+') then
         has_ldoc_tags = true
      end
   end

   -- Priority: explicit LDoc tags > explicit LuaLS tags > heuristic fallback
   if has_ldoc_tags then
      return 'ldoc'
   elseif has_luals_tags then
      return 'luals'
   elseif has_triple_dash_only and not has_double_dash then
      return 'luals'
   else
      return 'ldoc'
   end
end

-- Parse LuaLS-style annotations
-- LuaLS uses @tag name type description format (different from LDoc's @tparam type name description)
-- In pure LuaLS mode, ignore unknown/LDoc-specific tags gracefully
local function parse_luals_tags(text, args)
   local lines = stringio.lines(text)
   local preamble, line = tools.grab_while_not(lines, luadoc_tag)
   local tag_items = {}
   local follows

   -- Define LuaLS tags that are relevant for documentation
   -- Exclude code-analysis-only tags like @type, @diagnostic, @cast, @generic, etc.
   -- TODO: Add to config instead of here
   local luals_supported_tags = {
      param = true,
      ['return'] = true,
      field = true,
      class = true,
      table = true,
      overload = true,
      operator = true,
      vararg = true,
      async = true,
      enum = true,
      realm = true,
      alias = true,
      module = true,
      see = true,
      usage = true,
      deprecated = true,
      internal = true,
      ['function'] = true
   }

   -- Define LuaLS tags that should be ignored (code analysis only)
   -- TODO: Add to config instead of here
   local luals_ignored_tags = {
      type = true,       -- Variable type annotations
      diagnostic = true, -- Diagnostic control
      cast = true,       -- Type casting
      generic = true,    -- Generic type parameters (usually not needed in docs)
      meta = true,       -- Meta information
      nodiscard = true,  -- Return value usage hints
      version = true,    -- Version annotations
      since = true,      -- Version since annotations
      package = true,    -- Package visibility
      protected = true,  -- Protected visibility
      private = true,    -- Private visibility
   }

   -- Helper: split a LuaLS function type (fun(...):Ret<...>) from trailing description, tolerating spaces inside generics
   local function split_fun_and_desc(s)
      local start = s:find('%f[%a]fun%(')
      if not start then return nil end
      local i = start + 4 -- position after 'fun('
      local depth = 1
      while i <= #s and depth > 0 do
         local ch = s:sub(i, i)
         if ch == '(' then
            depth = depth + 1
         elseif ch == ')' then
            depth = depth - 1
         end
         i = i + 1
      end
      if depth ~= 0 then return nil end
      -- i now points just after closing ')'
      local j = i
      if s:sub(j, j) == ':' then
         j = j + 1
         local angle = 0
         while j <= #s do
            local ch = s:sub(j, j)
            if ch == '<' then
               angle = angle + 1
            elseif ch == '>' then
               angle = math.max(0, angle - 1)
            elseif ch == ' ' and angle == 0 then
               -- Stop type at first space not inside angle brackets
               break
            end
            j = j + 1
         end
      end
      local type_part = s:sub(start, j - 1):match('^%s*(.-)%s*$')
      local desc = s:sub(j):match('^%s*(.-)%s*$')
      if desc == '' then desc = nil end
      return type_part, desc
   end

   while line do
      local tag, rest = line:match(luadoc_tag_value)
      if tag then
         -- Check if this tag should be ignored (code analysis only)
         if luals_ignored_tags[tag] then
            -- Always ignore these tags regardless of mode
            follows, line = tools.grab_while_not(lines, luadoc_tag)
            -- Continue to next tag without adding this one
         elseif not luals_supported_tags[tag] then
            -- Check if this is an unsupported LuaLS tag
            if args and args.luals == true and args.ldoc_compat ~= true then
               -- Skip unsupported tags silently in pure LuaLS mode
               follows, line = tools.grab_while_not(lines, luadoc_tag)
               -- Continue to next tag without adding this one
            else
               -- In compatibility mode, treat as unknown tag
               follows, line = tools.grab_while_not(lines, luadoc_tag)
               append(tag_items, { tag, rest .. '\n' .. follows })
            end
            -- Handle LuaLS-specific tag parsing
         elseif tag == 'param' then
            -- LuaLS: @param name TYPE [# desc]
            local name, type_and_desc = rest:match('^%s*([%w_%.:%?%.%.%.]+)%s+(.*)')
            if name and type_and_desc then
               local is_opt = false
               if name:match('%?$') then
                  is_opt = true
                  name = name:gsub('%?$', '')
               end
               -- Prefer '# desc'; else try to split smartly into type and desc
               local type_part, desc = type_and_desc:match('^%s*(.-)%s*#%s*(.*)$')
               if not type_part then
                  -- function type like fun(...) or fun(...):Ret (with generics/spaces)
                  local T, D = split_fun_and_desc(type_and_desc)
                  if T then
                     type_part, desc = T, D
                  else
                     -- fallback: first non-space token as type
                     local t_simple, d2 = type_and_desc:match('^%s*([^%s]+)%s+(.*)$')
                     if t_simple then
                        type_part = t_simple
                        desc = d2
                     else
                        type_part = (type_and_desc:gsub('^%s*(.-)%s*$', '%1'))
                        desc = nil
                     end
                  end
               end
               -- Clean up description if needed
               if desc and desc:match('^%s*#%s*') then
                  desc = desc:gsub('^%s*#%s*', '')
               end
               rest = name .. ' ' .. (desc or '')
               follows, line = tools.grab_while_not(lines, luadoc_tag)
               local mods = { type = type_part }
               if is_opt then mods.opt = true end
               append(tag_items, { 'param', rest .. '\n' .. follows, mods })
            else
               -- Malformed param
               follows, line = tools.grab_while_not(lines, luadoc_tag)
               if args and args.luals == true and args.ldoc_compat ~= true then
                  -- skip
               else
                  append(tag_items, { 'param', rest .. '\n' .. follows })
               end
            end
         elseif tag == 'return' then
            -- LuaLS: @return TYPE [# desc]
            local type_and_desc = rest:match('^%s*(.*)')
            if type_and_desc then
               local type_part, desc = type_and_desc:match('^%s*(.-)%s*#%s*(.*)$')
               if not type_part then
                  type_part = (type_and_desc:gsub('^%s*(.-)%s*$', '%1'))
                  desc = nil
               end
               if type_part and type_part ~= '' then
                  if desc and desc:match('^%s*#%s*') then
                     desc = desc:gsub('^%s*#%s*', '')
                  end
                  follows, line = tools.grab_while_not(lines, luadoc_tag)
                  append(tag_items, { 'return', (desc or '') .. '\n' .. follows, { type = type_part } })
               else
                  follows, line = tools.grab_while_not(lines, luadoc_tag)
                  append(tag_items, { 'return', rest .. '\n' .. follows })
               end
            else
               follows, line = tools.grab_while_not(lines, luadoc_tag)
               append(tag_items, { 'return', rest .. '\n' .. follows })
            end
         elseif tag == 'field' then
            -- Support BOTH syntaxes here so auto-detection never breaks fields:
            -- 1) LuaLS:   @field name TYPE [# desc]
            -- 2) LDoc:    @field[type=TYPE,opt] name desc
            local display_type, name, desc

            -- First, detect classic LDoc bracketed modifiers form
            local mods_str, rest_after_mods = rest:match('^%s*%[([^%]]+)%]%s*(.*)$')
            if mods_str then
               -- Parse modifiers like type=..., opt, readonly, etc.
               local mods = {}
               for x in mods_str:gmatch('[^,]+') do
                  local k, v = x:match('^%s*([^=]+)%s*=%s*(.-)%s*$')
                  if not k then k, v = x:gsub('^%s+', ''):gsub('%s+$', ''), true end
                  mods[k] = v
               end
               name, desc = rest_after_mods:match('^%s*([%w_%.]+)%s*(.*)$')
               if name then
                  display_type = mods.type or ''
                  follows, line = tools.grab_while_not(lines, luadoc_tag)
                  -- Normalize function signatures for display consistency
                  if type(display_type) == 'string' and display_type:match('^%s*fun%b%(%).*$') then
                     append(tag_items, { 'function_field', name .. "\t" .. display_type .. '\n' .. '' })
                     display_type = 'function'
                  end
                  append(tag_items,
                     { 'tfield', (display_type or '') .. ' ' .. name .. ' ' .. (desc or '') .. '\n' .. follows })
               else
                  -- Malformed; fall back to generic handling
                  follows, line = tools.grab_while_not(lines, luadoc_tag)
                  append(tag_items, { 'field', rest .. '\n' .. follows })
               end
            else
               -- LuaLS-style @field
               local name1, type_and_desc = rest:match('^%s*(%S+)%s+(.*)')
               if name1 and type_and_desc then
                  -- Prefer '# desc'; else try to split smartly into type and desc
                  local type_part, d = type_and_desc:match('^%s*(.-)%s*#%s*(.*)$')
                  if not type_part then
                     -- function type like fun(...) or fun(...):Ret (with generics/spaces)
                     local T, D = split_fun_and_desc(type_and_desc)
                     if T then
                        type_part, d = T, D
                     else
                        local t_simple, d2 = type_and_desc:match('^%s*([^%s]+)%s+(.*)$')
                        if t_simple then
                           type_part = t_simple
                           d = d2
                        else
                           type_part = (type_and_desc:gsub('^%s*(.-)%s*$', '%1'))
                           d = nil
                        end
                     end
                  end
                  if type_part then
                     if d and d:match('^%s*#%s*') then d = d:gsub('^%s*#%s*', '') end
                     follows, line = tools.grab_while_not(lines, luadoc_tag)
                     local disp = type_part
                     if type_part:match('^%s*fun%b%(%).*$') then
                        append(tag_items, { 'function_field', name1 .. "\t" .. type_part .. '\n' .. '' })
                        disp = 'function'
                     end
                     append(tag_items, { 'tfield', disp .. ' ' .. name1 .. ' ' .. (d or '') .. '\n' .. follows })
                  else
                     follows, line = tools.grab_while_not(lines, luadoc_tag)
                     append(tag_items, { 'field', rest .. '\n' .. follows })
                  end
               else
                  follows, line = tools.grab_while_not(lines, luadoc_tag)
                  append(tag_items, { 'field', rest .. '\n' .. follows })
               end
            end
         elseif tag == 'class' then
            -- LuaLS: @class [(exact)] <name>[: <parent>[, <parent>...]]
            -- Record class name, optional exact flag, and zero-or-more parents.
            local text = (rest or '')
            local exact = text:find('%(exact%)') ~= nil
            text = text:gsub('%(exact%)', '')
            -- name and optional colon-separated parents
            local cname, parents = text:match('^%s*([^:,%s]+)%s*:%s*(.+)$')
            if not cname then
               cname = text:match('^%s*([^:,%s]+)%s*$')
               parents = nil
            end
            follows, line = tools.grab_while_not(lines, luadoc_tag)
            if cname and cname ~= '' then
               append(tag_items, { 'class', cname .. '\n' .. follows })
               if exact then
                  append(tag_items, { 'class_exact', 'true\n' .. '' })
               end
               if parents and parents ~= '' then
                  -- split on commas, allowing dotted names and spaces
                  for p in parents:gmatch('[^,]+') do
                     local parent = (p:gsub('^%s*(.-)%s*$', '%1'))
                     if parent ~= '' then
                        append(tag_items, { 'extends', parent .. '\n' .. '' })
                     end
                  end
               end
            else
               append(tag_items, { 'class', rest .. '\n' .. follows })
            end
         elseif tag == 'table' then
            -- Classic LDoc: @table Name (allow inside LuaLS mode for compatibility)
            follows, line = tools.grab_while_not(lines, luadoc_tag)
            append(tag_items, { 'table', rest .. '\n' .. follows })
         elseif tag == 'generic' then
            -- LuaLS: @generic T - handle generics
            follows, line = tools.grab_while_not(lines, luadoc_tag)
            append(tag_items, { 'generic', rest .. '\n' .. follows })
         elseif tag == 'overload' then
            -- LuaLS: @overload fun(params):return
            follows, line = tools.grab_while_not(lines, luadoc_tag)
            append(tag_items, { 'overload', rest .. '\n' .. follows })
         elseif tag == 'operator' then
            -- LuaLS: @operator
            follows, line = tools.grab_while_not(lines, luadoc_tag)
            append(tag_items, { 'operator', rest .. '\n' .. follows })
         elseif tag == 'vararg' then
            -- LuaLS: @vararg
            follows, line = tools.grab_while_not(lines, luadoc_tag)
            append(tag_items, { 'vararg', rest .. '\n' .. follows })
         elseif tag == 'meta' then
            -- LuaLS: @meta
            follows, line = tools.grab_while_not(lines, luadoc_tag)
            append(tag_items, { 'meta', rest .. '\n' .. follows })
         elseif tag == 'async' then
            -- LuaLS: @async
            follows, line = tools.grab_while_not(lines, luadoc_tag)
            append(tag_items, { 'async', rest .. '\n' .. follows })
         elseif tag == 'enum' then
            follows, line = tools.grab_while_not(lines, luadoc_tag)
            append(tag_items, { 'enum', rest .. '\n' .. follows })
         elseif tag == 'realm' then
            -- Custom LuaLS extension: @realm
            follows, line = tools.grab_while_not(lines, luadoc_tag)
            append(tag_items, { 'realm', rest .. '\n' .. follows })
         elseif tag == 'alias' then
            -- LuaLS: @alias
            follows, line = tools.grab_while_not(lines, luadoc_tag)
            append(tag_items, { 'alias', rest .. '\n' .. follows })
         elseif tag == 'module' then
            -- LuaLS: @module
            follows, line = tools.grab_while_not(lines, luadoc_tag)
            append(tag_items, { 'module', rest .. '\n' .. follows })
         else
            -- Handle other tags normally
            follows, line = tools.grab_while_not(lines, luadoc_tag)
            append(tag_items, { tag, rest .. '\n' .. follows })
         end
      else
         -- Skip malformed lines
         follows, line = tools.grab_while_not(lines, luadoc_tag)
      end
   end

   return preamble, tag_items
end

-- Detect realm from filename for Garry's Mod/CityRP files
local function detect_realm_from_filename(filename)
   local basename = filename:match('([^/\\]+)$') or filename
   if basename:match('^cl_') then
      return 'client'
   elseif basename:match('^sv_') then
      return 'server'
   elseif basename:match('^sh_') then
      return 'shared'
   else
      return 'shared' -- default to shared instead of nil
   end
end

--local colon_tag = '%s*(%a+):%s'
local colon_tag = '%s*(%S-):%s'
local colon_tag_value = colon_tag .. '(.*)'

local function parse_colon_tags(text)
   local lines = stringio.lines(text)
   local preamble, line = tools.grab_while_not(lines, colon_tag)
   local tag_items = {}
   while line do
      local tag, rest = line:match(colon_tag_value)
      follows, line = tools.grab_while_not(lines, colon_tag)
      local value = rest .. '\n' .. follows
      if tag:match '^[%?!]' then
         tag = tag:gsub('^!', '')
         value = tag .. ' ' .. value
         tag = 'tparam'
      end
      append(tag_items, { tag, value })
   end
   return preamble, tag_items
end

-- Tags are stored as an ordered multi map from strings to strings
-- If the same key is used, then the value becomes a list
local Tags = {}
Tags.__index = Tags

function Tags.new(t, name)
   local class
   if name then
      class = t
      t = {}
   end
   t._order = List()
   local tags = setmetatable(t, Tags)
   if name then
      tags:add('ldoc_class', class)
      tags:add('name', name)
   end
   return tags
end

function Tags:add(tag, value, modifiers)
   if modifiers then -- how modifiers are encoded
      value = { value, modifiers = modifiers }
   end
   local ovalue = self:get(tag)
   if ovalue then
      ovalue:append(value)
      value = ovalue
   end
   rawset(self, tag, value)
   if not ovalue then
      self._order:append(tag)
   end
end

function Tags:get(tag)
   local ovalue = rawget(self, tag)
   if ovalue then -- previous value?
      if getmetatable(ovalue) ~= List then
         ovalue = List { ovalue }
      end
      return ovalue
   end
end

function Tags:iter()
   return self._order:iter()
end

local function comment_contains_tags(comment, args)
   if args.colon then
      if type(comment) == 'table' then
         local comment_str = table.concat(comment, '\n')
         return comment_str:find ': '
      else
         return comment:find ': '
      end
   else
      -- Handle both string and table comment formats
      local comment_str, comment_lines
      if type(comment) == 'table' then
         comment_str = table.concat(comment, '\n')
         comment_lines = comment
      else
         comment_str = comment
         comment_lines = { comment }
      end

      -- If user forces only one style, constrain detection accordingly
      if args.only_luals == true then
         local has_luals_tags = false
         for _, line in ipairs(comment_lines) do
            if line:match('@param%s+%S+%s+%S+') or line:match('@return%s+%S+') or
                line:match('@field%s+%S+%s+%S+') or line:match('@class%s+%S+') or
                line:match('@overload%s+') or line:match('@realm%s+') or
                line:match('@alias%s+') or line:match('@module%s+') then
               has_luals_tags = true; break
            end
         end
         return has_luals_tags
      end
      if args.only_ldoc == true then
         -- only consider classic LDoc tags
         local has_ldoc_tags = false
         for _, line in ipairs(comment_lines) do
            if line:match('@tparam%s+') or line:match('@treturn%s+') or
                line:match('@string%s+') or line:match('@number%s+') or
                line:match('@bool%s+') or line:match('@tab%s+') or
                line:match('@entity%s+') or line:match('@player%s+') or
                line:match('@rnum%s+') or line:match('@warns?%s+') or
                line:match('@code%s+') or line:match('@char%s+') or
                line:match('@function%s+') or line:match('@field%s+') or
                line:match('@table%s+') then
               has_ldoc_tags = true; break
            end
         end
         return has_ldoc_tags
      end

      -- In pure LuaLS mode, still accept explicit LDoc blocks (e.g. @table)
      if args.luals == true and args.ldoc_compat ~= true then
         local has_luals_tags = false
         local has_ldoc_tags = false
         for _, line in ipairs(comment_lines) do
            if line:match('@param%s+%S+%s+%S+') or line:match('@return%s+%S+') or
                line:match('@field%s+%S+%s+%S+') or line:match('@class%s+%S+') or
                line:match('@overload%s+') or line:match('@realm%s+') or
                line:match('@alias%s+') or line:match('@module%s+') then
               has_luals_tags = true
            end
            if line:match('@tparam%s+') or line:match('@treturn%s+') or
                line:match('@string%s+') or line:match('@number%s+') or
                line:match('@bool%s+') or line:match('@tab%s+') or
                line:match('@entity%s+') or line:match('@player%s+') or
                line:match('@rnum%s+') or line:match('@warns?%s+') or
                line:match('@code%s+') or line:match('@char%s+') or
                line:match('@function%s+') or line:match('@field%s+') or
                line:match('@table%s+') then
               has_ldoc_tags = true
            end
            if has_luals_tags and has_ldoc_tags then break end
         end
         return has_luals_tags or has_ldoc_tags
      else
         -- In compatibility mode or auto-detect mode, check for any @ symbols
         local has_at_symbol = comment_str:find '@'
         if has_at_symbol then
            return true
         end

         -- Also check for LuaLS style
         local annotation_style = detect_annotation_style(comment_lines)
         return annotation_style == 'luals'
      end
   end
end

-- Determine if a comment block should be ignored entirely because it only contains
-- LuaLS code-analysis annotations (like @type, @diagnostic) and no user-facing docs.
local function is_ignored_only_luals_comment(comment_lines, args)
   if type(comment_lines) ~= 'table' then comment_lines = { comment_lines } end

   -- Tags that should NOT trigger a documentation entry
   local ignored = {
      type = true,
      diagnostic = true,
      cast = true,
      generic = true,
      meta = true,
      nodiscard = true,
      version = true,
      since = true,
      package = true,
      protected = true,
      private = true,
   }

   local saw_anything = false
   for _, line in ipairs(comment_lines) do
      local tag = line:match('^%s*@(%w+)')
      if tag then
         saw_anything = true
         if not ignored[tag] then
            -- There is at least one meaningful tag
            return false
         end
      else
         -- Any plain text means it's a real doc block
         if line:match('%S') then
            return false
         end
      end
   end

   -- Only ignored tags (or blank) were present
   return saw_anything
end



-- This takes the collected comment block, and uses the docstyle to
-- extract tags and values.  Assume that the summary ends in a period or a question
-- mark, and everything else in the preamble is the description.
-- If a tag appears more than once, then its value becomes a list of strings.
-- Alias substitution and @TYPE NAME shortcutting is handled by Item.check_tag
local function extract_tags(s, args, comment_lines, filename)
   local preamble, tag_items
   if s:match '^%s*$' then return {} end

   -- Detect annotation style if comment_lines provided
   local annotation_style = 'ldoc' -- default
   if args.only_luals == true then
      annotation_style = 'luals'
   elseif args.only_ldoc == true then
      annotation_style = 'ldoc'
   else
      if comment_lines and args.luals ~= false then
         annotation_style = detect_annotation_style(comment_lines)
      end
   end

   -- Style selection: prefer detection even when LuaLS mode is on, so classic
   -- LDoc blocks like @table still work alongside LuaLS annotations.
   if args.luals == true then
      local detected = (comment_lines and detect_annotation_style(comment_lines)) or annotation_style
      if args.ldoc_compat == true then
         annotation_style = detected
      else
         annotation_style = detected
      end
   end

   if args.colon then --and s:match ':%s' and not s:match '@%a' then
      preamble, tag_items = parse_colon_tags(s)
   elseif annotation_style == 'luals' then
      preamble, tag_items = parse_luals_tags(s, args)
   else
      preamble, tag_items = parse_at_tags(s)
   end

   -- Global filter: Remove variable-only LuaLS tags regardless of parsing path
   local variable_only_tags = {
      type = true,       -- Variable type annotations
      diagnostic = true, -- Diagnostic control
      cast = true,       -- Type casting
      meta = true,       -- Meta information
      nodiscard = true,  -- Return value usage hints
      version = true,    -- Version annotations
      since = true,      -- Version since annotations
      package = true,    -- Package visibility
      protected = true,  -- Protected visibility
      private = true,    -- Private visibility
   }

   -- Filter out variable-only tags from tag_items
   local filtered_tag_items = {}
   for _, item in ipairs(tag_items) do
      local tag = item[1]
      if not variable_only_tags[tag] then
         filtered_tag_items[#filtered_tag_items + 1] = item
      end
   end
   tag_items = filtered_tag_items

   -- Compatibility: inside hook/function-like blocks, treat classic '@table name desc'
   -- as a parameter declaration instead of a new table item to avoid ldoc_class conflicts.
   -- This fixes blocks that mix '@hook' and '@table ...', which would otherwise yield
   -- ldoc_class {hook,table} and halt the build.
   do
      local has_hook_like = false
      for _, it in ipairs(tag_items) do
         local t = it[1]
         if t == 'hook' or t == 'function' or t == 'lfunction' then
            has_hook_like = true; break
         end
      end
      if has_hook_like then
         for idx, it in ipairs(tag_items) do
            if it[1] == 'table' then
               local rest = it[2] or ''
               -- Split into first token (name) and remainder (description)
               local name, desc = rest:match('^%s*([^%s]+)(.*)$')
               if name and name ~= '' then
                  desc = desc or ''
                  local new_rest = (desc ~= '' and (name .. ' ' .. desc:gsub('^%s+', '')) or name)
                  tag_items[idx] = { 'param', new_rest, { type = 'table' } }
               end
            end
         end
      end
   end

   -- Helper to build tags object from a list of tag_items and a given preamble
   local function build_tags_from_items(items, pre)
      local strip = tools.strip
      local summary, description = pre:match('^(.-[%.?])(%s.+)')
      if not summary then
         summary, description = pre:match('^(.-\n\n)(.+)')
         if not summary then
            summary = pre
         end
      end
      local tg = Tags.new { summary = summary and strip(summary) or '', description = description or '' }
      for _, it in ipairs(items) do
         local tag, value, modifiers = Item.check_tag(tg, unpack(it))
         if not value:match '\n[^\n]+\n' then
            value = strip(value)
         end
         tg:add(tag, value, modifiers)
      end
      return tg
   end

   -- If multiple @table tags exist in this block, split into per-table segments
   local table_indices = {}
   for idx, item in ipairs(tag_items) do
      if item[1] == 'table' then table_indices[#table_indices + 1] = idx end
   end

   local tags
   if #table_indices > 1 then
      local segments = {}
      for i = 1, #table_indices do
         local s = table_indices[i]
         local e = (i < #table_indices) and (table_indices[i + 1] - 1) or #tag_items
         local slice = {}
         for j = s, e do slice[#slice + 1] = tag_items[j] end
         segments[#segments + 1] = slice
      end
      -- Build tags for first segment; attach others to _extra_segments
      tags = build_tags_from_items(segments[1], preamble)
      tags._extra_segments = {}
      for i = 2, #segments do
         local tgi = build_tags_from_items(segments[i], '') -- avoid carrying summary twice
         tags._extra_segments[#tags._extra_segments + 1] = tgi
      end
   else
      -- Default single-block behavior
      tags = build_tags_from_items(tag_items, preamble)
   end

   -- If parsed in classic mode, recognize LuaLS @class. Only emit a table when there are @field entries.
   if tags:get('class') and not tags:get('ldoc_class') then
      -- carry over class metadata for later binding in parse_file
      tags._luals_class_name = rawget(tags, 'class')
      tags._luals_extends = tags.extends
      tags._luals_class_exact = tags.class_exact and true or false
      if tags:get('field') then
         local cname = rawget(tags, 'class')
         rawset(tags, 'class', nil)
         tags:add('ldoc_class', 'table')
         tags:add('name', cname)
      else
         -- keep as metadata only; do not create an item
         tags.name = nil
      end
   end
   -- If both @classmod (project-level) and LuaLS @class are present in the same block,
   -- keep the module as the project-level item and emit the table as a separate item later.
   if tags:get('classmod') and tags:get('table') and tags:get('name') then
      -- No action needed here; File:finish will handle categories.
   end

   -- Auto-detect realm for LuaLS annotations if not explicitly set
   if (args.auto_realm ~= false) and annotation_style == 'luals' and filename and not tags:get('realm') then
      local detected_realm = detect_realm_from_filename(filename)
      tags:add('realm', detected_realm) -- detected_realm now always returns a value (defaults to 'shared')
   end

   return tags --Map(tags)
end


-- parses a Lua or C file, looking for ldoc comments. These are like LuaDoc comments;
-- they start with multiple '-'. (Block commments are allowed)
-- If they don't define a name tag, then by default
-- it is assumed that a function definition follows. If it is the first comment
-- encountered, then ldoc looks for a call to module() to find the name of the
-- module if there isn't an explicit module name specified.

local function parse_file(fname, lang, package, args)
   local F = File(fname)
   local module_found, first_comment = nil, true
   local current_item, module_item

   F.args = args
   F.lang = lang
   F.base = package

   local tok, f = lang.lexer(fname)
   if not tok then return nil end

   local function lineno()
      return tok:lineno()
   end

   function F:warning(msg, kind, line)
      line = line or lineno()
      Item.had_warning = true
      io.stderr:write(fname .. ':' .. line .. ': ' .. msg, '\n')
   end

   function F:error(msg)
      self:warning(msg, 'error')
      io.stderr:write('LDoc error\n')
      os.exit(1)
   end

   local function add_module(tags, module_found, old_style)
      if not tags:get('name') then
         tags:add('name', module_found)
      end
      if not tags:get('ldoc_class') then
         tags:add('ldoc_class', 'module')
      end
      local item = F:new_item(tags, lineno())
      item.old_style = old_style
      module_item = item
   end

   local mod
   local t, v = tnext(tok)
   -- with some coding styles first comment is standard boilerplate; option to ignore this.
   if args.boilerplate and t == 'comment' then
      -- hack to deal with boilerplate inside Lua block comments
      if v:match '%s*%-%-%[%[' then lang:grab_block_comment(v, tok) end
      t, v = tnext(tok)
   end
   -- skip over dumb banners, as they break the parser
   if args.dumbbanners and t == 'comment' and (v:match '%s*%-%-%[%[%-%-%-+' or v:match '%s*%-%-%-%-+') then
      F:warning('Dumb banner being skipped at start of file, you should still remove them to prevent issues')
      t, v = lang:grab_block_comment(v, tok)
      t, v = tnext(tok)
   end
   if t == '#' then -- skip Lua shebang line, if present
      while t and t ~= 'comment' do t, v = tnext(tok) end
      if t == nil then
         F:warning('empty file')
         return nil
      end
   end
   if lang.parse_module_call and t ~= 'comment' then
      local prev_token
      while t do
         if prev_token ~= '.' and prev_token ~= ':' and t == 'iden' and v == 'module' then
            break
         end
         prev_token = t
         t, v = tnext(tok)
      end
      if not t then
         if not args.ignore then
            F:warning("no module() call found; no initial doc comment")
         end
         --return nil
      else
         mod, t, v = lang:parse_module_call(tok, t, v)
         if mod and mod ~= '...' then
            add_module(Tags.new { summary = '(no description)' }, mod, true)
            first_comment = false
            module_found = true
         end
      end
   end
   -- state for LuaLS class grouping within this file
   local pending_class_anno        -- holds the most recent @class name/metadata awaiting a target binding
   local class_var_to_name = {}    -- map variable identifier -> class display name
   local class_var_meta = {}       -- map variable identifier -> { exact=true/false, extends=List }
   local classes_meta_by_name = {} -- class display name -> metadata

   local ok, err = xpcall(function()
      while t do
         if t == 'comment' then
            local comment = {}

            local ldoc_comment, block = lang:start_comment(v)

            -- skip over dumb banners, as they break the parser
            if args.dumbbanners and ldoc_comment and (v:match '%s*%-%-%[%[%-%-%-+' or v:match '%s*%-%-%-%-+') then
               F:warning('Dumb banner being skipped, you should still remove them to prevent issues')
               t, v = lang:grab_block_comment(v, tok)
               ldoc_comment = nil
               block = nil
               t, v = tnext(tok)
            end

            if ldoc_comment and block then
               t, v = lang:grab_block_comment(v, tok)
            end

            if lang:empty_comment(v) then -- ignore rest of empty start comments
               t, v = tok()
               -- If there is a blank line separating this comment from the next,
               -- stop collecting so the next '---' starts a fresh block. A blank line
               -- is a space token that contains a newline (one or more '\n').
               if t == 'space' then
                  local space_has_newline = v:match('\n') ~= nil
                  if space_has_newline then
                     -- consume the space and leave the next token for the outer loop
                     t, v = tok()
                     break
                  else
                     -- consume inline spaces and continue collecting
                     t, v = tok()
                  end
               end
            end

            local seen_table = false
            local seen_table_name           -- capture first @table name within this block as a safety net
            local saw_project_level = false -- e.g. @module, @classmod, etc., within this block
            while t and t == 'comment' do
               local trimmed = lang:trim_comment(v)
               -- Track if this block contains a project-level tag; if so, don't swallow following table docs
               do
                  local tag = trimmed:match('^%s*@(%w+)')
                  if tag then
                     -- project-level kinds as per doc.known_tags._project_level (keep list local to avoid requiring doc here)
                     if tag == 'module' or tag == 'script' or tag == 'example' or tag == 'topic' or tag == 'submodule' or
                         tag == 'classmod' or tag == 'file' or tag == 'panel' or tag == 'item' or tag == 'sent' or tag == 'swep' or tag == 'stool' then
                        saw_project_level = true
                     end
                  end
               end
               local tname = trimmed:match('^%s*@table%s+([^%s].-)%s*$')
               if tname then
                  if seen_table then
                     -- We've already collected one @table in this block; stop here so the next
                     -- iteration treats the next @table as a new doc block.
                     break
                  else
                     seen_table = true
                     seen_table_name = tname
                  end
               end
               v = trimmed
               append(comment, v)
               t, v = tok()

               -- NOTE: Allow prose paragraphs within a @table block. We rely on the existing
               -- multi-@table segmentation (see table_indices logic) to split multiple tables
               -- defined within a single block. Breaking on any non-tag prose here was causing
               -- legitimate field tags later in the same block to be dropped (e.g. only the first
               -- @field would appear). So we do not break on non-tag prose anymore.
               -- If we previously saw a project-level tag (like @module), then encountering a new
               -- table tag should start a fresh block so that module docs and table docs don't merge.
               if t == 'comment' and saw_project_level then
                  local peek = lang:trim_comment(v)
                  if peek:match('^%s*@table%s+') then
                     break
                  end
               end
               -- Improved blank line detection: check for space tokens with newlines
               if t == 'space' then
                  -- Any newline in a non-comment space token separates doc blocks
                  if v:find('\n') then
                     -- Do not consume; leave for next outer iteration so next comment starts a new block
                     break
                  else
                     -- Pure spaces inline; consume and continue
                     t, v = tok()
                  end
               elseif t ~= 'comment' then
                  -- We've hit a non-comment, non-space token - end of comment block
                  break
               end

               -- After processing space/newlines, check if next comment contains a second @table
               -- This ensures blank lines separate @table blocks before we check for multiple tables
               if t == 'comment' and seen_table then
                  local next_trimmed = lang:trim_comment(v)
                  local next_tname = next_trimmed:match('^%s*@table%s+([^%s].-)%s*$')
                  if next_tname then
                     -- We've already collected one @table and found another; stop here so the next
                     -- iteration treats the next @table as a new doc block.
                     break
                  end
               end
            end

            if t == 'space' then t, v = tnext(tok) end

            -- If we exited the inner while-loop early due to a new '@table' line, ensure
            -- the accumulated block gets processed now; leave the next comment token for
            -- the outer loop iteration so it becomes a new block.

            local item_follows, tags, is_local, case, parse_error
            local comment_text
            if ldoc_comment then
               comment_text = table.concat(comment)
               if comment_text:match '^%s*$' then
                  ldoc_comment = nil
               end
               -- replace comment_lines source with text for further checks but keep original table
               comment = comment
               -- We will use comment_text below when needed
               if ldoc_comment then
                  -- If this comment only contains ignored LuaLS annotations, skip it entirely
                  local comment_lines_tbl = {}
                  for line in comment_text:gmatch("[^\n]*\n?") do
                     if line:match('%S') then comment_lines_tbl[#comment_lines_tbl + 1] = (line:gsub("\n$", "")) end
                  end
                  if is_ignored_only_luals_comment(comment_lines_tbl, args) then
                     ldoc_comment = nil
                  end
                  -- Heuristic: if the last line contains a LuaLS diagnostic directive or @type
                  -- and the next code token is a local assignment, do not try to parse as an item
                  -- (common pattern: local PLUGIN = PLUGIN ---@diagnostic disable-line)
                  if ldoc_comment and comment_text:match('@diagnostic') or comment_text:match('@type') then
                     -- Peek: if current t/v indicates 'local' followed by identifier and '=' then skip
                     local pt, pv = t, v
                     local skip
                     if pt == 'keyword' and pv == 'local' then
                        local t1, v1 = tnext(tok)
                        if t1 == 'iden' then
                           local t2 = tnext(tok)
                           if t2 == '=' then skip = true end
                        end
                     end
                     if skip then ldoc_comment = nil end
                  end
               end
            end
            if ldoc_comment then
               if first_comment then
                  first_comment = false
               else
                  item_follows, is_local, case = lang:item_follows(t, v, tok)
                  if not item_follows then
                     parse_error = is_local
                     is_local = false
                  end
               end

               if item_follows or comment_contains_tags(comment_text or table.concat(comment, '\n'), args) then
                  local comment_str = comment_text or table.concat(comment, '\n')
                  local comment_lines = {}
                  for line in comment_str:gmatch("[^\n]+") do comment_lines[#comment_lines + 1] = line end
                  tags = extract_tags(comment_str, args, comment_lines, fname)
                  -- If this block carries a LuaLS @class, record metadata and remember for next binding
                  if tags and tags._luals_class_name then
                     local meta = {
                        name = tags._luals_class_name,
                        extends = tags._luals_extends,
                        exact = tags._luals_class_exact or false,
                     }
                     classes_meta_by_name[meta.name] = { exact = meta.exact, extends = meta.extends }
                     pending_class_anno = meta
                  end
                  -- If a function follows but the tags declared a project-level 'item',
                  -- it likely comes from '@item <name> <desc>' used as a param macro. Drop it.
                  if item_follows and tags.ldoc_class == 'item' then
                     tags.ldoc_class = nil
                     tags.name = nil
                  end
                  if tags.ldoc_class and tags.name == "" then
                     tags.name = nil
                  end
                  -- explicitly named @module (which is recommended)
                  if doc.project_level(tags.ldoc_class) then
                     module_found = tags.name
                     -- might be a module returning a single function!
                     if tags.ldoc_class == 'module' and (tags.param or tags['return']) and not (F.args and F.args.luals) then
                        local parms, ret = tags.param, tags['return']
                        local name = tags.name
                        tags.param = nil
                        tags['return'] = nil
                        tags['ldoc_class'] = nil
                        tags['name'] = nil
                        add_module(tags, name, false)
                        tags = {
                           summary = '',
                           name = 'returns...',
                           ldoc_class = 'function',
                           ['return'] = ret,
                           param = parms
                        }
                     end
                  end
                  doc.expand_annotation_item(tags, current_item)
                  -- if the item has an explicit name or defined meaning
                  -- then don't continue to do any code analysis!
                  -- Watch out for the case where there are field or param tags
                  -- but no class, since these will be fixed up later as module/class
                  -- entities
                  if (tags.field or tags.param) and not tags.ldoc_class then
                     parse_error = false
                  end
                  if tags.name then
                     if not tags.ldoc_class then
                        F:warning("no type specified, assuming function: '" .. tags.name .. "'")
                        if tags.add then
                           tags:add('ldoc_class', 'function')
                        else
                           tags["ldoc_class"] = "function"
                        end
                     end
                     item_follows, is_local, parse_error = false, false, false
                  elseif args.no_args_infer then
                     F:error("No name and type provided (no_args_infer)")
                  elseif lang:is_module_modifier(tags) then
                     if not item_follows then
                        F:warning("@usage or @export followed by unknown code")
                        break
                     end
                     item_follows(tags, tok)
                     local res, value, tagname = lang:parse_module_modifier(tags, tok, F)
                     if not res then
                        F:warning(value); break
                     else
                        if tagname then
                           module_item:set_tag(tagname, value)
                        end
                        -- don't continue to make an item!
                        ldoc_comment = false
                     end
                  end
               end
               if parse_error then
                  F:warning('definition cannot be parsed - ' .. parse_error)
               end
            end

            -- some hackery necessary to find the module() call
            if not module_found and ldoc_comment then
               local old_style
               module_found, t, v = lang:find_module(tok, t, v)
               -- right, we can add the module object ...
               old_style = module_found ~= nil
               local module_type
               if not module_found or module_found == '...' then
                  -- we have to guess the module name
                  module_found, module_type = tools.this_module_name(package, fname)
               end
               if not tags then
                  local comment_str = type(comment) == 'table' and table.concat(comment, '\n') or comment
                  local comment_lines = type(comment) == 'table' and comment or { comment }
                  tags = extract_tags(comment_str, args, comment_lines, fname)
               end

               if module_type and not tags:get("ldoc_class") then
                  tags:add('ldoc_class', module_type)
               end
               -- If the current comment did not define a project-level tag (e.g. it's a LuaLS @class table),
               -- do not reuse its tags for the module, or we'll end up with duplicate 'name' values.
               local tags_for_module = tags
               if not (tags_for_module and tags_for_module.ldoc_class and doc.project_level(tags_for_module.ldoc_class)) then
                  tags_for_module = Tags.new { summary = '(no description)' }
               end
               -- Avoid creating multiple project-level modules with same name in a single file
               if not module_item or (module_item and module_item.name ~= module_found) then
                  add_module(tags_for_module, module_found, old_style)
               end
               -- Only consume the tags if this block defined a project-level item; otherwise
               -- keep tags so the current block can still produce its items (e.g. @table, @function).
               if tags and tags.ldoc_class and doc.project_level(tags.ldoc_class) then
                  tags = nil
               end
               if not t then
                  F:warning('contains no items', 'warning', 1)
                  break;
               end -- run out of file!
               -- if we did bump into a doc comment, then we can continue parsing it
            end

            -- end of a block of document comments
            if ldoc_comment and tags then
               local line = lineno()
               local function finalize_one(one_tags, is_first)
                  if t ~= nil then
                     -- Prefer not to override explicit classes, but if the block has a class (e.g. @hook)
                     -- and no explicit name was given, still run inference to fill in the name/args.
                     -- This preserves @table/@function blocks (which usually specify a name) while
                     -- fixing cases like '@hook' without a name preceding a function definition.
                     if is_first and item_follows and (not one_tags.ldoc_class or not one_tags.name) then
                        local err = item_follows(one_tags, tok)
                        if err then F:error(err) end
                     elseif is_first and parse_error then
                        F:warning('definition cannot be parsed - ' .. parse_error)
                     else
                        lang:parse_extra(one_tags, tok, is_first and case or nil)
                     end
                  end
                  if is_local or one_tags['local'] then
                     one_tags:add('local', true)
                  end
                  if (one_tags.field or one_tags.param) and not one_tags.ldoc_class then
                     local fp = one_tags.field or one_tags.param
                     if type(fp) == 'table' then fp = fp[1] end
                     if fp then
                        fp = tools.extract_identifier(fp)
                        one_tags:add('name', fp)
                        one_tags:add('ldoc_class', 'field')
                     end
                  end
                  -- Safety net: if this block clearly had an @table NAME then this item
                  -- must represent a table. Promote misclassified 'field' items to 'table'
                  -- and ensure the item name matches the @table NAME instead of the first
                  -- @field identifier (e.g., avoiding 'OnRun' becoming the item name).
                  if seen_table_name and (not one_tags.ldoc_class or one_tags.ldoc_class == 'field') then
                     -- overwrite any previous fallback classification
                     one_tags.ldoc_class = 'table'
                     -- ensure the correct table name is used
                     one_tags.name = seen_table_name
                  end
                  if one_tags and one_tags.ldoc_class and type(one_tags.ldoc_class) == "table" and #one_tags.ldoc_class == 2 then
                     local class = one_tags.ldoc_class
                     if class[1] ~= class[2] and ((class[1] == 'function' or class[2] == 'function') and (class[1] == 'hook' or class[2] == 'hook')) then
                        one_tags.ldoc_class = 'hook'
                        for _, name in ipairs(one_tags.name) do
                           if name ~= '' then
                              one_tags.name = name; break
                           end
                        end
                     end
                  end
                  if one_tags.state then one_tags.realm = one_tags.state end
                  if not one_tags.realm and fname then
                     local realm = tools.find_realm(tostring(fname))
                     if not realm then F:warning('No realm specified, guessing for ' .. fname) end
                     one_tags.realm = realm or 'shared'
                  end
                  -- If we have a pending @class waiting to bind, and the upcoming code
                  -- created a name by inference (e.g., local Foo = {} or function Foo:bar)
                  -- then bind the variable prefix to the class name for future items.
                  if pending_class_anno and one_tags.name then
                     local inferred_name = one_tags.name
                     -- choose a variable identifier to bind:
                     -- 1) for table or field definitions like NAME = { ... } or NAME = value
                     --    'one_tags.name' is already NAME
                     -- 2) for functions, look for NAME:method or NAME.method prefix
                     local var
                     if one_tags.ldoc_class == 'table' or one_tags.ldoc_class == 'field' then
                        var = inferred_name:match('^([%w_%.]+)$')
                     end
                     if not var and type(inferred_name) == 'string' then
                        var = inferred_name:match('^([%w_%.]+)[:%.]')
                     end
                     if var then
                        class_var_to_name[var] = pending_class_anno.name
                        local meta = { exact = pending_class_anno.exact, extends = pending_class_anno.extends }
                        class_var_meta[var] = meta
                        classes_meta_by_name[pending_class_anno.name] = meta
                        pending_class_anno = nil
                     end
                  end

                  -- If this item references a known class variable, rewrite name to ClassName:method
                  local function rewrite_to_class_grouping()
                     local name = one_tags.name
                     if not name or type(name) ~= 'string' then return end
                     local var, rest = name:match('^([%w_%.]+)[:%.](.+)$')
                     if not var then return end
                     local cname = class_var_to_name[var]
                     if not cname then return end
                     -- Use ':' vs '.' according to whether it was a method (':') or static ('.')
                     local sep = name:find(':', 1, true) and ':' or '.'
                     one_tags.name = cname .. sep .. rest
                     -- Also categorize into a class section for better UX; module logic will create sections
                     one_tags.within = 'Class ' .. cname
                  end

                  rewrite_to_class_grouping()

                  if one_tags.name then
                     current_item = F:new_item(one_tags, line)
                     current_item.inferred = is_first and (item_follows ~= nil) or false
                     if doc.project_level(one_tags.ldoc_class) then module_item = current_item end
                  end
               end

               finalize_one(tags, true)
               -- If extract_tags produced extra per-table segments, finalize them as items too
               if tags._extra_segments and #tags._extra_segments > 0 then
                  for _, extra in ipairs(tags._extra_segments) do
                     finalize_one(extra, false)
                  end
               end
               if not t then break end
            end
         end
         if t ~= 'comment' then t, v = tok() end
      end
   end, debug.traceback)
   if not ok then return F, err end
   if f then f:close() end
   -- expose classes metadata to File so File:finish can build class sections with inheritance/exact flags
   F._luals_classes_meta = classes_meta_by_name
   return F
end

function parse.file(name, lang, args)
   if args.verbose then print(name, lang, args.package, args) end
   local F, err = parse_file(name, lang, args.package, args)
   if err or not F then return F, err end
   local ok, err = xpcall(function() F:finish() end, debug.traceback)
   if not ok then return F, err end
   return F
end

return parse
