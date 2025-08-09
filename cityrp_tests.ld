
file = {
	"cityrp_tests"
}

module_file = {

}

dir = "docs/html"
project = "CityRP"
title = "CityRP Documentation"

no_space_before_args = true
style = "docs/css"
template = "docs/templates"
format = "markdown"
ignore = true
topics = "docs/manual"
use_markdown_titles = true
kind_names = {module = "Libraries", topic = "Manual"}
merge = true
sort = true
sort_modules = true
dumbbanners = true
--luals = true

simple_args_string = true -- we show optionals/defaults outside of the display name
strip_metamethod_prefix = true -- remove the name of the table when displaying metamethod names
no_viewed_topic_at_top = true -- don't put the currently viewed topic at the top
use_new_templates = true -- new templating system
pretty_urls = true -- avoid showing .html in urls
pretty_topic_names = true -- strips extension from manual filenames, this does not check filename collisions

custom_tags = {
	{"realm", hidden = true},
	{"internal", hidden = true},
	{"baseclass", title = "BaseClass", hidden = true},
	{"state", title = "State", hidden = true},

	{"warns", title = "Warnings", format = function(...)
		return "<span class='tag-warning'>" .. markup(...) .. "</span>"
	end},
	{"bugs", title = "Known Issues", format = function(...)
		return "<span class='tag-bugs'>" .. markup(...) .. "</span>"
	end},
	{"deprecated", title = "Deprecated", format = function(str)
		if str == "" then
			return "<span class='tag-deprecated'>This function is deprecated and may be removed in a future version.</span>"
		else
			return "<span class='tag-deprecated'>This function is deprecated and may be removed in a future version.<br>" .. markup(str) .. "</span>"
		end
	end},
	{"internal", title = "Internal", format = function(str)
		if str == "" then
			return "<span class='tag-internal'>This function is internal. Whilst you can call it, you probably shouldn't.</span>"
		else
			return "<span class='tag-internal'>This function is internal. Whilst you can call it, you probably shouldn't.<br>" .. markup(str) .. "</span>"
		end
	end}
}

local function tagToState(tags)
	local states = {false, false, false} -- client, server, menu

	for _, state in ipairs(tags) do
		state = state:lower()
		if state == "client" then states[1] = true end
		if state == "server" then states[2] = true end
		if state == "menu" then states[3] = true end
		if state == "shared" then states[1], states[2] = true, true end
		if state == "global" then states[1], states[2], states[3] = true, true, true end
		if state == "clmenu" then states[1], states[3] = true, true end
	end

	return states
end

custom_display_name_handler = function(item, default_handler)
	if (item.type == "function" and item.module) then
		if (item.module.type == "classmod" or item.module.type == "panel") then
			return item.module.mod_name .. ":" .. default_handler(item)
		elseif (item.module.type == "hooks") then
			return item.module.mod_name:upper() .. ":" .. default_handler(item)
		end
	end

	return default_handler(item)
end

new_type("hooks", "Hooks", true)
new_type("panel", "Panels", true)

alias("fstring", {"field", modifiers = {type="string"}})
alias("fnumber", {"field", modifiers = {type="number"}})
alias("fnum", {"field", modifiers = {type="number"}})
alias("fint", {"field", modifiers = {type="int"}})
alias("fbool", {"field", modifiers = {type="bool"}})
alias("ffunc", {"field", modifiers = {type="function"}})
alias("ftab", {"field", modifiers = {type="table"}})

alias("rstring", {"return", modifiers = {type="string"}})
alias("rnumber", {"return", modifiers = {type="number"}})
alias("rint", {"return", modifiers = {type="int"}})
alias("rbool", {"return", modifiers = {type="bool"}})
alias("rfunc", {"return", modifiers = {type="function"}})
alias("rtab", {"return", modifiers = {type="table"}})
alias("rvec", {"return", modifiers = {type="Vector"}})
alias("rang", {"return", modifiers = {type="Angle"}})

tparam_alias("cityrptype", "cityrp.type")

tparam_alias("ply", "Player")
tparam_alias("vec", "Vector")
tparam_alias("ent", "Entity")
tparam_alias("color", "Color")
tparam_alias("veh", "Vehicle")
tparam_alias("ang", "Angle")
tparam_alias("vararg", "vararg")
tparam_alias("str", "string")
tparam_alias("wep", "Weapon")
tparam_alias("weapon", "Weapon")

local gmodurl = "https://wiki.facepunch.com/gmod/%s"
custom_see_handler("^gmod%((.*)%)$", function(name)
	return name, gmodurl:format(name)
end)

new_type("hook", "Hooks", false, "Parameters")
new_type("item", "Items", true)


