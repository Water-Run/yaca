--[[
File: sha256_reference.lua
Date: 2026-08-29
Author: WaterRun
Description: Supplies an independent pure-Lua SHA-256 test oracle.
]]

local CONSTANTS = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local MASK = 0xFFFFFFFF

local function u32(value)
    return value & MASK
end

local function rotate_right(value, count)
    return ((value >> count) | (value << (32 - count))) & MASK
end

local function length_suffix(byte_length)
    local bit_length = byte_length * 8
    local result = {}
    for index = 7, 0, -1 do
        result[#result + 1] = string.char((bit_length >> (index * 8)) & 0xFF)
    end
    return table.concat(result)
end

local function digest(value)
    assert(type(value) == "string", "SHA-256 oracle input must be bytes")
    local padded = value .. "\128"
    local zero_count = (56 - (#padded % 64)) % 64
    padded = padded .. string.rep("\0", zero_count) .. length_suffix(#value)
    local state = {
        0x6a09e667,
        0xbb67ae85,
        0x3c6ef372,
        0xa54ff53a,
        0x510e527f,
        0x9b05688c,
        0x1f83d9ab,
        0x5be0cd19,
    }
    for block_start = 1, #padded, 64 do
        local words = {}
        for index = 0, 15 do
            local offset = block_start + index * 4
            local first, second, third, fourth = padded:byte(offset, offset + 3)
            words[index + 1] = (first << 24) | (second << 16) | (third << 8) | fourth
        end
        for index = 17, 64 do
            local lower = rotate_right(words[index - 15], 7)
                ~ rotate_right(words[index - 15], 18)
                ~ (words[index - 15] >> 3)
            local upper = rotate_right(words[index - 2], 17)
                ~ rotate_right(words[index - 2], 19)
                ~ (words[index - 2] >> 10)
            words[index] = u32(words[index - 16] + lower + words[index - 7] + upper)
        end
        local a, b, c, d = state[1], state[2], state[3], state[4]
        local e, f, g, h = state[5], state[6], state[7], state[8]
        for index = 1, 64 do
            local sum_e = rotate_right(e, 6) ~ rotate_right(e, 11) ~ rotate_right(e, 25)
            local choice = (e & f) ~ ((~e) & g)
            local first = u32(h + sum_e + choice + CONSTANTS[index] + words[index])
            local sum_a = rotate_right(a, 2) ~ rotate_right(a, 13) ~ rotate_right(a, 22)
            local majority = (a & b) ~ (a & c) ~ (b & c)
            local second = u32(sum_a + majority)
            h, g, f, e, d, c, b, a = g, f, e, u32(d + first), c, b, a, u32(first + second)
        end
        state[1] = u32(state[1] + a)
        state[2] = u32(state[2] + b)
        state[3] = u32(state[3] + c)
        state[4] = u32(state[4] + d)
        state[5] = u32(state[5] + e)
        state[6] = u32(state[6] + f)
        state[7] = u32(state[7] + g)
        state[8] = u32(state[8] + h)
    end
    local output = {}
    for _, word in ipairs(state) do
        output[#output + 1] = string.char(
            (word >> 24) & 0xFF,
            (word >> 16) & 0xFF,
            (word >> 8) & 0xFF,
            word & 0xFF
        )
    end
    return table.concat(output)
end

local function hex(value)
    return (digest(value):gsub(".", function(byte)
        return string.format("%02x", byte:byte())
    end))
end

return {
    digest = digest,
    hex = hex,
}
