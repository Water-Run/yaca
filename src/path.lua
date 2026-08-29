--[[
File: path.lua
Date: 2026-08-29
Author: WaterRun
Description: Canonicalizes logical paths and derives stable Context hashes.
]]

local text = require("text")

local M = {}

local function failure(code, message, reason)
    local result = { code = code, message = message }
    if reason ~= nil then result.reason = reason end
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
        __metatable = "locked",
    })
end

local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

local function validate_options(options)
    if type(options) ~= "table" then
        return nil, failure("InvalidPathOptions", "path codec limits are required")
    end
    local names = {
        "maximum_path_bytes",
        "maximum_segments",
        "maximum_segment_bytes",
        "maximum_hash_chunk_bytes",
    }
    local allowed = {}
    local limits = {}
    for _, name in ipairs(names) do
        allowed[name] = true
        if not valid_integer(options[name], 1) then
            return nil, failure("InvalidPathOptions", name .. " must be a positive integer")
        end
        limits[name] = options[name]
    end
    for key in pairs(options) do
        if type(key) ~= "string" or not allowed[key] then
            return nil, failure("InvalidPathOptions", "path options contain an unknown field")
        end
    end
    if limits.maximum_segment_bytes > limits.maximum_path_bytes
        or limits.maximum_hash_chunk_bytes > limits.maximum_path_bytes
    then
        return nil, failure("InvalidPathOptions", "field limits must not exceed path bytes")
    end
    return limits
end

local function validate_native(native)
    if type(native) ~= "table" then
        return nil, failure("InvalidHashPort", "native SHA-256 port is required")
    end
    local names = { "sha256_start", "sha256_update", "sha256_finish", "sha256_close" }
    local port = {}
    for _, name in ipairs(names) do
        if type(native[name]) ~= "function" then
            return nil, failure("InvalidHashPort", "native SHA-256 port is incomplete")
        end
        port[name] = native[name]
    end
    return port
end

local function validate_bytes(value, limits, code)
    if type(value) ~= "string" or value == "" then
        return nil, failure(code, "path must be a non-empty byte string", "type")
    end
    if #value > limits.maximum_path_bytes then
        return nil, failure("PathLimit", "path exceeds maximum_path_bytes", "path-bytes")
    end
    local valid, metadata = text.validate_utf8(value)
    if not valid then return nil, failure(code, "path is not strict UTF-8", "utf8") end
    if metadata.contains_nul then
        return nil, failure(code, "path contains NUL", "nul")
    end
    return true
end

local function split_segments(value, windows_separators)
    local result = {}
    local start_index = 1
    for index = 1, #value + 1 do
        local byte = value:byte(index)
        local separator = byte == nil
            or byte == 0x2F
            or (windows_separators and byte == 0x5C)
        if separator then
            result[#result + 1] = value:sub(start_index, index - 1)
            start_index = index + 1
        end
    end
    return result
end

local function admit_segment(segments, segment, limits)
    if #segment > limits.maximum_segment_bytes then
        return nil, failure("PathLimit", "path segment exceeds maximum_segment_bytes", "segment")
    end
    if #segments >= limits.maximum_segments then
        return nil, failure("PathLimit", "path exceeds maximum_segments", "segments")
    end
    segments[#segments + 1] = segment
    return true
end

local function fold_navigation(segments, raw_segments, first, floor, limits)
    for index = first, #raw_segments do
        local segment = raw_segments[index]
        if segment == "" or segment == "." then
            -- Redundant separators and current-directory markers disappear.
        elseif segment == ".." then
            if #segments <= floor then
                return nil, failure(
                    "PathEscapesWorkspace",
                    "path navigation escapes its absolute root",
                    "dotdot"
                )
            end
            segments[#segments] = nil
        else
            local admitted, segment_error = admit_segment(segments, segment, limits)
            if not admitted then return nil, segment_error end
        end
    end
    return true
end

local function drive_path(value)
    if #value < 3 then return nil end
    local drive = value:sub(1, 1)
    local separator = value:byte(3)
    if drive:match("^[A-Za-z]$")
        and value:sub(2, 2) == ":"
        and (separator == 0x2F or separator == 0x5C)
    then
        return drive:upper(), value:sub(4)
    end
    return nil
end

local function platform_segments(value, limits)
    local segments = {}
    local root_kind
    local remainder
    local upper_prefix = value:sub(1, 8):upper()
    if upper_prefix == "\\\\?\\UNC\\" then
        root_kind = "windows-unc"
        remainder = value:sub(9)
    elseif value:sub(1, 4) == "\\\\?\\" then
        local drive, tail = drive_path(value:sub(5))
        if not drive then
            return nil, failure("UnsupportedPath", "extended Windows path is unsupported")
        end
        root_kind = "windows-drive"
        assert(admit_segment(segments, drive, limits))
        remainder = tail
    elseif value:sub(1, 4) == "\\\\.\\" then
        return nil, failure("UnsupportedPath", "Windows device paths are unsupported")
    elseif value:sub(1, 2) == "\\\\" then
        root_kind = "windows-unc"
        remainder = value:sub(3)
    else
        local drive, tail = drive_path(value)
        if drive then
            root_kind = "windows-drive"
            assert(admit_segment(segments, drive, limits))
            remainder = tail
        elseif value:sub(1, 1) == "/" then
            root_kind = "posix"
            remainder = value:sub(2)
        else
            return nil, failure("UnsupportedPath", "path is not absolute")
        end
    end

    local raw = split_segments(remainder, root_kind ~= "posix")
    if root_kind == "windows-unc" then
        local names = {}
        for _, segment in ipairs(raw) do
            if segment ~= "" then names[#names + 1] = segment end
        end
        if #names < 2
            or names[1] == "."
            or names[1] == ".."
            or names[2] == "."
            or names[2] == ".."
        then
            return nil, failure("UnsupportedPath", "UNC path requires a server and share")
        end
        local admitted, segment_error = admit_segment(segments, "UNC", limits)
        if not admitted then return nil, segment_error end
        admitted, segment_error = admit_segment(segments, names[1], limits)
        if not admitted then return nil, segment_error end
        admitted, segment_error = admit_segment(segments, names[2], limits)
        if not admitted then return nil, segment_error end
        local folded, fold_error = fold_navigation(segments, names, 3, 3, limits)
        if not folded then return nil, fold_error end
    else
        local floor = root_kind == "windows-drive" and 1 or 0
        local folded, fold_error = fold_navigation(segments, raw, 1, floor, limits)
        if not folded then return nil, fold_error end
    end
    return segments, root_kind
end

local function logical_string(segments)
    if #segments == 0 then return "/" end
    return "/" .. table.concat(segments, "/")
end

local function parse_logical(value, limits)
    local valid, validation_error = validate_bytes(value, limits, "InvalidLogicalPath")
    if not valid then return nil, validation_error end
    if value:sub(1, 1) ~= "/"
        or (value ~= "/" and value:sub(-1) == "/")
        or value:find("//", 1, true)
    then
        return nil, failure("InvalidLogicalPath", "logical path is not canonical")
    end
    if value == "/" then return {} end
    local segments = split_segments(value:sub(2), false)
    for _, segment in ipairs(segments) do
        if segment == "" or segment == "." or segment == ".." then
            return nil, failure("InvalidLogicalPath", "logical path has a forbidden segment")
        end
        if #segment > limits.maximum_segment_bytes then
            return nil, failure("PathLimit", "logical segment exceeds its byte limit", "segment")
        end
    end
    if #segments > limits.maximum_segments then
        return nil, failure("PathLimit", "logical path has too many segments", "segments")
    end
    if segments[1] == "UNC" and #segments < 3 then
        return nil, failure("InvalidLogicalPath", "logical UNC path is incomplete")
    end
    return segments
end

local function ascii_fold(value)
    return (value:gsub("[A-Z]", function(character)
        return string.char(character:byte() + 0x20)
    end))
end

local function digest_with_port(port, value, chunk_bytes)
    local started, handle = pcall(port.sha256_start)
    if not started or handle == nil or handle == false then
        return nil, failure("NativeHash", "native SHA-256 start failed")
    end
    local function close()
        return pcall(port.sha256_close, handle)
    end
    for index = 1, #value, chunk_bytes do
        local called, updated = pcall(
            port.sha256_update,
            handle,
            value:sub(index, index + chunk_bytes - 1)
        )
        if not called or updated ~= true then
            close()
            return nil, failure("NativeHash", "native SHA-256 update failed")
        end
    end
    local finished, digest = pcall(port.sha256_finish, handle)
    local closed, close_result = close()
    if not finished or type(digest) ~= "string" or #digest ~= 32 then
        return nil, failure("NativeHash", "native SHA-256 finish returned a malformed digest")
    end
    if not closed or close_result ~= true then
        return nil, failure("NativeHash", "native SHA-256 close failed")
    end
    return digest
end

local function lower_hex(value)
    return (value:gsub(".", function(byte)
        return string.format("%02x", byte:byte())
    end))
end

local function context_hex(value)
    local output = {}
    for index = 1, 8 do output[index] = string.format("%02X", value:byte(index)) end
    return table.concat(output)
end

local function byte_compare(left, right)
    local shared = math.min(#left, #right)
    for index = 1, shared do
        local left_byte, right_byte = left:byte(index), right:byte(index)
        if left_byte < right_byte then return -1 end
        if left_byte > right_byte then return 1 end
    end
    if #left < #right then return -1 end
    if #left > #right then return 1 end
    return 0
end

local function context_name_error(message, reason)
    return failure("InvalidContextName", message, reason)
end

---Creates a pure LogicalPath codec backed by the bundled streaming hash port.
-- @param native table Native module exposing the four SHA-256 handle methods.
-- @param options table Required path, segment, and hash chunk limits.
-- @return table|nil codec Immutable path service.
-- @return table|nil err Structured port or limit failure.
function M.new(native, options)
    local port, port_error = validate_native(native)
    if not port then return nil, port_error end
    local limits, limits_error = validate_options(options)
    if not limits then return nil, limits_error end
    local service = {}

    ---Converts one observed absolute platform path to canonical LogicalPath.
    -- This function performs no filesystem lookup or symlink inference.
    -- @param platform_path string Strict UTF-8 absolute path bytes.
    -- @return string|nil logical Canonical slash-separated LogicalPath.
    -- @return table|nil metadata_or_err Root kind metadata or typed failure.
    function service.to_logical(platform_path)
        local valid, validation_error = validate_bytes(
            platform_path,
            limits,
            "UnsupportedPath"
        )
        if not valid then return nil, validation_error end
        local segments, root_kind_or_error = platform_segments(platform_path, limits)
        if not segments then return nil, root_kind_or_error end
        local logical = logical_string(segments)
        if #logical > limits.maximum_path_bytes then
            return nil, failure("PathLimit", "logical path exceeds maximum_path_bytes")
        end
        return logical, readonly({ root_kind = root_kind_or_error }, "path metadata")
    end

    ---Validates an already-canonical LogicalPath without rewriting it.
    -- @param logical string Candidate LogicalPath.
    -- @return string|nil admitted Exact input when canonical.
    -- @return table|nil err Structured canonicality or limit failure.
    function service.validate_logical(logical)
        local segments, parse_error = parse_logical(logical, limits)
        if not segments then return nil, parse_error end
        return logical
    end

    ---Decodes LogicalPath into an explicit platform path syntax.
    -- @param logical string Canonical LogicalPath.
    -- @param platform_kind string Either windows or posix.
    -- @return string|nil platform_path Deterministic platform syntax.
    -- @return table|nil err Structured mapping failure.
    function service.from_logical(logical, platform_kind)
        local segments, parse_error = parse_logical(logical, limits)
        if not segments then return nil, parse_error end
        if platform_kind == "posix" then return logical end
        if platform_kind ~= "windows" then
            return nil, failure("UnsupportedPath", "unknown platform path syntax")
        end
        if #segments == 0 then
            return nil, failure("UnsupportedPath", "Windows mapping requires a drive or UNC root")
        end
        for _, segment in ipairs(segments) do
            if segment:find("\\", 1, true) or segment:find(":", 1, true) then
                return nil, failure("UnsupportedPath", "logical segment cannot map to Windows")
            end
        end
        if segments[1] == "UNC" then
            return "\\\\" .. table.concat(segments, "\\", 2)
        end
        if segments[1]:match("^[A-Z]$") then
            local suffix = #segments > 1 and "\\" .. table.concat(segments, "\\", 2) or "\\"
            return segments[1] .. ":" .. suffix
        end
        return nil, failure("UnsupportedPath", "logical path has no Windows root marker")
    end

    ---Returns exact display bytes after only safety and size admission.
    -- @param platform_path string Native-friendly display path.
    -- @return string|nil display Exact unnormalized display bytes.
    -- @return table|nil err Structured safety or limit failure.
    function service.normalize_display(platform_path)
        local valid, validation_error = validate_bytes(
            platform_path,
            limits,
            "UnsupportedPath"
        )
        if not valid then return nil, validation_error end
        return platform_path
    end

    ---Builds the platform comparison key separately from hash input bytes.
    -- @param logical string Canonical LogicalPath.
    -- @param platform_kind string Either windows or posix.
    -- @return string|nil key Stable comparison key.
    -- @return table|nil err Structured selector failure.
    function service.comparison_key(logical, platform_kind)
        local admitted, validation_error = service.validate_logical(logical)
        if not admitted then return nil, validation_error end
        if platform_kind == "windows" then return ascii_fold(logical) end
        if platform_kind == "posix" then return logical end
        return nil, failure("UnsupportedPath", "unknown comparison platform")
    end

    ---Checks a canonical path boundary by whole segments, never raw prefix alone.
    -- @param logical string Candidate LogicalPath.
    -- @param root_logical string Candidate root LogicalPath.
    -- @param platform_kind string Either windows or posix comparison semantics.
    -- @return boolean|nil within Whether logical is root or a descendant.
    -- @return table|nil err Structured canonicality or platform failure.
    function service.is_within_root(logical, root_logical, platform_kind)
        local key, key_error = service.comparison_key(logical, platform_kind)
        if not key then return nil, key_error end
        local root, root_error = service.comparison_key(root_logical, platform_kind)
        if not root then return nil, root_error end
        return root == "/" or key == root or key:sub(1, #root + 1) == root .. "/"
    end

    ---Compares two canonical LogicalPaths by exact UTF-8 bytes.
    -- This does not consult the locale or filesystem case rules; it is the
    -- stable resolver and catalog tie-break order.
    -- @param left string First canonical LogicalPath.
    -- @param right string Second canonical LogicalPath.
    -- @return integer|nil order -1, 0, or 1.
    -- @return table|nil err Structured canonicality failure.
    function service.compare_logical(left, right)
        local admitted, validation_error = service.validate_logical(left)
        if not admitted then return nil, validation_error end
        admitted, validation_error = service.validate_logical(right)
        if not admitted then return nil, validation_error end
        return byte_compare(left, right)
    end

    ---Returns the canonical parent of a LogicalPath.
    -- @param logical string Canonical LogicalPath.
    -- @return string|nil parent Root is its own parent.
    -- @return table|nil err Structured canonicality failure.
    function service.parent(logical)
        local segments, parse_error = parse_logical(logical, limits)
        if not segments then return nil, parse_error end
        if #segments == 0 then return "/" end
        segments[#segments] = nil
        return logical_string(segments)
    end

    ---Validates an exact Context display name used by name selectors.
    -- Names are opaque UTF-8 bytes, but path separators, dot navigation, and
    -- ASCII controls are never admitted as a basename selector.
    -- @param name string Candidate display/canonical name without .xml.
    -- @return string|nil admitted Exact input when safe.
    -- @return table|nil err Structured name failure.
    function service.validate_context_name(name)
        if type(name) ~= "string" or name == "" then
            return nil, context_name_error("Context name must be non-empty", "empty")
        end
        if #name > limits.maximum_segment_bytes - 4 then
            return nil, context_name_error("Context name exceeds its byte limit", "bytes")
        end
        local valid, metadata = text.validate_utf8(name)
        if not valid then
            return nil, context_name_error("Context name is not strict UTF-8", "utf8")
        end
        if metadata.contains_nul then
            return nil, context_name_error("Context name contains NUL", "nul")
        end
        if name == "." or name == ".." then
            return nil, context_name_error("Context name is path navigation", "navigation")
        end
        if name:find("/", 1, true) or name:find("\\", 1, true) then
            return nil, context_name_error("Context name contains a path separator", "separator")
        end
        for index = 1, #name do
            local byte = name:byte(index)
            if byte < 0x20 or byte == 0x7F then
                return nil, context_name_error("Context name contains an ASCII control", "control")
            end
        end
        return name
    end

    ---Classifies one canonical LogicalPath as an official Context XML file.
    -- Temp, previous-valid, lock, extension-only, and non-XML paths are not
    -- catalog candidates because only an exact non-empty `.xml` suffix wins.
    -- @param logical string Canonical LogicalPath.
    -- @return table|nil details Logical parent, leaf, and display name.
    -- @return table|nil err Structured path or candidate-role failure.
    function service.context_file(logical)
        local segments, parse_error = parse_logical(logical, limits)
        if not segments then return nil, parse_error end
        if #segments == 0 then
            return nil, failure("NotContextFile", "Context candidate cannot be the catalog root")
        end
        local leaf = segments[#segments]
        if #leaf <= 4 or leaf:sub(-4) ~= ".xml" then
            return nil, failure("NotContextFile", "path is not an official Context XML file")
        end
        local display_name = leaf:sub(1, -5)
        local admitted, name_error = service.validate_context_name(display_name)
        if not admitted then return nil, name_error end
        segments[#segments] = nil
        return readonly({
            logical_path = logical,
            parent = logical_string(segments),
            leaf = leaf,
            display_name = display_name,
        }, "Context path details")
    end

    ---Hashes exact canonical LogicalPath UTF-8 bytes with pinned SHA-256.
    -- @param logical string Canonical LogicalPath.
    -- @return table|nil details Full lowercase digest and first-eight-byte hash.
    -- @return table|nil err Structured path or native port failure.
    function service.hash(logical)
        local admitted, validation_error = service.validate_logical(logical)
        if not admitted then return nil, validation_error end
        local digest, digest_error = digest_with_port(
            port,
            logical,
            limits.maximum_hash_chunk_bytes
        )
        if not digest then return nil, digest_error end
        return readonly({
            algorithm = "SHA-256",
            full_hex = lower_hex(digest),
            context_hash = context_hex(digest),
        }, "path hash details")
    end

    ---Returns the public fixed 16-uppercase-hex Context selector hash.
    -- @param logical string Canonical LogicalPath.
    -- @return string|nil hash First eight SHA-256 bytes in network order.
    -- @return table|nil err Structured path or native port failure.
    function service.context_hash(logical)
        local details, hash_error = service.hash(logical)
        if not details then return nil, hash_error end
        return details.context_hash
    end

    ---Classifies exactly 16 hexadecimal bytes as hash; everything else is name.
    -- @param token string User selector token.
    -- @return table|nil selector Immutable kind and canonical token.
    -- @return table|nil err Structured UTF-8, NUL, empty, or limit failure.
    function service.classify_selector(token)
        local valid, validation_error = validate_bytes(token, limits, "InvalidSelector")
        if not valid then return nil, validation_error end
        local is_hash = #token == 16 and token:match("^[0-9A-Fa-f]+$") ~= nil
        return readonly({
            kind = is_hash and "hash" or "name",
            canonical = is_hash and token:upper() or token,
        }, "path selector")
    end

    service.limits = readonly({
        maximum_path_bytes = limits.maximum_path_bytes,
        maximum_segments = limits.maximum_segments,
        maximum_segment_bytes = limits.maximum_segment_bytes,
        maximum_hash_chunk_bytes = limits.maximum_hash_chunk_bytes,
    }, "path limits")

    return readonly(service, "path codec")
end

return M
