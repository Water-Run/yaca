--[[
Author: WaterRun
Date: 2026-09-23
File: fake_lxp.lua
Description: Drives deterministic SAX callback scripts without native loading.
]]

--Supplies an assertion callback for this test scenario.
--@param dispatch function Dispatch callback supplied to the fake runtime.
--@return any value Callback value consumed by the enclosing scenario assertion.
return function(dispatch)
    assert(type(dispatch) == "function", "fake lxp requires a dispatch function")
    local observations = {
        parser_count = 0,
        maximum_chunk_bytes = 0,
        merge_character_data = nil,
    }
    local module = {
        _VERSION = "LuaExpat 1.5.2",
        _EXPAT_VERSION = "expat_2.8.2",
        _EXPAT_FEATURES = { sizeof_XML_Char = 1 },
        observations = observations,
    }

    --Constructs the new service used by this suite.
    --@param callbacks table Callbacks supplied to the fake service.
    --@param separator any The separator supplied to the fake service for this scenario.
    --@param merge_character_data any The merge character data supplied to the fake service for this scenario.
    --@return any observed new value observed by the scenario assertion.
    function module.new(callbacks, separator, merge_character_data)
        assert(type(callbacks) == "table")
        assert(separator == nil)
        observations.parser_count = observations.parser_count + 1
        observations.merge_character_data = merge_character_data
        local parser = {
            chunks = {},
            closed = false,
            line = 1,
            column = 1,
            offset = 1,
        }

        --Transforms parse data used by this suite.
        --@param self table Fixture or port instance receiving this call.
        --@param chunk string Data chunk supplied to the stream.
        --@return boolean|nil observed True acknowledgment from the fake port; nil on alternate branches.
        --@return any|nil secondary2 Additional status or structured error from the fixture operation.
        --@return any|nil secondary3 Additional status or structured error from the fixture operation.
        --@return any|nil secondary4 Additional status or structured error from the fixture operation.
        --@return any|nil secondary5 Additional status or structured error from the fixture operation.
        function parser.parse(self, chunk)
            assert(not self.closed, "parser is closed")
            if chunk ~= nil then
                self.chunks[#self.chunks + 1] = chunk
                if #chunk > observations.maximum_chunk_bytes then
                    observations.maximum_chunk_bytes = #chunk
                end
                return true
            end
            local document = table.concat(self.chunks)
            local called, accepted, parse_error, line, column, offset = pcall(
                dispatch,
                document,
                callbacks,
                self
            )
            if not called then
                return nil, tostring(accepted), self.line, self.column, self.offset
            end
            if accepted == false then
                return nil,
                    parse_error or "not well formed",
                    line or self.line,
                    column or self.column,
                    offset or self.offset
            end
            return true
        end

        --Supplies pos behavior required by this suite.
        --@param self table Fixture or port instance receiving this call.
        --@return any observed pos value observed by the scenario assertion.
        --@return any secondary2 Additional status or structured error from the fixture operation.
        --@return any secondary3 Additional status or structured error from the fixture operation.
        function parser.pos(self)
            return self.line, self.column, self.offset
        end

        --Simulates the close transition of a fake activity port for this suite.
        --@param self table Fixture or port instance receiving this call.
        --@return boolean accepted Whether close succeeds in the fixture.
        function parser.close(self)
            self.closed = true
            return true
        end

        return parser
    end

    return module
end
