--[[
File: network.lua
Date: 2026-08-29
Author: WaterRun
Description: Builds a secret-safe curl carrier over structured process ports.
]]

local M = {}

local FIXED_CURL_ARGUMENTS = {
    "--disable",
    "--silent",
    "--show-error",
    "--no-buffer",
    "--config",
    "-",
}

local REQUIRED_FILESYSTEM_METHODS = {
    "open_read",
    "create_new",
    "stat_identity",
    "stream_read",
    "stream_write",
    "flush_file",
    "flush_directory",
    "delete_verified",
    "close",
}

local CONTROLLED_PUBLIC_HEADERS = {
    ["accept-encoding"] = true,
    authorization = true,
    connection = true,
    ["content-length"] = true,
    host = true,
    ["proxy-authorization"] = true,
    ["transfer-encoding"] = true,
}

local CONTROLLED_SECRET_HEADERS = {
    ["accept-encoding"] = true,
    connection = true,
    ["content-length"] = true,
    host = true,
    ["transfer-encoding"] = true,
}

local function failure(code, message, detail)
    local result = { code = code, message = message }
    if detail ~= nil then result.detail = detail end
    return result
end

local function readonly(values, label)
    return setmetatable({}, {
        __index = values,
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        __pairs = function()
            return next, values, nil
        end,
        __len = function()
            return #values
        end,
        __metatable = "locked",
    })
end

local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

local function valid_absolute_path(path)
    if type(path) ~= "string" or path == "" or path:find("\0", 1, true) then
        return false
    end
    local normalized = path:gsub("\\", "/")
    return normalized:sub(1, 1) == "/"
        or normalized:match("^[A-Za-z]:/") ~= nil
        or normalized:match("^//[^/]+/[^/]+") ~= nil
end

local function dense_count(values)
    if type(values) ~= "table" then return nil end
    local count = 0
    for key in pairs(values) do
        if math.type(key) ~= "integer" or key < 1 then return nil end
        count = count + 1
    end
    for index = 1, count do
        if values[index] == nil then return nil end
    end
    return count
end

local function copy_array(values)
    local result = {}
    for index, value in ipairs(values) do result[index] = value end
    return result
end

local function copy_string_map(values)
    local result = {}
    for key, value in pairs(values or {}) do result[key] = value end
    return result
end

local function directory_separator(path)
    if path:find("\\", 1, true) and not path:find("/", 1, true) then return "\\" end
    return "/"
end

local function join_path(directory, name)
    local tail = directory:sub(-1)
    if tail == "/" or tail == "\\" then return directory .. name end
    return directory .. directory_separator(directory) .. name
end

local function identity_equal(left, right)
    return type(left) == "table"
        and type(right) == "table"
        and left.kind == right.kind
        and left.volume == right.volume
        and left.object == right.object
        and left.size == right.size
        and left.modified == right.modified
end

local function same_object(left, right)
    return type(left) == "table"
        and type(right) == "table"
        and left.kind == "file"
        and right.kind == "file"
        and left.volume == right.volume
        and left.object == right.object
end

local function config_quote(value)
    return '"' .. value
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\t", "\\t")
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\v", "\\v") .. '"'
end

local function option_line(name, value)
    if type(value) == "boolean" then
        return name .. " = " .. (value and "true" or "false")
    end
    return name .. " = " .. config_quote(value)
end

local function milliseconds_as_seconds(value)
    return tostring(value // 1000) .. "." .. string.format("%03d", value % 1000)
end

local function valid_url(value, allow_credentials)
    if type(value) ~= "string"
        or value == ""
        or value:find("[\0\r\n]")
        or value:find("#", 1, true)
    then
        return false
    end
    local scheme = value:match("^([A-Za-z][A-Za-z0-9+%.%-]*):")
    if not scheme then return false end
    scheme = scheme:lower()
    if scheme ~= "http" and scheme ~= "https" then return false end
    local authority = value:match("^[A-Za-z][A-Za-z0-9+%.%-]*://([^/%?#]+)")
    if not authority or authority == "" then return false end
    return allow_credentials or not authority:find("@", 1, true)
end

local function valid_header_name(value)
    return type(value) == "string"
        and value ~= ""
        and value:match("^[!#$%%&'*+%.%^_`|~0-9A-Za-z%-]+$") ~= nil
end

local function valid_header_fragment(value)
    return type(value) == "string" and not value:find("[\0\r\n]")
end

local function validate_headers(public_headers, secret_headers)
    local public_count = dense_count(public_headers)
    local secret_count = dense_count(secret_headers)
    if public_count == nil or secret_count == nil then
        return nil, failure("InvalidHeaders", "request headers must be dense arrays")
    end
    local names, public_copy, secret_copy = {}, {}, {}
    for index, header in ipairs(public_headers) do
        if type(header) ~= "table" then
            return nil, failure("InvalidHeaders", "public header must be a table")
        end
        for key in pairs(header) do
            if key ~= "name" and key ~= "value" then
                return nil, failure("InvalidHeaders", "public header has an unknown field")
            end
        end
        if not valid_header_name(header.name) or not valid_header_fragment(header.value) then
            return nil, failure("InvalidHeaders", "public header bytes are invalid")
        end
        local comparison = header.name:lower()
        if CONTROLLED_PUBLIC_HEADERS[comparison] or names[comparison] then
            return nil, failure("InvalidHeaders", "public header is controlled or duplicated")
        end
        names[comparison] = true
        public_copy[index] = { name = header.name, value = header.value }
    end
    for index, header in ipairs(secret_headers) do
        if type(header) ~= "table" then
            return nil, failure("InvalidHeaders", "secret header must be a table")
        end
        local allowed = {
            name = true,
            prefix = true,
            suffix = true,
            secret_id = true,
            destination = true,
        }
        for key in pairs(header) do
            if type(key) ~= "string" or not allowed[key] then
                return nil, failure("InvalidHeaders", "secret header has an unknown field")
            end
        end
        local prefix, suffix = header.prefix or "", header.suffix or ""
        if not valid_header_name(header.name)
            or not valid_header_fragment(prefix)
            or not valid_header_fragment(suffix)
            or type(header.secret_id) ~= "string"
            or header.secret_id == ""
            or type(header.destination) ~= "string"
            or header.destination == ""
        then
            return nil, failure("InvalidHeaders", "secret header reference is invalid")
        end
        local comparison = header.name:lower()
        if CONTROLLED_SECRET_HEADERS[comparison] or names[comparison] then
            return nil, failure("InvalidHeaders", "secret header is controlled or duplicated")
        end
        names[comparison] = true
        secret_copy[index] = {
            name = header.name,
            prefix = prefix,
            suffix = suffix,
            secret_id = header.secret_id,
            destination = header.destination,
        }
    end
    return public_copy, secret_copy
end

local function validate_proxy(proxy)
    proxy = proxy or { mode = "off" }
    if type(proxy) ~= "table" then
        return nil, failure("InvalidProxy", "proxy snapshot must be a table")
    end
    local allowed = {
        mode = true,
        url = true,
        no_proxy = true,
        secret_id = true,
        destination = true,
    }
    for key in pairs(proxy) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidProxy", "proxy snapshot has an unknown field")
        end
    end
    if proxy.mode == "off" then
        if proxy.url ~= nil or proxy.secret_id ~= nil or proxy.destination ~= nil then
            return nil, failure("InvalidProxy", "disabled proxy cannot carry a route")
        end
        return { mode = "off", no_proxy = "*" }
    end
    if proxy.mode ~= "explicit" or not valid_header_fragment(proxy.no_proxy or "") then
        return nil, failure("InvalidProxy", "proxy mode or no-proxy snapshot is invalid")
    end
    local has_public = proxy.url ~= nil
    local has_secret = proxy.secret_id ~= nil or proxy.destination ~= nil
    if has_public == has_secret then
        return nil, failure("InvalidProxy", "explicit proxy requires one route carrier")
    end
    if has_public then
        if not valid_url(proxy.url, false) then
            return nil, failure("InvalidProxy", "public proxy URL is invalid or credential-bearing")
        end
        return { mode = "explicit", url = proxy.url, no_proxy = proxy.no_proxy or "" }
    end
    if type(proxy.secret_id) ~= "string"
        or proxy.secret_id == ""
        or type(proxy.destination) ~= "string"
        or proxy.destination == ""
    then
        return nil, failure("InvalidProxy", "proxy secret reference is invalid")
    end
    return {
        mode = "explicit",
        secret_id = proxy.secret_id,
        destination = proxy.destination,
        no_proxy = proxy.no_proxy or "",
    }
end

local function validate_secret_source(source, required)
    if not required and source == nil then return true end
    if type(source) ~= "table"
        or type(source.reveal_secret) ~= "function"
        or type(source.secret_descriptors) ~= "function"
        or type(source.scan_registered_secrets) ~= "function"
    then
        return nil, failure("InvalidSecretSource", "typed configuration secret source is required")
    end
    return true
end

local function validate_attempt(spec, limits)
    if type(spec) ~= "table" then
        return nil, failure("InvalidRequest", "network attempt spec must be a table")
    end
    local allowed = {
        attempt_id = true,
        url = true,
        method = true,
        public_headers = true,
        secret_headers = true,
        body = true,
        secret_source = true,
        proxy = true,
        ca_bundle_path = true,
        connect_timeout_ms = true,
        total_timeout_ms = true,
    }
    for key in pairs(spec) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidRequest", "network attempt spec has an unknown field")
        end
    end
    if type(spec.attempt_id) ~= "string"
        or spec.attempt_id == ""
        or #spec.attempt_id > limits.maximum_attempt_id_bytes
        or not spec.attempt_id:match("^[A-Za-z0-9_-]+$")
    then
        return nil, failure("InvalidAttemptId", "attempt identity is not a safe carrier token")
    end
    if not valid_url(spec.url, false) then
        return nil, failure("InvalidUrl", "Model URL must be absolute HTTP or HTTPS without credentials")
    end
    if spec.method ~= "POST" then
        return nil, failure("InvalidMethod", "v0.1 Model transport requires POST")
    end
    if type(spec.body) ~= "string" or #spec.body > limits.maximum_body_bytes then
        return nil, failure("Limit", "request body exceeds its release limit")
    end
    if not valid_integer(spec.connect_timeout_ms, 1)
        or spec.connect_timeout_ms > limits.maximum_connect_timeout_ms
        or not valid_integer(spec.total_timeout_ms, 1)
        or spec.total_timeout_ms > limits.maximum_total_timeout_ms
        or spec.connect_timeout_ms > spec.total_timeout_ms
    then
        return nil, failure("InvalidDeadline", "network attempt deadlines are invalid")
    end
    local public_headers, secret_headers_or_error = validate_headers(
        spec.public_headers or {},
        spec.secret_headers or {}
    )
    if not public_headers then return nil, secret_headers_or_error end
    local proxy, proxy_error = validate_proxy(spec.proxy)
    if not proxy then return nil, proxy_error end
    local secret_required = #secret_headers_or_error > 0 or proxy.secret_id ~= nil
    local source_ok, source_error = validate_secret_source(spec.secret_source, secret_required)
    if not source_ok then return nil, source_error end
    local ca_bundle_path = spec.ca_bundle_path or limits.bundled_ca_path
    if not valid_absolute_path(ca_bundle_path) then
        return nil, failure("InvalidCaBundle", "CA bundle snapshot must be an absolute path")
    end
    return {
        attempt_id = spec.attempt_id,
        url = spec.url,
        method = spec.method,
        public_headers = public_headers,
        secret_headers = secret_headers_or_error,
        body = spec.body,
        secret_source = spec.secret_source,
        proxy = proxy,
        ca_bundle_path = ca_bundle_path,
        connect_timeout_ms = spec.connect_timeout_ms,
        total_timeout_ms = spec.total_timeout_ms,
    }
end

local function scan_public_bytes(source, values)
    if source == nil then return true end
    for _, value in ipairs(values) do
        local called, hits, scan_error = pcall(source.scan_registered_secrets, value)
        if not called then
            return nil, failure("SecretScanFailure", "registered secret scan raised an exception")
        end
        if hits == nil then
            return nil, type(scan_error) == "table" and scan_error
                or failure("SecretScanFailure", "registered secret scan failed")
        end
        if type(hits) ~= "table" then
            return nil, failure("SecretScanFailure", "registered secret scan result is invalid")
        end
        if next(hits) ~= nil then
            return nil, failure(
                "RegisteredSecretInRequest",
                "ordinary request bytes contain a registered configuration secret"
            )
        end
    end
    return true
end

local function reveal_secrets(attempt)
    local source = attempt.secret_source
    if source == nil then return {}, {} end
    local called, descriptors = pcall(source.secret_descriptors)
    if not called or type(descriptors) ~= "table" then
        return nil, failure("SecretSourceFailure", "secret descriptors are unavailable")
    end
    local eligible = {}
    for _, descriptor in pairs(descriptors) do
        if type(descriptor) == "table" and type(descriptor.id) == "string" then
            eligible[descriptor.id] = descriptor.scan_eligible == true
        end
    end
    local used, by_reference, seen = {}, {}, {}
    local function reveal(id, destination)
        local reference = id .. "\0" .. destination
        if by_reference[reference] ~= nil then return by_reference[reference] end
        if eligible[id] ~= true then
            return nil, failure(
                "SecretConsumerIneligible",
                "registered secret is below the release scan boundary or unknown"
            )
        end
        local ok, value = pcall(source.reveal_secret, id, destination)
        if not ok then
            return nil, failure("SecretSourceFailure", "secret reveal raised an exception")
        end
        if type(value) ~= "string" or value == "" or value:find("[\0\r\n]") then
            return nil, failure("SecretSourceFailure", "secret reveal returned invalid bytes")
        end
        by_reference[reference] = value
        if not seen[value] then
            seen[value] = true
            used[#used + 1] = value
        end
        return value
    end
    for _, header in ipairs(attempt.secret_headers) do
        local value, reveal_error = reveal(header.secret_id, header.destination)
        if not value then return nil, reveal_error end
    end
    if attempt.proxy.secret_id then
        local value, reveal_error = reveal(
            attempt.proxy.secret_id,
            attempt.proxy.destination
        )
        if not value then return nil, reveal_error end
        if not valid_url(value, true) then
            return nil, failure("InvalidProxy", "revealed proxy URL is invalid")
        end
    end
    return used, by_reference
end

local function redact(bytes, secrets)
    if type(bytes) ~= "string" or bytes == "" or #secrets == 0 then return bytes end
    local intervals = {}
    for _, secret in ipairs(secrets) do
        local cursor = 1
        while true do
            local first = bytes:find(secret, cursor, true)
            if not first then break end
            intervals[#intervals + 1] = { first, first + #secret - 1 }
            cursor = first + 1
        end
    end
    if #intervals == 0 then return bytes end
    table.sort(intervals, function(left, right)
        if left[1] ~= right[1] then return left[1] < right[1] end
        return left[2] > right[2]
    end)
    local merged = {}
    for _, interval in ipairs(intervals) do
        local tail = merged[#merged]
        if not tail or interval[1] > tail[2] + 1 then
            merged[#merged + 1] = { interval[1], interval[2] }
        elseif interval[2] > tail[2] then
            tail[2] = interval[2]
        end
    end
    local parts, cursor = {}, 1
    for _, interval in ipairs(merged) do
        parts[#parts + 1] = bytes:sub(cursor, interval[1] - 1)
        parts[#parts + 1] = "[registered-secret]"
        cursor = interval[2] + 1
    end
    parts[#parts + 1] = bytes:sub(cursor)
    return table.concat(parts)
end

local function raise_redacted(value, secrets, level)
    local message
    if type(value) == "table" and type(value.code) == "string" then
        message = value.code .. ": " .. tostring(value.message or "network carrier failed")
    else
        message = tostring(value)
    end
    error(redact(message, secrets or {}), (level or 1) + 1)
end

local function cleanup_file(filesystem, directory, carrier)
    if carrier == nil or carrier.deleted then return true end
    local stated, observed = filesystem.stat_identity(carrier.path)
    if not stated then
        if type(observed) == "table" and observed.code == "NotFound" then
            carrier.deleted = true
            return true
        end
        return nil, observed
    end
    local admitted = carrier.mutable
        and same_object(carrier.identity, observed)
        or identity_equal(carrier.identity, observed)
    if not admitted then
        return nil, failure("CarrierChanged", "temporary network carrier identity changed")
    end
    local deleted, delete_error = filesystem.delete_verified(carrier.path, observed)
    if not deleted then return nil, delete_error end
    carrier.deleted = true
    local flushed, flush_error = filesystem.flush_directory(directory)
    if not flushed then return nil, flush_error end
    return true
end

local function cleanup_carriers(filesystem, directory, body_carrier, header_carrier)
    local first_error
    local body_ok, body_error = cleanup_file(filesystem, directory, body_carrier)
    if not body_ok then first_error = body_error end
    local header_ok, header_error = cleanup_file(filesystem, directory, header_carrier)
    if not header_ok and not first_error then first_error = header_error end
    if first_error then return nil, first_error end
    return true
end

local function write_private_file(filesystem, directory, path, bytes, limits, mutable)
    local created, handle_or_error = filesystem.create_new(path, limits.private_permissions)
    if not created then return nil, handle_or_error end
    local handle = handle_or_error
    local function abandon(identity)
        filesystem.close(handle)
        local carrier = { path = path, identity = identity, mutable = true }
        if not identity then
            local stated, observed = filesystem.stat_identity(path)
            if stated then carrier.identity = observed end
        end
        if carrier.identity then cleanup_file(filesystem, directory, carrier) end
    end
    for offset = 1, #bytes, limits.maximum_io_chunk_bytes do
        local chunk = bytes:sub(offset, offset + limits.maximum_io_chunk_bytes - 1)
        local written, write_error = filesystem.stream_write(handle, chunk)
        if not written then
            abandon()
            return nil, write_error
        end
    end
    local flushed, flush_error = filesystem.flush_file(handle)
    if not flushed then
        abandon()
        return nil, flush_error
    end
    local stated, identity_or_error = filesystem.stat_identity(handle)
    if not stated then
        abandon()
        return nil, identity_or_error
    end
    local closed, close_error = filesystem.close(handle)
    if not closed then
        local carrier = { path = path, identity = identity_or_error, mutable = true }
        cleanup_file(filesystem, directory, carrier)
        return nil, close_error
    end
    local directory_flushed, directory_error = filesystem.flush_directory(directory)
    if not directory_flushed then
        local carrier = { path = path, identity = identity_or_error, mutable = true }
        cleanup_file(filesystem, directory, carrier)
        return nil, directory_error
    end
    return {
        path = path,
        identity = identity_or_error,
        mutable = mutable == true,
        deleted = false,
    }
end

local function read_header_file(filesystem, carrier, maximum_bytes, maximum_chunk_bytes)
    local stated, before = filesystem.stat_identity(carrier.path)
    if not stated then return nil, before end
    if not same_object(carrier.identity, before) then
        return nil, failure("CarrierChanged", "response header carrier object changed")
    end
    if before.size > maximum_bytes then
        return nil, failure("HeaderLimit", "response headers exceed their release limit")
    end
    local opened, handle_or_error = filesystem.open_read(carrier.path)
    if not opened then return nil, handle_or_error end
    local handle = handle_or_error
    local handle_stated, opened_identity = filesystem.stat_identity(handle)
    if not handle_stated or not identity_equal(before, opened_identity) then
        filesystem.close(handle)
        return nil, handle_stated and failure(
            "CarrierChanged",
            "response header carrier changed while opening"
        ) or opened_identity
    end
    local parts, size = {}, 0
    while true do
        local remaining = maximum_bytes - size
        local request_bytes = math.min(maximum_chunk_bytes, math.max(remaining, 1))
        local read, chunk_or_error = filesystem.stream_read(handle, request_bytes)
        if not read then
            filesystem.close(handle)
            return nil, chunk_or_error
        end
        local chunk = chunk_or_error
        if #chunk.bytes > remaining then
            filesystem.close(handle)
            return nil, failure("HeaderLimit", "response headers exceed their release limit")
        end
        size = size + #chunk.bytes
        parts[#parts + 1] = chunk.bytes
        if chunk.eof then break end
        if #chunk.bytes == 0 then
            filesystem.close(handle)
            return nil, failure("FilesystemContract", "header reader made no progress")
        end
    end
    local final_stated, final_identity = filesystem.stat_identity(handle)
    local closed, close_error = filesystem.close(handle)
    if not closed then return nil, close_error end
    if not final_stated or not identity_equal(opened_identity, final_identity) then
        return nil, final_stated and failure(
            "CarrierChanged",
            "response header carrier changed while reading"
        ) or final_identity
    end
    local path_stated, path_identity = filesystem.stat_identity(carrier.path)
    if not path_stated or not identity_equal(final_identity, path_identity) then
        return nil, path_stated and failure(
            "CarrierChanged",
            "response header carrier changed after reading"
        ) or path_identity
    end
    carrier.identity = final_identity
    return table.concat(parts)
end

local function build_config(attempt, body_path, header_path, by_reference)
    local lines = {
        option_line("url", attempt.url),
        option_line("request", attempt.method),
    }
    for _, header in ipairs(attempt.public_headers) do
        lines[#lines + 1] = option_line("header", header.name .. ": " .. header.value)
    end
    for _, header in ipairs(attempt.secret_headers) do
        local value = assert(by_reference[header.secret_id .. "\0" .. header.destination])
        lines[#lines + 1] = option_line(
            "header",
            header.name .. ": " .. header.prefix .. value .. header.suffix
        )
    end
    lines[#lines + 1] = option_line("header", "Accept-Encoding: identity")
    lines[#lines + 1] = option_line("data-binary", "@" .. body_path)
    lines[#lines + 1] = option_line("dump-header", header_path)
    lines[#lines + 1] = option_line("output", "-")
    lines[#lines + 1] = option_line(
        "connect-timeout",
        milliseconds_as_seconds(attempt.connect_timeout_ms)
    )
    lines[#lines + 1] = option_line("max-time", milliseconds_as_seconds(attempt.total_timeout_ms))
    lines[#lines + 1] = option_line("retry", "0")
    lines[#lines + 1] = option_line("retry-all-errors", false)
    lines[#lines + 1] = option_line("location", false)
    lines[#lines + 1] = option_line("max-redirs", "0")
    lines[#lines + 1] = option_line("proto", "=http,https")
    lines[#lines + 1] = option_line("proto-redir", "=http,https")
    lines[#lines + 1] = option_line("compressed", false)
    lines[#lines + 1] = option_line("netrc", false)
    local proxy_url = attempt.proxy.url
    if attempt.proxy.secret_id then
        proxy_url = assert(by_reference[
            attempt.proxy.secret_id .. "\0" .. attempt.proxy.destination
        ])
    end
    lines[#lines + 1] = option_line("proxy", proxy_url or "")
    lines[#lines + 1] = option_line("noproxy", attempt.proxy.no_proxy)
    lines[#lines + 1] = option_line("cacert", attempt.ca_bundle_path)
    return table.concat(lines, "\n") .. "\n"
end

---Creates a curl transport factory with release-owned component and carrier paths.
-- Configured secret values are accepted only as typed references and revealed
-- while constructing the anonymous stdin config carrier for one attempt.
-- @param ports table Narrow filesystem and process services.
-- @param options table Release paths, environment, permissions, and hard caps.
-- @return table|nil service Immutable curl transport service.
-- @return table|nil err Structured construction failure.
function M.new(ports, options)
    if type(ports) ~= "table"
        or type(ports.filesystem) ~= "table"
        or type(ports.processes) ~= "table"
    then
        return nil, failure("InvalidNetworkPorts", "filesystem and process services are required")
    end
    for _, method in ipairs(REQUIRED_FILESYSTEM_METHODS) do
        if type(ports.filesystem[method]) ~= "function" then
            return nil, failure("InvalidNetworkPorts", "filesystem omits " .. method)
        end
    end
    if type(ports.processes.new_component_port) ~= "function" then
        return nil, failure("InvalidNetworkPorts", "structured component process port is required")
    end
    if type(options) ~= "table" then
        return nil, failure("InvalidNetworkOptions", "network release options are required")
    end
    local allowed = {
        curl_executable = true,
        bundled_ca_path = true,
        temporary_directory = true,
        private_permissions = true,
        maximum_body_bytes = true,
        maximum_header_bytes = true,
        maximum_config_bytes = true,
        maximum_output_bytes = true,
        maximum_io_chunk_bytes = true,
        maximum_attempt_id_bytes = true,
        maximum_connect_timeout_ms = true,
        maximum_total_timeout_ms = true,
        component_environment = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidNetworkOptions", "network options have an unknown field")
        end
    end
    if not valid_absolute_path(options.curl_executable)
        or not valid_absolute_path(options.bundled_ca_path)
        or not valid_absolute_path(options.temporary_directory)
    then
        return nil, failure("InvalidNetworkPath", "curl, CA, and temporary paths must be absolute")
    end
    if options.private_permissions ~= 384 then
        return nil, failure("InvalidNetworkPermissions", "network carriers require owner-only mode 0600")
    end
    for _, name in ipairs({
        "maximum_body_bytes",
        "maximum_header_bytes",
        "maximum_config_bytes",
        "maximum_output_bytes",
        "maximum_io_chunk_bytes",
        "maximum_attempt_id_bytes",
        "maximum_connect_timeout_ms",
        "maximum_total_timeout_ms",
    }) do
        if not valid_integer(options[name], 1) then
            return nil, failure("InvalidNetworkLimit", "network release hard caps are required")
        end
    end
    if type(options.component_environment) ~= "table" then
        return nil, failure("InvalidNetworkEnvironment", "clean component environment is required")
    end
    local limits = {
        curl_executable = options.curl_executable,
        bundled_ca_path = options.bundled_ca_path,
        temporary_directory = options.temporary_directory,
        private_permissions = options.private_permissions,
        maximum_body_bytes = options.maximum_body_bytes,
        maximum_header_bytes = options.maximum_header_bytes,
        maximum_config_bytes = options.maximum_config_bytes,
        maximum_output_bytes = options.maximum_output_bytes,
        maximum_io_chunk_bytes = options.maximum_io_chunk_bytes,
        maximum_attempt_id_bytes = options.maximum_attempt_id_bytes,
        maximum_connect_timeout_ms = options.maximum_connect_timeout_ms,
        maximum_total_timeout_ms = options.maximum_total_timeout_ms,
        component_environment = copy_string_map(options.component_environment),
    }
    local service = {}

    ---Creates one POST attempt AsyncPort without revealing or persisting secrets.
    -- Files and the native process are created only when start is called.
    -- @param spec table Frozen request snapshot and typed secret references.
    -- @return table|nil port Network AsyncPort in the created state.
    -- @return table|nil err Structured validation failure.
    function service.new_attempt(spec)
        local attempt, attempt_error = validate_attempt(spec, limits)
        if not attempt then return nil, attempt_error end
        local state = "created"
        local process_port
        local body_carrier, header_carrier
        local used_secrets = {}
        local port = {}

        local function cleanup()
            return cleanup_carriers(
                ports.filesystem,
                limits.temporary_directory,
                body_carrier,
                header_carrier
            )
        end

        function port:start(now)
            if state ~= "created" then error("network port is " .. state, 2) end
            if not valid_integer(now, 0) then error("network start time is invalid", 2) end
            local revealed, by_reference_or_error = reveal_secrets(attempt)
            if not revealed then raise_redacted(by_reference_or_error, {}, 1) end
            used_secrets = revealed
            local public_values = { attempt.url, attempt.body, attempt.ca_bundle_path }
            for _, header in ipairs(attempt.public_headers) do
                public_values[#public_values + 1] = header.name
                public_values[#public_values + 1] = header.value
            end
            if attempt.proxy.url then public_values[#public_values + 1] = attempt.proxy.url end
            public_values[#public_values + 1] = attempt.proxy.no_proxy
            local scanned, scan_error = scan_public_bytes(attempt.secret_source, public_values)
            if not scanned then raise_redacted(scan_error, used_secrets, 1) end

            local prefix = "yaca-curl-" .. attempt.attempt_id
            local body_path = join_path(
                limits.temporary_directory,
                prefix .. ".body.tmp"
            )
            local header_path = join_path(
                limits.temporary_directory,
                prefix .. ".headers.tmp"
            )
            body_carrier, attempt_error = write_private_file(
                ports.filesystem,
                limits.temporary_directory,
                body_path,
                attempt.body,
                limits,
                false
            )
            if not body_carrier then
                state = "failed"
                raise_redacted(attempt_error, used_secrets, 1)
            end
            header_carrier, attempt_error = write_private_file(
                ports.filesystem,
                limits.temporary_directory,
                header_path,
                "",
                limits,
                true
            )
            if not header_carrier then
                cleanup()
                state = "failed"
                raise_redacted(attempt_error, used_secrets, 1)
            end
            local configuration = build_config(
                attempt,
                body_path,
                header_path,
                by_reference_or_error
            )
            if #configuration > limits.maximum_config_bytes then
                cleanup()
                state = "failed"
                raise_redacted(
                    failure("ConfigLimit", "curl config carrier exceeds its release limit"),
                    used_secrets,
                    1
                )
            end
            local component, component_error = ports.processes.new_component_port({
                executable = limits.curl_executable,
                arguments = copy_array(FIXED_CURL_ARGUMENTS),
                cwd = limits.temporary_directory,
                environment = copy_string_map(limits.component_environment),
                stdin_bytes = configuration,
                output_limit_bytes = limits.maximum_output_bytes,
            })
            configuration = nil
            if not component then
                cleanup()
                state = "failed"
                raise_redacted(component_error, used_secrets, 1)
            end
            process_port = component
            local started, start_error = pcall(process_port.start, process_port, now)
            if not started then
                cleanup()
                state = "failed"
                raise_redacted(start_error, used_secrets, 1)
            end
            state = "started"
            return true
        end

        function port:poll(now, budget)
            if state ~= "started" then error("network port is " .. state, 2) end
            local called, process_events = pcall(process_port.poll, process_port, now, budget)
            if not called then raise_redacted(process_events, used_secrets, 1) end
            local events = {}
            for _, event in ipairs(process_events) do
                if event.kind == "io_progress" and event.stream == "stdout" then
                    events[#events + 1] = { kind = "body_chunk", bytes = event.bytes }
                elseif event.kind == "io_progress" and event.stream == "stderr" then
                    events[#events + 1] = { kind = "diagnostic_progress" }
                elseif event.kind == "io_terminal" then
                    events[#events + 1] = {
                        kind = "transport_terminal",
                        outcome = event.outcome,
                    }
                else
                    raise_redacted(
                        failure("ProcessContract", "component process emitted an unknown event"),
                        used_secrets,
                        1
                    )
                end
            end
            return events
        end

        function port:cancel(now)
            if state ~= "started" then error("network port is " .. state, 2) end
            local called, accepted = pcall(process_port.cancel, process_port, now)
            if not called then raise_redacted(accepted, used_secrets, 1) end
            return accepted
        end

        function port:join(deadline)
            if state ~= "started" then error("network port is " .. state, 2) end
            local called, result = pcall(process_port.join, process_port, deadline)
            if not called then
                cleanup()
                state = "failed"
                raise_redacted(result, used_secrets, 1)
            end
            local headers, header_error = read_header_file(
                ports.filesystem,
                header_carrier,
                limits.maximum_header_bytes,
                limits.maximum_io_chunk_bytes
            )
            if not headers then
                cleanup()
                state = "failed"
                raise_redacted(header_error, used_secrets, 1)
            end
            local cleaned, cleanup_error = cleanup()
            if not cleaned then
                state = "failed"
                raise_redacted(cleanup_error, used_secrets, 1)
            end
            state = "joined"
            return {
                outcome = result.outcome,
                exit_kind = result.exit_kind,
                exit_code = result.exit_code,
                signal_or_exception = result.signal_or_exception,
                response_body = result.stdout,
                response_headers = headers,
                diagnostic = redact(result.stderr, used_secrets),
                body_truncated = result.stdout_truncated,
                diagnostic_truncated = result.stderr_truncated,
                decoder = result.decoder,
                duration_ms = result.duration_ms,
                descendants_proven_stopped = result.descendants_proven_stopped,
            }
        end

        function port:close()
            if state ~= "started" and state ~= "joined" then
                error("network port is " .. state, 2)
            end
            local called, close_result = pcall(process_port.close, process_port)
            local cleaned, cleanup_error = cleanup()
            state = "closed"
            if not called then raise_redacted(close_result, used_secrets, 1) end
            if not cleaned then raise_redacted(cleanup_error, used_secrets, 1) end
            used_secrets = {}
            return true
        end

        return port
    end

    service.capabilities = readonly({
        curl_executable = limits.curl_executable,
        fixed_arguments = readonly(copy_array(FIXED_CURL_ARGUMENTS), "curl arguments"),
        first_option = "--disable",
        shell = false,
        config_carrier = "anonymous-stdin-pipe",
        secret_in_argv = false,
        secret_in_environment = false,
        request_body_carrier = "owner-only-create-new-temp",
        response_header_carrier = "owner-only-create-new-temp",
        ambient_environment = "clean-allowlist",
        curl_retry = 0,
        automatic_redirect = false,
        protocols = "http,https",
        content_encoding = "identity",
        target_qualified = false,
        qualification = "modern-carrier-candidate;target-curl-tls-proxy-ca-pending",
    }, "network capabilities")

    return readonly(service, "network service")
end

return M
