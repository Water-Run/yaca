--[[
File: windows_network_smoke.lua
Date: 2026-09-14
Author: WaterRun
Description: Exercises the real anonymous curl carrier using a credential-free test endpoint.
]]

local root, url = assert(arg[1]), assert(arg[2])
package.path = root .. "/src/?.lua"
local native = require("yaca_native")
local filesystem = assert(require("fs").new(native, { maximum_chunk_bytes = 65536 }))
local processes = assert(require("process").new(native, {
    maximum_output_bytes = 1048576, maximum_poll_bytes = 65536,
    shell = { kind = "windows", executable = "native-GetSystemDirectoryW/cmd.exe",
        fixed_arguments = { "/d", "/s", "/c" } },
}))
local network = assert(require("network").new({
    filesystem = filesystem, processes = processes,
}, {
    curl_executable = root .. "/curl.exe", bundled_ca_path = root .. "/cacert.pem",
    temporary_directory = root, private_permissions = 384,
    maximum_body_bytes = 1048576, maximum_header_bytes = 262144,
    maximum_config_bytes = 524288, maximum_output_bytes = 1048576,
    maximum_io_chunk_bytes = 65536, maximum_attempt_id_bytes = 128,
    maximum_connect_timeout_ms = 120000, maximum_total_timeout_ms = 3600000,
    component_environment = {},
}))
local port = assert(network.new_attempt({
    attempt_id = "remote-network-smoke", url = url, method = "POST", body = "{}",
    public_headers = { { name = "Content-Type", value = "application/json" } },
    secret_headers = {}, proxy = { mode = "off" },
    connect_timeout_ms = 10000, total_timeout_ms = 30000,
    secret_source = {
        secret_descriptors = function() return {} end,
        reveal_secret = function() error("no credential is permitted") end,
        scan_registered_secrets = function() return {} end,
    },
}))
assert(port:start(native.monotonic_now()))
local deadline = native.monotonic_now() + 35000
local terminal = false
while not terminal do
    assert(native.monotonic_now() < deadline, "network smoke deadline exceeded")
    for _, event in ipairs(port:poll(native.monotonic_now(), 16)) do
        if event.kind == "transport_terminal" then terminal = true end
    end
    if not terminal then native.sleep_ms(10) end
end
local result = port:join(native.monotonic_now() + 1000)
assert(port:close())
for _, name in ipairs({ "outcome", "exit_code", "diagnostic", "response_headers",
    "body_truncated", "descendants_proven_stopped" }) do
    print(name, tostring(result[name]))
end
assert(result.outcome == "completed" and result.exit_code == 0,
    "anonymous curl carrier failed")
assert(result.descendants_proven_stopped and not result.body_truncated)
assert(result.response_headers:match("^HTTP/1%.1 %d%d%d"))
print("windows-network-carrier=PASS")
