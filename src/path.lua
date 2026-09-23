--[[
Author: WaterRun
Date: 2026-09-23
File: path.lua
Description: Canonicalizes logical paths and derives stable Context hashes.
]]

local text = require("text")

local M = {}

-- Construct a structured diagnostic without throwing or formatting its optional fields.
--@param code string Stable diagnostic code used by callers to choose recovery behavior.
--@param message string Human-readable summary supplied by the failing operation.
--@param reason string|nil Optional machine-readable cause or validation rule.
--@return table New diagnostic record; optional non-nil fields are retained without deep copying.
local function failure(code, message, reason)
    local result = { code = code, message = message }
    if reason ~= nil then result.reason = reason end
    return result
end

-- Create a shallow read-only view without copying the backing table.
--@param values table Backing fields retained by reference; the caller owns their stability.
--@param label string|nil Diagnostic label; defaults to "readonly value".
--@return table Empty proxy exposing the backing fields through its locked metatable.
--@ownership Retains values by reference; nested values and the backing table are not frozen.
local function readonly(values, label)
    --@metatable readonly_proxy Forwards reads and iteration; ordinary assignments raise an error.
    --@field __index table Backing values used for missing-key reads.
    --@field __newindex function Rejects ordinary assignments without changing the backing values.
    --@field __pairs function Enumerates the backing table with next.
    --@field __metatable string Hides this metatable behind the fixed "locked" marker.
    return setmetatable({}, {
        __index = values,
        -- Reject a write through the proxy before it can create an ordinary field.
        --@param _ table Proxy receiving the assignment; its contents are not consulted.
        --@param key any Attempted field name included in the diagnostic.
        --@return nil Does not return normally.
        --@error Always raises a read-only assignment error at the caller frame.
        __newindex = function(_, key)
            error((label or "readonly value") .. " cannot be modified: " .. tostring(key), 2)
        end,
        -- Iterate the backing fields instead of the empty proxy table.
        --@param none The proxy argument supplied by pairs is ignored.
        --@return function The standard next iterator.
        --@return table Backing values used as iterator state.
        --@return nil Initial key used to start iteration.
        __pairs = function()
            return next, values, nil
        end,
        __metatable = "locked",
    })
end

-- Check the Lua integer subtype and the caller's inclusive lower bound.
--@param value any Candidate value; floats and non-numeric values are rejected.
--@param minimum integer Inclusive minimum accepted by this check.
--@return boolean True only for an integer at least minimum.
local function valid_integer(value, minimum)
    return math.type(value) == "integer" and value >= minimum
end

-- Validate and copy the complete path-limit contract before any path is admitted.
--@param options table Candidate positive integer limits; unknown fields are rejected.
--@return table|nil limits Independent table containing the four admitted limits.
--@return table|nil err Structured limit or option-shape failure.
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

-- Snapshot the four required streaming SHA-256 callbacks from a native port.
--@param native table Candidate hash port; callback members must be functions.
--@return table|nil port Independent callback table retaining callable references.
--@return table|nil err Structured missing-port or incomplete-port failure.
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

-- Admit a non-empty path byte string with bounded strict UTF-8 and no NUL.
--@param value any Candidate path bytes.
--@param limits table Validated path limits, read without mutation.
--@param code string Diagnostic code for invalid input bytes.
--@return boolean|nil valid True when the input passes byte admission.
--@return table|nil err Structured type, length, UTF-8, or NUL failure.
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

-- Split raw path bytes while preserving empty components for root parsing.
--@param value string Path suffix or logical path without its leading slash.
--@param windows_separators boolean Whether backslashes also separate components.
--@return table segments Ordered string components, including empty components.
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

-- Append one bounded component to the caller's mutable segment sequence.
--@param segments table Mutable sequence to append to after validation.
--@param segment string Component whose byte length is checked.
--@param limits table Validated per-component and component-count limits.
--@return boolean|nil admitted True after the append succeeds.
--@return table|nil err Structured component or count limit failure.
--@effect Mutates segments only on success.
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

-- Fold separators, dots, and parent navigation without crossing an absolute root.
--@param segments table Mutable admitted prefix retained by the caller.
--@param raw_segments table Raw component sequence to process.
--@param first integer First one-based component to process.
--@param floor integer Minimum retained prefix length protected from parent traversal.
--@param limits table Validated component and count limits.
--@return boolean|nil folded True when all components have been admitted.
--@return table|nil err Structured escape or path-limit failure.
--@effect Appends or removes entries in segments; an error may leave a partial result.
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

-- Recognize a drive-absolute Windows prefix and separate its remaining bytes.
--@param value string Candidate Windows path beginning at the drive letter.
--@return string|nil drive Uppercase ASCII drive letter, or nil for no match.
--@return string|nil remainder Bytes following the drive root on a match.
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

-- Parse supported absolute POSIX, Windows drive, and UNC syntax into logical components.
--@param value string Strict UTF-8 platform path previously admitted by validate_bytes.
--@param limits table Validated path and component limits.
--@return table|nil segments Canonical logical components including root markers.
--@return string|table root_kind_or_err Root kind on success or structured failure.
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

-- Join canonical components into the slash-rooted logical representation.
--@param segments table Ordered canonical components; empty represents root.
--@return string logical Canonical slash-rooted path.
local function logical_string(segments)
    if #segments == 0 then return "/" end
    return "/" .. table.concat(segments, "/")
end

-- Validate a logical path exactly as supplied and return its components.
--@param value any Candidate canonical slash-rooted UTF-8 path.
--@param limits table Validated path and component limits.
--@return table|nil segments Canonical components, empty for root.
--@return table|nil err Structured canonicality, UTF-8, or limit failure.
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

-- Fold only ASCII uppercase bytes for Windows comparison semantics.
--@param value string Canonical logical path whose non-ASCII bytes stay unchanged.
--@return string folded ASCII-case-folded path bytes.
local function ascii_fold(value)
    -- Map one matched uppercase ASCII byte to its lowercase equivalent.
    --@param character string One uppercase ASCII byte matched by gsub.
    --@return string lower The corresponding lowercase ASCII byte.
    return (value:gsub("[A-Z]", function(character)
        return string.char(character:byte() + 0x20)
    end))
end

-- Hash exact path bytes in bounded chunks and close the native hash handle.
--@param port table Validated four-callback SHA-256 port.
--@param value string Exact canonical logical path bytes.
--@param chunk_bytes integer Positive maximum chunk length.
--@return string|nil digest Raw 32-byte SHA-256 digest.
--@return table|nil err Structured start, update, finish, or close failure.
--@ownership Owns and closes the hash handle returned by sha256_start.
local function digest_with_port(port, value, chunk_bytes)
    local started, handle = pcall(port.sha256_start)
    if not started or handle == nil or handle == false then
        return nil, failure("NativeHash", "native SHA-256 start failed")
    end
    -- Release the native hash handle while containing native callback exceptions.
    --@param none No arguments; the started handle is captured by this closure.
    --@return boolean called Whether sha256_close returned without throwing.
    --@return any result Native close result when called, or its error object.
    --@effect Attempts to close the hash handle once at each invoked call site.
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

-- Encode every raw digest byte as two lowercase hexadecimal characters.
--@param value string Raw digest bytes.
--@return string hex Lowercase hexadecimal encoding.
local function lower_hex(value)
    -- Format one raw digest byte as a fixed-width lowercase hexadecimal pair.
    --@param byte string One matched byte from the digest.
    --@return string pair Two lowercase hexadecimal characters.
    return (value:gsub(".", function(byte)
        return string.format("%02x", byte:byte())
    end))
end

-- Encode the first eight digest bytes as an uppercase Context selector hash.
--@param value string Raw SHA-256 digest of at least eight bytes.
--@return string hash Sixteen uppercase hexadecimal characters.
local function context_hex(value)
    local output = {}
    for index = 1, 8 do output[index] = string.format("%02X", value:byte(index)) end
    return table.concat(output)
end

-- Compare two strings by unsigned byte order without locale conversion.
--@param left string First UTF-8 path byte sequence.
--@param right string Second UTF-8 path byte sequence.
--@return integer order Minus one, zero, or one for left versus right.
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

-- Wrap a Context basename validation failure in its stable diagnostic code.
--@param message string Human-readable reason for rejection.
--@param reason string Machine-readable basename rejection category.
--@return table err New InvalidContextName diagnostic.
local function context_name_error(message, reason)
    return failure("InvalidContextName", message, reason)
end

---Creates a pure LogicalPath codec backed by the bundled streaming hash port.
--@param native table Native module exposing the four SHA-256 handle methods.
--@param options table Required path, segment, and hash chunk limits.
--@return table|nil codec Immutable path service.
--@return table|nil err Structured port or limit failure.
function M.new(native, options)
    local port, port_error = validate_native(native)
    if not port then return nil, port_error end
    local limits, limits_error = validate_options(options)
    if not limits then return nil, limits_error end
    local service = {}

    ---Converts one observed absolute platform path to canonical LogicalPath.
    -- This function performs no filesystem lookup or symlink inference.
    --@param platform_path string Strict UTF-8 absolute path bytes.
    --@return string|nil logical Canonical slash-separated LogicalPath.
    --@return table|nil metadata_or_err Root kind metadata or typed failure.
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
    --@param logical string Candidate LogicalPath.
    --@return string|nil admitted Exact input when canonical.
    --@return table|nil err Structured canonicality or limit failure.
    function service.validate_logical(logical)
        local segments, parse_error = parse_logical(logical, limits)
        if not segments then return nil, parse_error end
        return logical
    end

    ---Decodes LogicalPath into an explicit platform path syntax.
    --@param logical string Canonical LogicalPath.
    --@param platform_kind string Either windows or posix.
    --@return string|nil platform_path Deterministic platform syntax.
    --@return table|nil err Structured mapping failure.
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
    --@param platform_path string Native-friendly display path.
    --@return string|nil display Exact unnormalized display bytes.
    --@return table|nil err Structured safety or limit failure.
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
    --@param logical string Canonical LogicalPath.
    --@param platform_kind string Either windows or posix.
    --@return string|nil key Stable comparison key.
    --@return table|nil err Structured selector failure.
    function service.comparison_key(logical, platform_kind)
        local admitted, validation_error = service.validate_logical(logical)
        if not admitted then return nil, validation_error end
        if platform_kind == "windows" then return ascii_fold(logical) end
        if platform_kind == "posix" then return logical end
        return nil, failure("UnsupportedPath", "unknown comparison platform")
    end

    ---Checks a canonical path boundary by whole segments, never raw prefix alone.
    --@param logical string Candidate LogicalPath.
    --@param root_logical string Candidate root LogicalPath.
    --@param platform_kind string Either windows or posix comparison semantics.
    --@return boolean|nil within Whether logical is root or a descendant.
    --@return table|nil err Structured canonicality or platform failure.
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
    --@param left string First canonical LogicalPath.
    --@param right string Second canonical LogicalPath.
    --@return integer|nil order -1, 0, or 1.
    --@return table|nil err Structured canonicality failure.
    function service.compare_logical(left, right)
        local admitted, validation_error = service.validate_logical(left)
        if not admitted then return nil, validation_error end
        admitted, validation_error = service.validate_logical(right)
        if not admitted then return nil, validation_error end
        return byte_compare(left, right)
    end

    ---Returns the canonical parent of a LogicalPath.
    --@param logical string Canonical LogicalPath.
    --@return string|nil parent Root is its own parent.
    --@return table|nil err Structured canonicality failure.
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
    --@param name string Candidate display/canonical name without .xml.
    --@return string|nil admitted Exact input when safe.
    --@return table|nil err Structured name failure.
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
    --@param logical string Canonical LogicalPath.
    --@return table|nil details Logical parent, leaf, and display name.
    --@return table|nil err Structured path or candidate-role failure.
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
    --@param logical string Canonical LogicalPath.
    --@return table|nil details Full lowercase digest and first-eight-byte hash.
    --@return table|nil err Structured path or native port failure.
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
    --@param logical string Canonical LogicalPath.
    --@return string|nil hash First eight SHA-256 bytes in network order.
    --@return table|nil err Structured path or native port failure.
    function service.context_hash(logical)
        local details, hash_error = service.hash(logical)
        if not details then return nil, hash_error end
        return details.context_hash
    end

    ---Classifies exactly 16 hexadecimal bytes as hash; everything else is name.
    --@param token string User selector token.
    --@return table|nil selector Immutable kind and canonical token.
    --@return table|nil err Structured UTF-8, NUL, empty, or limit failure.
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
