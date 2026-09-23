--[[
Author: WaterRun
Date: 2026-09-23
File: direct_filesystem_harness.lua
Description: Supplies a no-follow identity-aware direct filesystem test port.
]]

local M = {}

--Supplies failure behavior required by this suite.
--@param code string|integer Expected error or exit code.
--@param message string|table Message or diagnostic passed through this test port.
--@return table observed Structured fixture record with code, message.
local function failure(code, message)
    return { code = code, message = message or code }
end

--Supplies parent of behavior required by this suite.
--@param path string File or Context path exercised by the case.
--@return number|nil observed parent of value observed by the scenario assertion.
local function parent_of(path)
    if path == "/" then return nil end
    local parent = path:match("^(.*)/[^/]+$")
    return parent == "" and "/" or parent
end

--Supplies basename behavior required by this suite.
--@param path string File or Context path exercised by the case.
--@return any observed basename value observed by the scenario assertion.
local function basename(path)
    return path:match("([^/]+)$")
end

--Supplies copy identity behavior required by this suite.
--@param identity table File or process identity under inspection.
--@return table observed Structured fixture record selected by the exercised branch.
local function copy_identity(identity)
    return {
        kind = identity.kind,
        volume = identity.volume,
        object = identity.object,
        size = identity.size,
        modified = identity.modified,
    }
end

--Supplies the same identity observation used by this suite.
--@param node table Syntax or Context node under inspection.
--@param expected any Expected value used by the assertion.
--@return any matches Whether same identity satisfies the tested condition.
local function same_identity(node, expected)
    return type(expected) == "table"
        and expected.kind == node.kind
        and expected.volume == node.volume
        and expected.object == node.object
        and expected.size == node.size
        and expected.modified == node.modified
end

--Checks same object against this suite.
--@param node table Syntax or Context node under inspection.
--@param expected any Expected value used by the assertion.
--@return any matches Whether same object satisfies the tested condition.
local function same_object(node, expected)
    return type(expected) == "table"
        and expected.kind == node.kind
        and expected.volume == node.volume
        and expected.object == node.object
end

--Constructs the new service used by this suite.
--@param initial any The initial supplied to the fake service for this scenario.
--@return any observed new value observed by the scenario assertion.
--@return any secondary2 Configured control actions returned by the fixture.
function M.new(initial)
    local nodes, serial, generation = {}, 0, 0
    local controls = { operations = {}, faults = {}, last_ignore_policy = false }

    --Supplies next serial behavior required by this suite.
    --@param none No arguments; this closure uses its captured fixture state.
    --@return any observed next serial value observed by the scenario assertion.
    local function next_serial()
        serial = serial + 1
        return tostring(serial)
    end

    --Constructs make node for this test scenario.
    --@param kind string Kind of event or resource under test.
    --@param bytes string Byte chunk supplied to the fake I/O port.
    --@param settings table|nil Fixture settings and scenario overrides.
    --@return any created Constructed make node fixture value.
    local function make_node(kind, bytes, settings)
        settings = settings or {}
        local node = {
            kind = kind,
            bytes = bytes or "",
            volume = settings.volume or "volume-1",
            object = settings.object or next_serial(),
            modified = next_serial(),
            behavior_digest = settings.behavior_digest or "behavior-default",
            preservation = settings.preservation or "proven",
            link_count = settings.link_count or 1,
            link_target = settings.link_target or false,
        }
        node.size = kind == "file" and #node.bytes or 0
        return node
    end

    --Supplies touch behavior required by this suite.
    --@param node table Syntax or Context node under inspection.
    --@return nil No value; the fake port or test assertion observes this callback's effects.
    local function touch(node)
        node.modified = next_serial()
        node.size = node.kind == "file" and #node.bytes or 0
        generation = generation + 1
    end

    --Supplies ensure directory behavior required by this suite.
    --@param path string File or Context path exercised by the case.
    --@return any observed ensure directory value observed by the scenario assertion.
    local function ensure_directory(path)
        if nodes[path] then return nodes[path] end
        local parent = parent_of(path)
        if parent then ensure_directory(parent) end
        nodes[path] = make_node("directory")
        return nodes[path]
    end

    ensure_directory("/")
    for path, value in pairs(initial or {}) do
        ensure_directory(assert(parent_of(path)))
        if type(value) == "string" then
            nodes[path] = make_node("file", value)
        else
            nodes[path] = make_node(value.kind, value.bytes, value)
        end
    end

    --Supplies the identity observation used by this suite.
    --@param node table Syntax or Context node under inspection.
    --@return table observed Structured fixture record selected by the exercised branch.
    local function identity(node)
        return {
            kind = node.kind,
            volume = node.volume,
            object = node.object,
            size = node.size,
            modified = node.modified,
        }
    end

    --Supplies metadata behavior required by this suite.
    --@param node table Syntax or Context node under inspection.
    --@return table observed Structured fixture record with link_count, behavior_digest, preservation, link_target.
    local function metadata(node)
        return {
            link_count = node.link_count,
            behavior_digest = node.behavior_digest,
            preservation = node.preservation,
            link_target = node.link_target,
        }
    end

    --Supplies ancestors behavior required by this suite.
    --@param path string File or Context path exercised by the case.
    --@return any observed ancestors value observed by the scenario assertion.
    local function ancestors(path)
        local result, chain = {}, {}
        local current = parent_of(path)
        while current do
            chain[#chain + 1] = current
            current = parent_of(current)
        end
        for index = #chain, 1, -1 do
            local item = chain[index]
            result[#result + 1] = { path = item, identity = identity(assert(nodes[item])) }
        end
        return result
    end

    --Supplies snapshot behavior required by this suite.
    --@param path string File or Context path exercised by the case.
    --@return table observed Structured fixture record selected by the exercised branch.
    local function snapshot(path)
        local node = nodes[path]
        local parent = assert(nodes[parent_of(path) or "/"])
        return {
            requested_path = path,
            canonical_path = path,
            exists = node ~= nil,
            identity = node and identity(node) or false,
            parent_identity = identity(parent),
            metadata = node and metadata(node) or false,
            ancestors = ancestors(path),
            ancestry_complete = controls.incomplete_ancestry ~= path,
        }
    end

    --Supplies open handle behavior required by this suite.
    --@param node table Syntax or Context node under inspection.
    --@param path string File or Context path exercised by the case.
    --@param mode string Operating mode selected by the scenario.
    --@return table observed Structured fixture record selected by the exercised branch.
    local function open_handle(node, path, mode)
        return { node = node, path = path, mode = mode, offset = 1, closed = false }
    end

    local native = {}

    --Simulates fs open read in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@return boolean accepted Whether fs open read succeeds in the fixture.
    --@return any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_open_read(path)
        local node = nodes[path]
        if not node or node.kind ~= "file" then return false, failure("NotFound") end
        return true, open_handle(node, path, "read")
    end

    --Simulates fs create new in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@return boolean accepted Whether fs create new succeeds in the fixture.
    --@return any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_create_new(path)
        if nodes[path] then return false, failure("DestinationExists") end
        local parent = nodes[parent_of(path)]
        if not parent or parent.kind ~= "directory" then return false, failure("NotFound") end
        local node = make_node("file", "")
        nodes[path] = node
        touch(parent)
        return true, open_handle(node, path, "write")
    end

    --Simulates fs stat identity in this test fixture.
    --@param handle_or_path table|string Fake handle or path accepted by this port.
    --@return boolean accepted Whether fs stat identity succeeds in the fixture.
    --@return any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_stat_identity(handle_or_path)
        local node = type(handle_or_path) == "string" and nodes[handle_or_path]
            or type(handle_or_path) == "table" and handle_or_path.node
        if not node then return false, failure("NotFound") end
        return true, identity(node)
    end

    --Simulates fs read in this test fixture.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@param maximum integer Maximum allowed count or byte length.
    --@return boolean accepted Whether fs read succeeds in the fixture.
    --@return table|any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_read(handle, maximum)
        if type(handle) ~= "table" or handle.closed or handle.mode ~= "read" then
            return false, failure("InvalidHandle")
        end
        local bytes = handle.node.bytes:sub(handle.offset, handle.offset + maximum - 1)
        handle.offset = handle.offset + #bytes
        return true, { bytes = bytes, eof = handle.offset > #handle.node.bytes }
    end

    --Simulates fs write in this test fixture.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@param bytes string Byte chunk supplied to the fake I/O port.
    --@return boolean accepted Whether fs write succeeds in the fixture.
    --@return any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_write(handle, bytes)
        if type(handle) ~= "table" or handle.closed or handle.mode ~= "write" then
            return false, failure("InvalidHandle")
        end
        if controls.faults.write then return false, failure("InjectedWrite") end
        handle.node.bytes = handle.node.bytes .. bytes
        touch(handle.node)
        return true, #bytes
    end

    --Simulates fs flush file in this test fixture.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@return boolean accepted Whether fs flush file succeeds in the fixture.
    --@return boolean|any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_flush_file(handle)
        if controls.faults.flush_file then return false, failure("InjectedFlush") end
        if type(handle) ~= "table" or handle.closed then return false, failure("InvalidHandle") end
        return true, true
    end

    --Simulates fs flush directory in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@return boolean accepted Whether fs flush directory succeeds in the fixture.
    --@return boolean|any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_flush_directory(path)
        controls.operations[#controls.operations + 1] = "flush-directory:" .. path
        if controls.faults.flush_directory then return false, failure("InjectedDirectoryFlush") end
        return true, true
    end

    --Simulates fs replace in this test fixture.
    --@param temporary string Temporary publication path.
    --@param target table|string Target selected for the exercised operation.
    --@return boolean accepted Whether fs replace succeeds in the fixture.
    --@return boolean|any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_replace(temporary, target)
        if not nodes[temporary] or not nodes[target] then return false, failure("NotFound") end
        nodes[target], nodes[temporary] = nodes[temporary], nil
        return true, true
    end

    --Simulates fs rename no replace in this test fixture.
    --@param source string|table Source content or object under test.
    --@param target table|string Target selected for the exercised operation.
    --@return boolean accepted Whether fs rename no replace succeeds in the fixture.
    --@return boolean|any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_rename_no_replace(source, target)
        if not nodes[source] then return false, failure("NotFound") end
        if nodes[target] then return false, failure("DestinationExists") end
        nodes[target], nodes[source] = nodes[source], nil
        return true, true
    end

    --Simulates fs delete verified in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@param expected any Expected value used by the assertion.
    --@return boolean accepted Whether fs delete verified succeeds in the fixture.
    --@return boolean|any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_delete_verified(path, expected)
        local node = nodes[path]
        if not node then return false, failure("NotFound") end
        if not same_identity(node, expected) then return false, failure("TargetChanged") end
        nodes[path] = nil
        return true, true
    end

    --Simulates fs close in this test fixture.
    --@param handle table|integer Fake resource handle whose state is inspected.
    --@return boolean accepted Whether fs close succeeds in the fixture.
    --@return boolean|any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_close(handle)
        if type(handle) ~= "table" or handle.closed then return false, failure("InvalidHandle") end
        handle.closed = true
        return true, true
    end

    --Simulates fs inspect direct in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@return boolean accepted Whether fs inspect direct succeeds in the fixture.
    --@return any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_inspect_direct(path)
        controls.operations[#controls.operations + 1] = "inspect:" .. path
        if controls.faults.inspect == path then return false, failure("InjectedInspect") end
        if not nodes[parent_of(path) or "/"] and not nodes[path] then
            return false, failure("NotFound")
        end
        return true, snapshot(path)
    end

    --Simulates fs walk direct in this test fixture.
    --@param root any The root supplied to the fake service for this scenario.
    --@param depth integer Current nesting depth of the synthetic value.
    --@param maximum integer Maximum allowed count or byte length.
    --@param ignore_policy any The ignore policy supplied to the fake service for this scenario.
    --@return boolean accepted Whether fs walk direct succeeds in the fixture.
    --@return table|any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_walk_direct(root, depth, maximum, ignore_policy)
        controls.operations[#controls.operations + 1] = "walk:" .. root
        controls.last_ignore_policy = ignore_policy
        local root_node = nodes[root]
        if not root_node or root_node.kind ~= "directory" then return false, failure("NotFound") end
        local candidates = {}
        local prefix = root == "/" and "/" or root .. "/"
        for path, node in pairs(nodes) do
            if path:sub(1, #prefix) == prefix and path ~= root then
                local relative = path:sub(#prefix + 1)
                local levels = 1
                for _ in relative:gmatch("/") do levels = levels + 1 end
                if levels <= depth + 1 then
                    candidates[#candidates + 1] = {
                        relative_path = relative,
                        snapshot = snapshot(path),
                        node = node,
                    }
                end
            end
        end
        --Supplies an assertion callback for this test scenario.
        --@param left any First value in the comparison.
        --@param right any Second value in the comparison.
        --@return any value Callback value consumed by the enclosing scenario assertion.
        table.sort(candidates, function(left, right) return left.relative_path < right.relative_path end)
        local complete = #candidates <= maximum
        while #candidates > maximum do candidates[#candidates] = nil end
        for _, entry in ipairs(candidates) do entry.node = nil end
        local rows = {}
        for path, node in pairs(nodes) do
            if path == root or path:sub(1, #prefix) == prefix then
                rows[#rows + 1] = path .. "=" .. node.object .. ":" .. node.modified
            end
        end
        table.sort(rows)
        local partial_reason = false
        if not complete then partial_reason = "entry-limit" end
        return true, {
            generation = table.concat(rows, "|"),
            entries = candidates,
            complete = complete,
            partial_reason = partial_reason,
        }
    end

    --Simulates fs open read verified in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@param expected any Expected value used by the assertion.
    --@return boolean accepted Whether fs open read verified succeeds in the fixture.
    --@return any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_open_read_verified(path, expected)
        controls.operations[#controls.operations + 1] = "open-verified:" .. path
        local node = nodes[path]
        if not node or node.kind ~= "file" then return false, failure("NotFound") end
        if not same_identity(node, expected) then return false, failure("TargetChanged") end
        return true, open_handle(node, path, "read")
    end

    --Simulates fs create new verified in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@param expected_parent table|string Expected parent identity or path.
    --@return boolean accepted Whether fs create new verified succeeds in the fixture.
    --@return any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_create_new_verified(path, expected_parent)
        controls.operations[#controls.operations + 1] = "create-verified:" .. path
        if controls.faults.create then return false, failure("InjectedCreate") end
        if nodes[path] then return false, failure("DestinationExists") end
        local parent = nodes[parent_of(path)]
        if not parent or not same_object(parent, expected_parent) then
            return false, failure("TargetChanged")
        end
        local node = make_node("file", "")
        nodes[path] = node
        touch(parent)
        return true, open_handle(node, path, "write")
    end

    --Simulates fs replace verified in this test fixture.
    --@param temporary string Temporary publication path.
    --@param target table|string Target selected for the exercised operation.
    --@param expected_temporary any The expected temporary supplied to the fake service for this scenario.
    --@param expected_target any The expected target supplied to the fake service for this scenario.
    --@param expected_parent table|string Expected parent identity or path.
    --@param expected_behavior_digest any The expected behavior digest supplied to the fake service for this scenario.
    --@return boolean accepted Whether fs replace verified succeeds in the fixture.
    --@return any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_replace_verified(
        temporary,
        target,
        expected_temporary,
        expected_target,
        expected_parent,
        expected_behavior_digest
    )
        controls.operations[#controls.operations + 1] = "replace-verified:" .. target
        if controls.faults.replace then return false, failure(controls.faults.replace) end
        local temporary_node, target_node = nodes[temporary], nodes[target]
        local parent = nodes[parent_of(target)]
        if not temporary_node or not target_node
            or not same_identity(temporary_node, expected_temporary)
            or not same_identity(target_node, expected_target)
            or not same_object(parent, expected_parent)
            or target_node.behavior_digest ~= expected_behavior_digest
        then
            return false, failure("TargetChanged")
        end
        temporary_node.behavior_digest = target_node.behavior_digest
        temporary_node.preservation = target_node.preservation
        nodes[target], nodes[temporary] = temporary_node, nil
        if controls.relocate_object_ids then temporary_node.object = next_serial() end
        touch(parent)
        return true, identity(temporary_node)
    end

    --Simulates fs rename no replace verified in this test fixture.
    --@param source string|table Source content or object under test.
    --@param target table|string Target selected for the exercised operation.
    --@param expected_source string Expected source content for the assertion.
    --@param expected_source_parent any The expected source parent supplied to the fake service for this scenario.
    --@param expected_target_parent any The expected target parent supplied to the fake service for this scenario.
    --@return boolean accepted Whether fs rename no replace verified succeeds in the fixture.
    --@return any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_rename_no_replace_verified(source, target, expected_source, expected_source_parent, expected_target_parent)
        controls.operations[#controls.operations + 1] = "rename-verified:" .. source .. ":" .. target
        if controls.faults.rename then return false, failure(controls.faults.rename) end
        local node = nodes[source]
        local source_parent, target_parent = nodes[parent_of(source)], nodes[parent_of(target)]
        if not node or nodes[target]
            or not same_identity(node, expected_source)
            or not same_object(source_parent, expected_source_parent)
            or not same_object(target_parent, expected_target_parent)
        then
            return false, failure("TargetChanged")
        end
        nodes[target], nodes[source] = node, nil
        if controls.relocate_object_ids then node.object = next_serial() end
        touch(source_parent)
        if target_parent ~= source_parent then touch(target_parent) end
        return true, identity(node)
    end

    --Simulates fs delete direct verified in this test fixture.
    --@param path string File or Context path exercised by the case.
    --@param expected any Expected value used by the assertion.
    --@param expected_parent table|string Expected parent identity or path.
    --@return boolean accepted Whether fs delete direct verified succeeds in the fixture.
    --@return boolean|any secondary2 Additional status or structured error from the fixture operation.
    function native.fs_delete_direct_verified(path, expected, expected_parent)
        controls.operations[#controls.operations + 1] = "delete-verified:" .. path
        if controls.faults.delete then return false, failure(controls.faults.delete) end
        local node, parent = nodes[path], nodes[parent_of(path)]
        if not node or not same_identity(node, expected) or not same_object(parent, expected_parent) then
            return false, failure("TargetChanged")
        end
        if node.kind == "directory" then
            local prefix = path .. "/"
            for candidate in pairs(nodes) do
                if candidate:sub(1, #prefix) == prefix then return false, failure("DirectoryNotEmpty") end
            end
        end
        nodes[path] = nil
        touch(parent)
        return true, true
    end

    --Supplies bytes behavior required by this suite.
    --@param path string File or Context path exercised by the case.
    --@return any observed bytes value observed by the scenario assertion.
    function controls.bytes(path)
        return nodes[path] and nodes[path].bytes or nil
    end

    --Supplies the identity observation used by this suite.
    --@param path string File or Context path exercised by the case.
    --@return any observed identity value observed by the scenario assertion.
    function controls.identity(path)
        return nodes[path] and copy_identity(identity(nodes[path])) or nil
    end

    --Supplies exists behavior required by this suite.
    --@param path string File or Context path exercised by the case.
    --@return any observed exists value observed by the scenario assertion.
    function controls.exists(path)
        return nodes[path] ~= nil
    end

    --Records the external replace effect observed by this suite.
    --@param path string File or Context path exercised by the case.
    --@param bytes string Byte chunk supplied to the fake I/O port.
    --@param settings table|nil Fixture settings and scenario overrides.
    --@return nil No value; the fake port or test assertion observes this callback's effects.
    function controls.external_replace(path, bytes, settings)
        nodes[path] = make_node("file", bytes, settings)
        local parent = nodes[parent_of(path)]
        if parent then touch(parent) end
    end

    --Records the external write effect observed by this suite.
    --@param path string File or Context path exercised by the case.
    --@param bytes string Byte chunk supplied to the fake I/O port.
    --@return nil No value; the fake port or test assertion observes this callback's effects.
    function controls.external_write(path, bytes)
        local node = assert(nodes[path])
        node.bytes = bytes
        touch(node)
    end

    --Supplies add behavior required by this suite.
    --@param path string File or Context path exercised by the case.
    --@param kind string Kind of event or resource under test.
    --@param bytes string Byte chunk supplied to the fake I/O port.
    --@param settings table|nil Fixture settings and scenario overrides.
    --@return nil No value; the fake port or test assertion observes this callback's effects.
    function controls.add(path, kind, bytes, settings)
        ensure_directory(assert(parent_of(path)))
        settings = settings or {}
        settings.kind = nil
        nodes[path] = make_node(kind, bytes, settings)
        touch(nodes[parent_of(path)])
    end

    --Supplies snapshot behavior required by this suite.
    --@param path string File or Context path exercised by the case.
    --@return any observed snapshot value observed by the scenario assertion.
    function controls.snapshot(path)
        return snapshot(path)
    end

    return native, controls
end

return M
