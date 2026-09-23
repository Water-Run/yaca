--[[
Author: WaterRun
Date: 2026-09-23
File: launcher.lua
Description: Composes the locked official Lua interpreter and application entry points.
]]

local M = {}

---Embeds the upstream interpreter in the generated application translation unit.
-- The caller supplies lua.c from the same verified source tree as the linked
-- runtime. No second runtime, executable, module loader, or script parser exists.
--@param application string Generated luainstaller launcher source.
--@param interpreter string Unmodified locked Lua src/lua.c source.
--@param entry string native/yaca_entry.c source.
--@param headers table Locked private Lua headers, prefix and limits.
--@return string Combined C source.
function M.wrap(application, interpreter, entry, headers)
    assert(type(application) == "string" and type(interpreter) == "string"
        and type(entry) == "string", "launcher source inputs are required")
    assert(application:find("int main%(int argc, char %*%*argv%)"),
        "locked application entry point changed")
    assert(interpreter:find("int main %(int argc, char %*%*argv%)"),
        "locked Lua interpreter entry point changed")
    -- Installed Lua prefixes expose only public headers. Inline the two
    -- private headers from the verified source tree for both platform builds.
    for name, key in pairs({ ["lprefix.h"] = "prefix", ["llimits.h"] = "limits" }) do
        assert(type(headers) == "table" and type(headers[key]) == "string",
            "locked private Lua header is missing")
        local count
        interpreter, count = interpreter:gsub('#include "' .. name:gsub("%.", "%%.") .. '"',
            ---Substitutes the verified private Lua header at its locked include.
            --@param none No arguments; the replacement uses the current header key.
            --@return string header Exact private header source from the verified tree.
            function() return headers[key] end)
        assert(count == 1, "locked Lua interpreter includes changed")
    end
    return table.concat({
        headers.windows or "",
        "#define main yaca_application_main\n", application, "\n#undef main\n",
        "#define main yaca_lua_main\n", interpreter, "\n#undef main\n", entry,
    })
end

return M
