--[[
File: fake_lxp.lua
Date: 2026-08-29
Author: WaterRun
Description: Drives deterministic SAX callback scripts without native loading.
]]

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

        function parser.pos(self)
            return self.line, self.column, self.offset
        end

        function parser.close(self)
            self.closed = true
            return true
        end

        return parser
    end

    return module
end
