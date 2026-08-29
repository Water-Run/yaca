--[[
File: lxp_build.lua
Date: 2026-08-29
Author: WaterRun
Description: Freezes the target build recipe for pinned LuaExpat and static Expat.
]]

local M = {}

local TARGETS = {
    ["win32-x86"] = {
        artifact = "lxp.dll",
        object_format = "PE32-i386",
    },
    ["win64-x86_64"] = {
        artifact = "lxp.dll",
        object_format = "PE32+-x86-64",
    },
    ["linux-x86_64"] = {
        artifact = "lxp.so",
        object_format = "ELF64-x86-64",
    },
}

local function failure(code, message)
    return nil, { code = code, message = message }
end

local function copy_array(values)
    local result = {}
    for index, value in ipairs(values) do result[index] = value end
    return result
end

M.lock = {
    lua = {
        version = "5.5.1",
        sha256 = "1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce",
        url = "https://www.lua.org/ftp/lua-5.5.1.tar.gz",
    },
    expat = {
        version = "2.8.2",
        sha256 = "ef7d1994f533c9e7343d6c19f31064fc8ebbcbcaa144be3812b4f43052a05f4c",
        url = "https://github.com/libexpat/libexpat/releases/download/"
            .. "R_2_8_2/expat-2.8.2.tar.gz",
    },
    luaexpat = {
        version = "1.5.2",
        sha256 = "89d83f2141edec31be576425637216928221918fe95dc3854d1b7fd4c627213f",
        url = "https://github.com/lunarmodules/luaexpat/archive/refs/tags/1.5.2.tar.gz",
    },
}

M.expat_cmake_arguments = {
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
    "-DEXPAT_SHARED_LIBS=OFF",
    "-DEXPAT_BUILD_DOCS=OFF",
    "-DEXPAT_BUILD_EXAMPLES=OFF",
    "-DEXPAT_BUILD_TESTS=OFF",
    "-DEXPAT_BUILD_TOOLS=OFF",
}

M.luaexpat_compile = {
    language = "c99",
    source = "src/lxplib.c",
    entry_point = "luaopen_lxp",
    warnings = { "-Wall", "-Wextra" },
    optimization = "-O2",
    position_independent = true,
    shared_module = true,
    expat_linkage = "verified-static-archive",
    forbidden_linkage = { "host-libexpat", "rpath", "runpath" },
}

---Returns the immutable build expectations for one release target.
-- @param target_id string Exact release target identifier.
-- @return table|nil plan Copied target and compiler expectations.
-- @return table|nil err Structured target failure.
function M.plan(target_id)
    local target = TARGETS[target_id]
    if not target then return failure("UnknownTarget", "unknown lxp release target") end
    return {
        target_id = target_id,
        artifact = target.artifact,
        object_format = target.object_format,
        lua_abi = "5.5",
        expat_linkage = M.luaexpat_compile.expat_linkage,
        entry_point = M.luaexpat_compile.entry_point,
        expat_cmake_arguments = copy_array(M.expat_cmake_arguments),
    }
end

---Validates the native module identity before the XML codec accepts it.
-- @param lxp table Module returned by the absolute release loader.
-- @return boolean|nil valid True only for the pinned runtime identity.
-- @return table|nil err Structured dependency failure.
function M.validate_runtime(lxp)
    if type(lxp) ~= "table" or type(lxp.new) ~= "function" then
        return failure("InvalidXmlDependency", "lxp module does not expose new")
    end
    if lxp._VERSION ~= "LuaExpat 1.5.2" then
        return failure("XmlDependencyMismatch", "LuaExpat runtime is not version 1.5.2")
    end
    if lxp._EXPAT_VERSION ~= "expat_2.8.2" then
        return failure("XmlDependencyMismatch", "Expat runtime is not version 2.8.2")
    end
    if type(lxp._EXPAT_FEATURES) ~= "table" then
        return failure("InvalidXmlDependency", "Expat feature manifest is unavailable")
    end
    return true
end

return M
