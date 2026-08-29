--[[
File: network.lua
Date: 2026-08-30
Author: WaterRun
Description: Builds a secret-safe curl carrier over structured process ports.
]]

local text = require("text")

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

local function validate_sse_options(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidSseOptions", "SSE release limits are required")
    end
    local allowed = {
        maximum_line_bytes = true,
        maximum_event_bytes = true,
        maximum_buffered_bytes = true,
        maximum_events_per_push = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidSseOptions", "SSE options contain an unknown field")
        end
    end
    for name in pairs(allowed) do
        if not valid_integer(options[name], 1) then
            return nil, failure("InvalidSseOptions", "SSE limits must be positive integers")
        end
    end
    if options.maximum_line_bytes > options.maximum_buffered_bytes
        or options.maximum_event_bytes > options.maximum_buffered_bytes
    then
        return nil, failure("InvalidSseOptions", "SSE sub-limits exceed the buffer limit")
    end
    return {
        maximum_line_bytes = options.maximum_line_bytes,
        maximum_event_bytes = options.maximum_event_bytes,
        maximum_buffered_bytes = options.maximum_buffered_bytes,
        maximum_events_per_push = options.maximum_events_per_push,
    }
end

local function split_sse_field(line)
    local colon = line:find(":", 1, true)
    if not colon then return line, "" end
    local value = line:sub(colon + 1)
    if value:sub(1, 1) == " " then value = value:sub(2) end
    return line:sub(1, colon - 1), value
end

---Creates a bounded incremental Server-Sent Events parser.
-- It accepts LF, CRLF, and CR at arbitrary chunk boundaries. Unknown fields,
-- comments, id resume semantics, and retry overrides never become canonical
-- transport behavior. A leading UTF-8 BOM and an unterminated final event are
-- stable protocol errors.
-- @param options table Required line, event, buffer, and output limits.
-- @return table|nil parser Incremental push/finish parser.
-- @return table|nil err Structured construction failure.
function M.new_sse_parser(options)
    local limits, options_error = validate_sse_options(options)
    if not limits then return nil, options_error end
    local buffer = ""
    local prefix_checked = false
    local data_parts = {}
    local has_data = false
    local event_name
    local last_id
    local event_bytes = 0
    local state = "open"
    local sticky_error
    local parser = {}

    local function fail(code, message)
        sticky_error = failure(code, message)
        state = "failed"
        return nil, sticky_error
    end

    local function reset_event()
        data_parts = {}
        has_data = false
        event_name = nil
        event_bytes = 0
    end

    local function process_line(line)
        if #line > limits.maximum_line_bytes then
            return fail("SseLineLimit", "SSE line exceeds its release limit")
        end
        local valid = text.validate_utf8(line)
        if not valid then return fail("SseUtf8", "SSE line is not strict UTF-8") end
        if line == "" then
            local event
            if has_data then
                local data = table.concat(data_parts, "\n")
                event = {
                    kind = "sse_event",
                    event = (event_name == nil or event_name == "") and "message"
                        or event_name,
                    data = data,
                }
                if last_id ~= nil then event.id = last_id end
                event = readonly(event, "SSE event")
            end
            reset_event()
            return true, event
        end
        event_bytes = event_bytes + #line + 1
        if event_bytes > limits.maximum_event_bytes then
            return fail("SseEventLimit", "SSE event exceeds its release limit")
        end
        if line:sub(1, 1) == ":" then return true end
        local field, value = split_sse_field(line)
        if field == "event" then
            event_name = value
        elseif field == "data" then
            data_parts[#data_parts + 1] = value
            has_data = true
        elseif field == "id" then
            if not value:find("\0", 1, true) then last_id = value end
        elseif field == "retry" then
            -- Provider-controlled SSE retry is intentionally ignored. Runtime
            -- owns the frozen logical-request retry snapshot.
        end
        return true
    end

    local function check_buffer_limit()
        if #buffer + event_bytes > limits.maximum_buffered_bytes then
            return fail("SseBufferLimit", "SSE parser buffer exceeds its release limit")
        end
        return true
    end

    local function check_prefix()
        if prefix_checked then return true end
        local bom = string.char(0xEF, 0xBB, 0xBF)
        local comparable = math.min(#buffer, #bom)
        if buffer:sub(1, comparable) == bom:sub(1, comparable) and #buffer < #bom then
            return false
        end
        prefix_checked = true
        if buffer:sub(1, #bom) == bom then
            return fail("SseBom", "leading UTF-8 BOM is forbidden")
        end
        return true
    end

    local function drain(ending)
        local events = {}
        while true do
            local terminator_index, terminator_byte
            for index = 1, #buffer do
                local byte = buffer:byte(index)
                if byte == 0x0A or byte == 0x0D then
                    terminator_index, terminator_byte = index, byte
                    break
                end
            end
            if not terminator_index then break end
            if terminator_byte == 0x0D and terminator_index == #buffer and not ending then
                break
            end
            local consumed = 1
            if terminator_byte == 0x0D and buffer:byte(terminator_index + 1) == 0x0A then
                consumed = 2
            end
            local line = buffer:sub(1, terminator_index - 1)
            buffer = buffer:sub(terminator_index + consumed)
            local ok, event_or_error = process_line(line)
            if not ok then return nil, event_or_error end
            if event_or_error then
                events[#events + 1] = event_or_error
                if #events > limits.maximum_events_per_push then
                    return fail("SseOutputLimit", "one SSE parse step produced too many events")
                end
            end
        end
        if #buffer > limits.maximum_line_bytes then
            return fail("SseLineLimit", "SSE line exceeds its release limit")
        end
        local within, limit_error = check_buffer_limit()
        if not within then return nil, limit_error end
        return events
    end

    ---Consumes one exact response byte chunk.
    -- @param bytes string Bounded raw response bytes.
    -- @return table|nil events Immutable SSE event objects.
    -- @return table|nil err Sticky protocol or resource failure.
    function parser:push(bytes)
        if state == "failed" then return nil, sticky_error end
        if state ~= "open" then
            return nil, failure("SseState", "SSE parser is already finished")
        end
        if type(bytes) ~= "string" then
            return nil, failure("InvalidSseBytes", "SSE input must be a byte string")
        end
        local available = limits.maximum_buffered_bytes - #buffer - event_bytes
        if #bytes > available then
            return fail("SseBufferLimit", "SSE parser buffer exceeds its release limit")
        end
        buffer = buffer .. bytes
        local within, limit_error = check_buffer_limit()
        if not within then return nil, limit_error end
        local checked, prefix_error = check_prefix()
        if checked == nil then return nil, prefix_error end
        if checked == false then return {} end
        return drain(false)
    end

    ---Closes the byte stream without synthesizing a final SSE event.
    -- @return table|nil events Events completed by a final CR delimiter.
    -- @return table|nil err Incomplete or sticky protocol failure.
    function parser:finish()
        if state == "failed" then return nil, sticky_error end
        if state ~= "open" then
            return nil, failure("SseState", "SSE parser is already finished")
        end
        if not prefix_checked and buffer == "" then
            state = "finished"
            return {}
        end
        local checked, prefix_error = check_prefix()
        if checked == nil then return nil, prefix_error end
        if checked == false then return fail("SseIncomplete", "SSE stream ends in a partial prefix") end
        local events, drain_error = drain(true)
        if not events then return nil, drain_error end
        if buffer ~= "" or has_data or event_bytes ~= 0 then
            return fail("SseIncomplete", "SSE stream ends with an unterminated event")
        end
        state = "finished"
        return events
    end

    function parser:status()
        return state, sticky_error
    end

    parser.limits = readonly({
        maximum_line_bytes = limits.maximum_line_bytes,
        maximum_event_bytes = limits.maximum_event_bytes,
        maximum_buffered_bytes = limits.maximum_buffered_bytes,
        maximum_events_per_push = limits.maximum_events_per_push,
    }, "SSE limits")
    return readonly(parser, "SSE parser")
end

local MONTH_NUMBER = {
    Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
    Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12,
}

local function leap_year(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function days_in_month(year, month)
    local values = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if month == 2 and leap_year(year) then return 29 end
    return values[month]
end

local function days_from_civil(year, month, day)
    year = year - (month <= 2 and 1 or 0)
    local era = (year >= 0 and year or year - 399) // 400
    local year_of_era = year - era * 400
    local adjusted_month = month + (month > 2 and -3 or 9)
    local day_of_year = (153 * adjusted_month + 2) // 5 + day - 1
    local day_of_era = year_of_era * 365 + year_of_era // 4
        - year_of_era // 100 + day_of_year
    return era * 146097 + day_of_era - 719468
end

local function utc_epoch(year, month, day, hour, minute, second)
    if not valid_integer(year, 1601)
        or not valid_integer(month, 1)
        or month > 12
        or not valid_integer(day, 1)
        or day > days_in_month(year, month)
        or not valid_integer(hour, 0)
        or hour > 23
        or not valid_integer(minute, 0)
        or minute > 59
        or not valid_integer(second, 0)
        or second > 59
    then
        return nil
    end
    return days_from_civil(year, month, day) * 86400 + hour * 3600 + minute * 60 + second
end

local function parse_http_date(value)
    local day, month_name, year, hour, minute, second = value:match(
        "^%a%a%a, (%d%d) (%a%a%a) (%d%d%d%d) (%d%d):(%d%d):(%d%d) GMT$"
    )
    if not day then
        local short_year
        day, month_name, short_year, hour, minute, second = value:match(
            "^%a+, (%d%d)%-(%a%a%a)%-(%d%d) (%d%d):(%d%d):(%d%d) GMT$"
        )
        if day then
            local numeric_year = tonumber(short_year)
            year = tostring(numeric_year >= 70 and 1900 + numeric_year or 2000 + numeric_year)
        end
    end
    if not day then
        month_name, day, hour, minute, second, year = value:match(
            "^%a%a%a (%a%a%a) +(%d%d?) (%d%d):(%d%d):(%d%d) (%d%d%d%d)$"
        )
    end
    local month = month_name and MONTH_NUMBER[month_name]
    if not month then return nil end
    return utc_epoch(
        tonumber(year),
        month,
        tonumber(day),
        tonumber(hour),
        tonumber(minute),
        tonumber(second)
    )
end

---Parses a Retry-After delta or HTTP-date into a bounded millisecond wait.
-- @param value string Exact single header value.
-- @param now_epoch_seconds integer Trusted current UTC seconds for date form.
-- @param maximum_ms integer Uncloseable release wait maximum.
-- @return integer|nil wait_ms Nonnegative minimum wait.
-- @return table|nil err Invalid or over-limit header failure.
function M.parse_retry_after(value, now_epoch_seconds, maximum_ms)
    if type(value) ~= "string"
        or not valid_integer(now_epoch_seconds, 0)
        or not valid_integer(maximum_ms, 0)
    then
        return nil, failure("InvalidRetryAfter", "Retry-After inputs are invalid")
    end
    value = value:match("^[ \t]*(.-)[ \t]*$")
    local wait_ms
    if value:match("^%d+$") then
        local seconds = tonumber(value)
        if not seconds or seconds > math.maxinteger // 1000 then
            return nil, failure("RetryAfterLimit", "Retry-After exceeds its release limit")
        end
        wait_ms = seconds * 1000
    else
        local target_epoch = parse_http_date(value)
        if not target_epoch then
            return nil, failure("InvalidRetryAfter", "Retry-After is not a valid delta or HTTP-date")
        end
        local seconds = math.max(0, target_epoch - now_epoch_seconds)
        if seconds > math.maxinteger // 1000 then
            return nil, failure("RetryAfterLimit", "Retry-After exceeds its release limit")
        end
        wait_ms = seconds * 1000
    end
    if wait_ms > maximum_ms then
        return nil, failure("RetryAfterLimit", "Retry-After exceeds its release limit")
    end
    return wait_ms
end

local function validate_http_header_options(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidHeaderOptions", "HTTP header limits are required")
    end
    local allowed = {
        maximum_bytes = true,
        maximum_line_bytes = true,
        maximum_lines = true,
    }
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidHeaderOptions", "HTTP header options have an unknown field")
        end
    end
    for name in pairs(allowed) do
        if not valid_integer(options[name], 1) then
            return nil, failure("InvalidHeaderOptions", "HTTP header limits must be positive")
        end
    end
    if options.maximum_line_bytes > options.maximum_bytes then
        return nil, failure("InvalidHeaderOptions", "HTTP line limit exceeds total bytes")
    end
    return options
end

local function parse_header_block(block, limits, total_lines)
    local lines = {}
    local cursor = 1
    while true do
        local boundary = block:find("\r\n", cursor, true)
        local line
        if boundary then
            line = block:sub(cursor, boundary - 1)
            cursor = boundary + 2
        else
            line = block:sub(cursor)
        end
        total_lines = total_lines + 1
        if total_lines > limits.maximum_lines then
            return nil, failure("HeaderLineLimit", "HTTP headers contain too many lines")
        end
        if #line > limits.maximum_line_bytes then
            return nil, failure("HeaderLineLimit", "HTTP header line exceeds its limit")
        end
        lines[#lines + 1] = line
        if not boundary then break end
    end
    local version, status_text, reason
    if lines[1] then
        version, status_text, reason = lines[1]:match(
            "^HTTP/(%d[%d%.]*) (%d%d%d)(.*)$"
        )
    end
    local status = tonumber(status_text)
    if not version or not status or status < 100 or status > 599 then
        return nil, failure("InvalidHttpHeaders", "HTTP status line is invalid")
    end
    reason = reason:match("^[ \t]*(.-)[ \t]*$")
    local headers = {}
    for index = 2, #lines do
        local line = lines[index]
        if line:sub(1, 1):match("[ \t]") then
            return nil, failure("InvalidHttpHeaders", "obsolete folded HTTP header is forbidden")
        end
        local name, value = line:match("^([^:]+):(.*)$")
        if not valid_header_name(name) or value:find("[\0\r\n]") then
            return nil, failure("InvalidHttpHeaders", "HTTP response header is invalid")
        end
        value = value:match("^[ \t]*(.-)[ \t]*$")
        local normalized = name:lower()
        headers[normalized] = headers[normalized] or {}
        headers[normalized][#headers[normalized] + 1] = value
    end
    local frozen_headers = {}
    for name, values in pairs(headers) do
        frozen_headers[name] = readonly(copy_array(values), "HTTP header values")
    end
    return readonly({
        version = version,
        status = status,
        reason = reason,
        headers = readonly(frozen_headers, "HTTP headers"),
    }, "HTTP response head"), total_lines
end

---Parses curl's bounded response-header carrier and selects the final block.
-- Interim and proxy blocks remain noncanonical; the last response block is the
-- authority used for status, redirect, and retry decisions.
-- @param bytes string Exact header carrier bytes.
-- @param options table Total, line, and line-count limits.
-- @return table|nil response Immutable final response head.
-- @return table|nil err Structured syntax or limit failure.
function M.parse_http_headers(bytes, options)
    local limits, options_error = validate_http_header_options(options)
    if not limits then return nil, options_error end
    if type(bytes) ~= "string" or #bytes > limits.maximum_bytes then
        return nil, failure("HeaderLimit", "HTTP response headers exceed their limit")
    end
    if bytes == "" or bytes:find("\0", 1, true) or bytes:sub(-4) ~= "\r\n\r\n" then
        return nil, failure("InvalidHttpHeaders", "HTTP response headers are incomplete")
    end
    local normalized = bytes:gsub("\r\n", "")
    if normalized:find("[\r\n]") then
        return nil, failure("InvalidHttpHeaders", "HTTP response headers use a bare line ending")
    end
    local blocks, cursor = {}, 1
    while cursor <= #bytes do
        local boundary = bytes:find("\r\n\r\n", cursor, true)
        if not boundary then
            return nil, failure("InvalidHttpHeaders", "HTTP response header block is incomplete")
        end
        blocks[#blocks + 1] = bytes:sub(cursor, boundary - 1)
        cursor = boundary + 4
    end
    local parsed, total_lines = {}, 0
    for _, block in ipairs(blocks) do
        local response, second = parse_header_block(block, limits, total_lines)
        if not response then return nil, second end
        total_lines = second
        parsed[#parsed + 1] = response
    end
    return parsed[#parsed]
end

---Returns one unambiguous response header value.
-- @param response table Parsed response returned by parse_http_headers.
-- @param name string Case-insensitive field name.
-- @return string|nil value Exact trimmed field value when present once.
-- @return table|nil err Duplicate or invalid selector failure.
function M.single_header(response, name)
    if type(response) ~= "table" or type(response.headers) ~= "table"
        or not valid_header_name(name)
    then
        return nil, failure("InvalidHeaderSelector", "parsed response and header name are required")
    end
    local values = response.headers[name:lower()]
    if values == nil then return nil end
    if #values ~= 1 then
        return nil, failure("AmbiguousHttpHeader", "security-sensitive HTTP header is duplicated")
    end
    return values[1]
end

local function remove_dot_segments(path)
    local input, output = path, ""
    local function remove_last_segment()
        output = output:gsub("/?[^/]*$", "")
    end
    while input ~= "" do
        if input:sub(1, 3) == "../" then
            input = input:sub(4)
        elseif input:sub(1, 2) == "./" then
            input = input:sub(3)
        elseif input:sub(1, 3) == "/./" then
            input = "/" .. input:sub(4)
        elseif input == "/." then
            input = "/"
        elseif input:sub(1, 4) == "/../" then
            input = "/" .. input:sub(5)
            remove_last_segment()
        elseif input == "/.." then
            input = "/"
            remove_last_segment()
        elseif input == "." or input == ".." then
            input = ""
        else
            local boundary
            if input:sub(1, 1) == "/" then
                boundary = input:find("/", 2, true)
            else
                boundary = input:find("/", 1, true)
            end
            if boundary then
                output = output .. input:sub(1, boundary - 1)
                input = input:sub(boundary)
            else
                output = output .. input
                input = ""
            end
        end
    end
    return output == "" and "/" or output
end

local function parse_network_url(value)
    if type(value) ~= "string"
        or value == ""
        or value:find("[%z\1-\32\127]")
        or value:find("\\", 1, true)
    then
        return nil, failure("InvalidUrl", "redirect URL contains invalid bytes")
    end
    local scheme, authority, suffix = value:match(
        "^([A-Za-z][A-Za-z0-9+%.%-]*)://([^/%?#]+)(.*)$"
    )
    if not scheme then return nil, failure("InvalidUrl", "redirect URL is not absolute") end
    scheme = scheme:lower()
    if scheme ~= "http" and scheme ~= "https" then
        return nil, failure("InvalidUrl", "redirect URL scheme is not HTTP or HTTPS")
    end
    if authority:find("@", 1, true) then
        return nil, failure("InvalidUrl", "redirect URL cannot contain credentials")
    end
    local host, display_host, port_text
    if authority:sub(1, 1) == "[" then
        local close = authority:find("]", 2, true)
        if not close then return nil, failure("InvalidUrl", "IPv6 host is not bracketed") end
        host = authority:sub(2, close - 1):lower()
        display_host = "[" .. host .. "]"
        local remainder = authority:sub(close + 1)
        if remainder ~= "" then port_text = remainder:match("^:(%d+)$") end
        if remainder ~= "" and not port_text then
            return nil, failure("InvalidUrl", "redirect URL port is invalid")
        end
        if host == "" or host:find("[^0-9a-f:%.]") then
            return nil, failure("InvalidUrl", "IPv6 host bytes are invalid")
        end
    else
        local first_colon = authority:find(":", 1, true)
        local last_colon = authority:match("^.*():")
        if first_colon and first_colon ~= last_colon then
            return nil, failure("InvalidUrl", "IPv6 host must use brackets")
        end
        if last_colon then
            host = authority:sub(1, last_colon - 1)
            port_text = authority:sub(last_colon + 1)
        else
            host = authority
        end
        host = host:lower()
        display_host = host
        if host == "" or host:find("[^a-z0-9%.%-%_]") then
            return nil, failure("InvalidUrl", "redirect host must be normalized ASCII")
        end
        if port_text ~= nil and not port_text:match("^%d+$") then
            return nil, failure("InvalidUrl", "redirect URL port is invalid")
        end
    end
    local port = port_text and tonumber(port_text) or (scheme == "https" and 443 or 80)
    if not port or port < 1 or port > 65535 then
        return nil, failure("InvalidUrl", "redirect URL port is outside its range")
    end
    local fragment = suffix:find("#", 1, true)
    if fragment then suffix = suffix:sub(1, fragment - 1) end
    if suffix == "" then suffix = "/" end
    if suffix:sub(1, 1) == "?" then suffix = "/" .. suffix end
    if suffix:sub(1, 1) ~= "/" then
        return nil, failure("InvalidUrl", "redirect URL path is invalid")
    end
    local path, query = suffix:match("^([^?]*)(.*)$")
    path = remove_dot_segments(path)
    local rendered_authority = display_host
    if port_text ~= nil then rendered_authority = rendered_authority .. ":" .. tostring(port) end
    return {
        scheme = scheme,
        host = host,
        display_host = display_host,
        port = port,
        explicit_port = port_text ~= nil,
        origin = scheme .. "://" .. display_host .. ":" .. tostring(port),
        path = path,
        query = query,
        url = scheme .. "://" .. rendered_authority .. path .. query,
        canonical_url = scheme .. "://" .. display_host .. ":" .. tostring(port)
            .. path .. query,
    }
end

local function resolve_redirect(source, location)
    local base, base_error = parse_network_url(source)
    if not base then return nil, base_error end
    if type(location) ~= "string"
        or location == ""
        or location:find("[%z\1-\32\127]")
        or location:find("\\", 1, true)
    then
        return nil, failure("InvalidRedirect", "redirect Location bytes are invalid")
    end
    local without_fragment = location:match("^([^#]*)")
    if without_fragment:match("^[A-Za-z][A-Za-z0-9+%.%-]*://") then
        return parse_network_url(without_fragment)
    end
    if without_fragment:sub(1, 2) == "//" then
        return parse_network_url(base.scheme .. ":" .. without_fragment)
    end
    local path_and_query
    if without_fragment == "" then
        path_and_query = base.path .. base.query
    elseif without_fragment:sub(1, 1) == "?" then
        path_and_query = base.path .. without_fragment
    elseif without_fragment:sub(1, 1) == "/" then
        path_and_query = without_fragment
    else
        local directory = base.path:match("^(.*)/") or ""
        path_and_query = directory .. "/" .. without_fragment
    end
    local path, query = path_and_query:match("^([^?]*)(.*)$")
    path = remove_dot_segments(path)
    local authority = base.display_host
    if base.explicit_port then authority = authority .. ":" .. tostring(base.port) end
    return parse_network_url(base.scheme .. "://" .. authority .. path .. query)
end

---Decides one explicit 307/308 redirect without asking curl to follow it.
-- @param spec table Status, source, Location, redirect count/history, and cap.
-- @return table|nil decision Immutable none/follow/reject decision.
-- @return table|nil err Invalid decision input.
function M.redirect_decision(spec)
    if type(spec) ~= "table" then
        return nil, failure("InvalidRedirect", "redirect decision spec must be a table")
    end
    local allowed = {
        status = true,
        source_url = true,
        location = true,
        redirect_count = true,
        maximum_redirects = true,
        history = true,
    }
    for key in pairs(spec) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidRedirect", "redirect decision has an unknown field")
        end
    end
    if not valid_integer(spec.status, 100)
        or spec.status > 599
        or not valid_integer(spec.redirect_count, 0)
        or not valid_integer(spec.maximum_redirects, 0)
        or dense_count(spec.history or {}) == nil
    then
        return nil, failure("InvalidRedirect", "redirect status, count, or history is invalid")
    end
    local source, source_error = parse_network_url(spec.source_url)
    if not source then return nil, source_error end
    if spec.status ~= 307 and spec.status ~= 308 then
        return readonly({ action = "none", status = spec.status }, "redirect decision")
    end
    if spec.redirect_count >= spec.maximum_redirects then
        return readonly({
            action = "reject",
            code = "RedirectLimit",
            status = spec.status,
            key_reused = false,
        }, "redirect decision")
    end
    local target, target_error = resolve_redirect(source.url, spec.location)
    if not target then return nil, target_error end
    if source.scheme == "https" and target.scheme == "http" then
        return readonly({
            action = "reject",
            code = "HttpsDowngrade",
            status = spec.status,
            key_reused = false,
        }, "redirect decision")
    end
    if source.origin ~= target.origin then
        return readonly({
            action = "reject",
            code = "CrossOriginRedirect",
            status = spec.status,
            key_reused = false,
        }, "redirect decision")
    end
    for _, prior in ipairs(spec.history or {}) do
        local parsed, prior_error = parse_network_url(prior)
        if not parsed then return nil, prior_error end
        if parsed.canonical_url == target.canonical_url then
            return readonly({
                action = "reject",
                code = "RedirectLoop",
                status = spec.status,
                key_reused = false,
            }, "redirect decision")
        end
    end
    return readonly({
        action = "follow",
        status = spec.status,
        target_url = target.url,
        origin = target.origin,
        redirect_number = spec.redirect_count + 1,
        key_reused = true,
    }, "redirect decision")
end

local RETRYABLE_CATEGORIES = {
    dns = true,
    connect = true,
    ["tls-before-body"] = true,
    ["http-429"] = true,
    ["http-503"] = true,
}

local NEVER_RETRY_CATEGORIES = {
    ["body-outcome-unknown"] = "unknown",
    ["outcome-unknown"] = "unknown",
    ["auth-4xx"] = "failed",
    ["ordinary-4xx"] = "failed",
    protocol = "failed",
    ["content-refusal"] = "failed",
    cancel = "cancelled",
}

local function validate_retry_manifest(manifest)
    if type(manifest) ~= "table" then
        return nil, failure("InvalidRetryManifest", "retry manifest is required")
    end
    local allowed = {
        identity = true,
        maximum_count = true,
        exponent = true,
        maximum_delay_ms = true,
        runtime_wait_cap_ms = true,
        deterministic_jitter_permille = true,
    }
    for key in pairs(manifest) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidRetryManifest", "retry manifest has an unknown field")
        end
    end
    if type(manifest.identity) ~= "string"
        or manifest.identity == ""
        or manifest.identity:find("\0", 1, true)
        or not valid_integer(manifest.maximum_count, 0)
        or manifest.maximum_count > math.maxinteger // 4
        or not valid_integer(manifest.exponent, 1)
        or not valid_integer(manifest.maximum_delay_ms, 0)
        or manifest.maximum_delay_ms > math.maxinteger // 2
        or not valid_integer(manifest.runtime_wait_cap_ms, 0)
        or manifest.runtime_wait_cap_ms > math.maxinteger // 2
        or not valid_integer(manifest.deterministic_jitter_permille, 0)
        or manifest.deterministic_jitter_permille > 1000
    then
        return nil, failure("InvalidRetryManifest", "retry manifest fields are invalid")
    end
    return {
        identity = manifest.identity,
        maximum_count = manifest.maximum_count,
        exponent = manifest.exponent,
        maximum_delay_ms = manifest.maximum_delay_ms,
        runtime_wait_cap_ms = manifest.runtime_wait_cap_ms,
        deterministic_jitter_permille = manifest.deterministic_jitter_permille,
    }
end

local function multiply_capped(value, multiplier, cap)
    if value == 0 or multiplier == 0 then return 0 end
    if value > cap // multiplier then return cap end
    return math.min(value * multiplier, cap)
end

local function fnv1a64_parts(bytes)
    local high, low = 0xCBF29CE4, 0x84222325
    local multiplier_low = 0x1B3
    for index = 1, #bytes do
        low = low ~ bytes:byte(index)
        local low_product = low * multiplier_low
        local next_low = low_product & 0xFFFFFFFF
        local carry = low_product // 0x100000000
        local next_high = (high * multiplier_low + low * 0x100 + carry) & 0xFFFFFFFF
        high, low = next_high, next_low
    end
    return high, low
end

local function unsigned64_mod(high, low, divisor)
    local base_mod = 0x100000000 % divisor
    return ((high % divisor) * base_mod + low % divisor) % divisor
end

---Calculates one deterministic, saturated retry delay from the frozen manifest.
-- @param logical_request_id string Stable local request identity.
-- @param retry_number integer One-based automatic retry number.
-- @param base_delay_ms integer Per-Model frozen base delay.
-- @param manifest table Versioned retry constants.
-- @return integer|nil delay_ms Deterministic bounded delay.
-- @return table|nil err Invalid input or manifest failure.
function M.retry_delay_ms(logical_request_id, retry_number, base_delay_ms, manifest)
    local admitted, manifest_error = validate_retry_manifest(manifest)
    if not admitted then return nil, manifest_error end
    if type(logical_request_id) ~= "string"
        or logical_request_id == ""
        or logical_request_id:find("\0", 1, true)
        or not valid_integer(retry_number, 1)
        or retry_number > admitted.maximum_count
        or not valid_integer(base_delay_ms, 0)
    then
        return nil, failure("InvalidRetryInput", "retry delay input is invalid")
    end
    local delay = math.min(base_delay_ms, admitted.maximum_delay_ms)
    for _ = 2, retry_number do
        delay = multiply_capped(delay, admitted.exponent, admitted.maximum_delay_ms)
    end
    local radius = (delay // 1000) * admitted.deterministic_jitter_permille
        + ((delay % 1000) * admitted.deterministic_jitter_permille) // 1000
    if radius == 0 then return delay end
    local modulus = radius * 2 + 1
    local material = admitted.identity .. "\0" .. logical_request_id
        .. "\0" .. tostring(retry_number)
    local high, low = fnv1a64_parts(material)
    local offset = unsigned64_mod(high, low, modulus) - radius
    return math.max(0, math.min(delay + offset, admitted.maximum_delay_ms))
end

local function minimum_deadline(spec)
    return math.min(
        spec.logical_deadline_at,
        spec.turn_deadline_at,
        spec.runtime_deadline_at
    )
end

local function validate_retry_controller_spec(spec)
    if type(spec) ~= "table" then
        return nil, failure("InvalidRetryController", "retry controller spec is required")
    end
    local allowed = {
        logical_request_id = true,
        initial_url = true,
        retry_count = true,
        base_delay_ms = true,
        maximum_redirects = true,
        logical_deadline_at = true,
        turn_deadline_at = true,
        runtime_deadline_at = true,
        manifest = true,
    }
    for key in pairs(spec) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidRetryController", "retry controller has an unknown field")
        end
    end
    local manifest, manifest_error = validate_retry_manifest(spec.manifest)
    if not manifest then return nil, manifest_error end
    local initial, url_error = parse_network_url(spec.initial_url)
    if not initial then return nil, url_error end
    if type(spec.logical_request_id) ~= "string"
        or spec.logical_request_id == ""
        or spec.logical_request_id:find("\0", 1, true)
        or not valid_integer(spec.retry_count, 0)
        or spec.retry_count > manifest.maximum_count
        or not valid_integer(spec.base_delay_ms, 0)
        or spec.base_delay_ms > manifest.maximum_delay_ms
        or not valid_integer(spec.maximum_redirects, 0)
        or spec.maximum_redirects > math.maxinteger // 4
        or not valid_integer(spec.logical_deadline_at, 0)
        or not valid_integer(spec.turn_deadline_at, 0)
        or not valid_integer(spec.runtime_deadline_at, 0)
    then
        return nil, failure("InvalidRetryController", "retry controller fields are invalid")
    end
    return {
        logical_request_id = spec.logical_request_id,
        initial_url = initial.url,
        retry_count = spec.retry_count,
        base_delay_ms = spec.base_delay_ms,
        maximum_redirects = spec.maximum_redirects,
        logical_deadline_at = spec.logical_deadline_at,
        turn_deadline_at = spec.turn_deadline_at,
        runtime_deadline_at = spec.runtime_deadline_at,
        manifest = manifest,
    }
end

local function immutable_decision(values)
    return readonly(values, "retry decision")
end

---Creates the single state source for attempts, redirects, retry waits, and cancel.
-- The controller never sleeps or starts I/O. It admits explicit attempt IDs and
-- returns immutable decisions that the runtime timer/event pump must execute.
-- @param spec table Logical identity, URL, retry snapshot, redirects, and deadlines.
-- @return table|nil controller Retry and redirect state machine.
-- @return table|nil err Structured construction failure.
function M.new_retry_controller(spec)
    local snapshot, spec_error = validate_retry_controller_spec(spec)
    if not snapshot then return nil, spec_error end
    local state = "ready"
    local current_url = snapshot.initial_url
    local history = { current_url }
    local redirect_count = 0
    local retry_number = 0
    local fallback_number = 0
    local attempts_started = 0
    local active
    local waiting
    local canonical_events = 0
    local used_attempt_ids = {}
    local terminal
    local last_now
    local controller = {}

    local function observe_now(now)
        if not valid_integer(now, 0) or last_now and now < last_now then
            return nil, failure("InvalidMonotonicTime", "retry controller time is invalid")
        end
        last_now = now
        return true
    end

    local function finish(outcome, code, detail)
        local values = {
            action = "finish",
            outcome = outcome,
            code = code,
            attempts = attempts_started,
            retries = retry_number,
            redirects = redirect_count,
            streaming_fallbacks = fallback_number,
            canonical_events = canonical_events,
        }
        if detail ~= nil then values.detail = detail end
        terminal = immutable_decision(values)
        state, active, waiting = "terminal", nil, nil
        return terminal
    end

    local function check_deadline(now)
        local deadline = minimum_deadline(snapshot)
        if now >= deadline then
            return nil, finish("failed", "RequestDeadlineExceeded", deadline)
        end
        return deadline
    end

    ---Admits exactly one fresh attempt after any returned wait has elapsed.
    function controller:start_attempt(attempt_id, now)
        local time_ok, time_error = observe_now(now)
        if not time_ok then return nil, time_error end
        if type(attempt_id) ~= "string"
            or attempt_id == ""
            or attempt_id:find("\0", 1, true)
            or used_attempt_ids[attempt_id]
        then
            return nil, failure("InvalidAttemptId", "attempt identity must be fresh and NUL-free")
        end
        if state == "waiting" then
            if now < waiting.resume_at then
                return nil, failure("RetryNotReady", "retry or redirect wait has not elapsed")
            end
            if waiting.target_url then current_url = waiting.target_url end
            waiting = nil
            state = "ready"
        end
        if state ~= "ready" then
            return nil, failure("RetryState", "retry controller cannot start an attempt in " .. state)
        end
        local deadline, deadline_error = check_deadline(now)
        if not deadline then return nil, deadline_error end
        local maximum_attempts = 2 + snapshot.retry_count + snapshot.maximum_redirects
        if attempts_started >= maximum_attempts then
            return nil, finish("failed", "AttemptLimit", maximum_attempts)
        end
        attempts_started = attempts_started + 1
        used_attempt_ids[attempt_id] = true
        active = {
            id = attempt_id,
            number = attempts_started,
            url = current_url,
            started_at = now,
        }
        state = "active"
        return readonly({
            attempt_id = active.id,
            attempt_number = active.number,
            url = active.url,
            retry_number = retry_number,
            redirect_count = redirect_count,
            deadline_at = deadline,
        }, "attempt admission")
    end

    ---Marks the first and subsequent canonical provider events for replay safety.
    function controller:observe_canonical_event(attempt_id, now)
        local time_ok, time_error = observe_now(now)
        if not time_ok then return nil, time_error end
        if state ~= "active" or not active or attempt_id ~= active.id then
            return nil, failure("RetryState", "canonical event does not belong to the active attempt")
        end
        canonical_events = canonical_events + 1
        return canonical_events
    end

    ---Abandons one streaming attempt before any canonical provider event and
    -- admits the contract's sole immediate non-streaming fallback attempt.
    -- Model semantics decide whether fallback is appropriate; this controller
    -- owns only attempt identity, replay safety, and the shared deadline.
    function controller:streaming_fallback(attempt_id, now)
        local time_ok, time_error = observe_now(now)
        if not time_ok then return nil, time_error end
        if state ~= "active" or not active or attempt_id ~= active.id then
            return nil, failure("RetryState", "streaming fallback does not match the active attempt")
        end
        if canonical_events > 0 then
            return finish("failed", "CanonicalEventReplayForbidden")
        end
        if fallback_number >= 1 then
            return finish("failed", "StreamingFallbackExhausted")
        end
        local deadline, deadline_error = check_deadline(now)
        if not deadline then return nil, deadline_error end
        active = nil
        fallback_number = fallback_number + 1
        waiting = immutable_decision({
            action = "wait",
            kind = "streaming-fallback",
            delay_ms = 0,
            resume_at = now,
            target_url = current_url,
            key_reused = true,
            streaming_fallback_number = fallback_number,
        })
        state = "waiting"
        return waiting
    end

    ---Finishes one active attempt and decides terminal, redirect, or bounded retry.
    -- observation.category is completed or one frozen retry matrix category;
    -- optional status/location drive explicit 307/308 handling, and optional
    -- retry_after_ms is already parsed against trusted UTC by parse_retry_after.
    function controller:finish_attempt(attempt_id, observation, now)
        local time_ok, time_error = observe_now(now)
        if not time_ok then return nil, time_error end
        if state ~= "active" or not active or attempt_id ~= active.id then
            return nil, failure("RetryState", "attempt result does not match the active attempt")
        end
        if type(observation) ~= "table" then
            return nil, failure("InvalidAttemptResult", "attempt observation must be a table")
        end
        local allowed = {
            category = true,
            status = true,
            location = true,
            retry_after_ms = true,
        }
        for key in pairs(observation) do
            if type(key) ~= "string" or not allowed[key] then
                return nil, failure("InvalidAttemptResult", "attempt observation has an unknown field")
            end
        end
        if type(observation.category) ~= "string" then
            return nil, failure("InvalidAttemptResult", "attempt category is required")
        end
        if observation.status ~= nil
            and (not valid_integer(observation.status, 100) or observation.status > 599)
        then
            return nil, failure("InvalidAttemptResult", "HTTP response status is invalid")
        end
        if observation.location ~= nil and type(observation.location) ~= "string" then
            return nil, failure("InvalidAttemptResult", "redirect Location is invalid")
        end
        if observation.retry_after_ms ~= nil
            and (not valid_integer(observation.retry_after_ms, 0)
                or observation.retry_after_ms > snapshot.manifest.runtime_wait_cap_ms)
        then
            return nil, failure("RetryAfterLimit", "Retry-After exceeds the Runtime wait cap")
        end
        local finished_active = active
        local finished_url = finished_active.url
        active = nil

        if observation.status == 307 or observation.status == 308 then
            if canonical_events > 0 then
                return finish("failed", "CanonicalEventReplayForbidden")
            end
            local redirect, redirect_error = M.redirect_decision({
                status = observation.status,
                source_url = finished_url,
                location = observation.location,
                redirect_count = redirect_count,
                maximum_redirects = snapshot.maximum_redirects,
                history = history,
            })
            if not redirect then
                state = "active"
                active = finished_active
                return nil, redirect_error
            end
            if redirect.action ~= "follow" then
                return finish("failed", redirect.code)
            end
            redirect_count = redirect.redirect_number
            history[#history + 1] = redirect.target_url
            waiting = immutable_decision({
                action = "wait",
                kind = "redirect",
                delay_ms = 0,
                resume_at = now,
                target_url = redirect.target_url,
                key_reused = true,
                redirect_number = redirect_count,
            })
            state = "waiting"
            return waiting
        end

        local category = observation.category
        if observation.status == 429 then
            category = "http-429"
        elseif observation.status == 503 then
            category = "http-503"
        elseif observation.status and observation.status >= 400 and observation.status <= 499 then
            category = (observation.status == 401 or observation.status == 403)
                and "auth-4xx" or "ordinary-4xx"
        end
        if category == "completed" then
            return finish("completed", "Completed")
        end
        local never_outcome = NEVER_RETRY_CATEGORIES[category]
        if never_outcome then
            return finish(never_outcome, category)
        end
        if not RETRYABLE_CATEGORIES[category] then
            state = "active"
            active = finished_active
            return nil, failure("InvalidAttemptResult", "attempt category is unknown")
        end
        if canonical_events > 0 then
            return finish("failed", "CanonicalEventReplayForbidden")
        end
        if retry_number >= snapshot.retry_count then
            return finish("failed", "RetryExhausted", category)
        end
        local next_retry = retry_number + 1
        local local_delay, delay_error = M.retry_delay_ms(
            snapshot.logical_request_id,
            next_retry,
            snapshot.base_delay_ms,
            snapshot.manifest
        )
        if not local_delay then
            state = "active"
            active = finished_active
            return nil, delay_error
        end
        local required_wait = math.max(local_delay, observation.retry_after_ms or 0)
        if required_wait > snapshot.manifest.runtime_wait_cap_ms then
            return finish("failed", "RetryWaitLimit", required_wait)
        end
        local deadline = minimum_deadline(snapshot)
        if required_wait > math.maxinteger - now or now + required_wait >= deadline then
            return finish("failed", "RetryBudgetExceeded", required_wait)
        end
        retry_number = next_retry
        waiting = immutable_decision({
            action = "wait",
            kind = "retry",
            category = category,
            retry_number = retry_number,
            local_delay_ms = local_delay,
            retry_after_ms = observation.retry_after_ms or 0,
            delay_ms = required_wait,
            resume_at = now + required_wait,
            target_url = current_url,
            key_reused = true,
        })
        state = "waiting"
        return waiting
    end

    ---Cancels active I/O or a pending wait and permanently closes auto retry.
    function controller:cancel(now)
        local time_ok, time_error = observe_now(now)
        if not time_ok then return nil, time_error end
        if state == "terminal" then return terminal end
        local cancel_active = state == "active"
        local active_attempt_id = cancel_active and active.id or nil
        terminal = immutable_decision({
            action = "finish",
            outcome = "cancelled",
            code = "cancel",
            attempts = attempts_started,
            retries = retry_number,
            redirects = redirect_count,
            streaming_fallbacks = fallback_number,
            canonical_events = canonical_events,
            cancel_active = cancel_active,
            active_attempt_id = active_attempt_id,
        })
        state, active, waiting = "terminal", nil, nil
        return terminal
    end

    function controller:pending()
        return waiting
    end

    function controller:status()
        return readonly({
            state = state,
            current_url = current_url,
            attempts = attempts_started,
            retries = retry_number,
            redirects = redirect_count,
            streaming_fallbacks = fallback_number,
            canonical_events = canonical_events,
            terminal = terminal,
        }, "retry controller status")
    end

    controller.snapshot = readonly({
        logical_request_id = snapshot.logical_request_id,
        initial_url = snapshot.initial_url,
        retry_count = snapshot.retry_count,
        base_delay_ms = snapshot.base_delay_ms,
        maximum_redirects = snapshot.maximum_redirects,
        logical_deadline_at = snapshot.logical_deadline_at,
        turn_deadline_at = snapshot.turn_deadline_at,
        runtime_deadline_at = snapshot.runtime_deadline_at,
        manifest_id = snapshot.manifest.identity,
        retry_exponent = snapshot.manifest.exponent,
        retry_max_delay_ms = snapshot.manifest.maximum_delay_ms,
        retry_jitter_permille = snapshot.manifest.deterministic_jitter_permille,
        runtime_wait_cap_ms = snapshot.manifest.runtime_wait_cap_ms,
    }, "retry snapshot")
    return readonly(controller, "retry controller")
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

    service.new_sse_parser = M.new_sse_parser
    service.parse_http_headers = M.parse_http_headers
    service.single_header = M.single_header
    service.parse_retry_after = M.parse_retry_after
    service.redirect_decision = M.redirect_decision
    service.new_retry_controller = M.new_retry_controller

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
        sse = "bounded-exact-lf-crlf-cr",
        redirects = "runtime-controlled-307-308-same-origin-only",
        retry = "runtime-controlled-bounded-no-replay-after-canonical-event",
        target_qualified = false,
        qualification = "modern-carrier-candidate;target-curl-tls-proxy-ca-pending",
    }, "network capabilities")

    return readonly(service, "network service")
end

return M
