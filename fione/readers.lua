--[[
Binary data readers for integers and floats
]]--

local compat = require('fione.compat')
local bit = compat.bit

-- Read basic integer from binary string
local function rd_int_basic(src, s, e, d)
	local num = 0

	for i = s, e, d do
		local mul = 256 ^ math.abs(i - s)
		num = num + mul * string.byte(src, i, i)
	end

	return num
end

-- Read basic float (32-bit)
local function rd_flt_basic(f1, f2, f3, f4)
	local sign = (-1) ^ bit.rshift(f4, 7)
	local exp = bit.rshift(f3, 7) + bit.lshift(bit.band(f4, 0x7F), 1)
	local frac = f1 + bit.lshift(f2, 8) + bit.lshift(bit.band(f3, 0x7F), 16)
	local normal = 1

	if exp == 0 then
		if frac == 0 then
			return sign * 0
		else
			normal = 0
			exp = 1
		end
	elseif exp == 0x7F then
		if frac == 0 then
			return sign * (1 / 0)
		else
			return sign * (0 / 0)
		end
	end

	return sign * 2 ^ (exp - 127) * (1 + normal / 2 ^ 23)
end

-- Read basic double (64-bit)
local function rd_dbl_basic(f1, f2, f3, f4, f5, f6, f7, f8)
	local sign = (-1) ^ bit.rshift(f8, 7)
	local exp = bit.lshift(bit.band(f8, 0x7F), 4) + bit.rshift(f7, 4)
	local frac = bit.band(f7, 0x0F) * 2 ^ 48
	local normal = 1

	frac = frac + (f6 * 2 ^ 40) + (f5 * 2 ^ 32) + (f4 * 2 ^ 24) + (f3 * 2 ^ 16) + (f2 * 2 ^ 8) + f1

	if exp == 0 then
		if frac == 0 then
			return sign * 0
		else
			normal = 0
			exp = 1
		end
	elseif exp == 0x7FF then
		if frac == 0 then
			return sign * (1 / 0)
		else
			return sign * (0 / 0)
		end
	end

	return sign * 2 ^ (exp - 1023) * (normal + frac / 2 ^ 52)
end

-- Little endian integer reader
local function rd_int_le(src, s, e) 
	return rd_int_basic(src, s, e - 1, 1) 
end

-- Big endian integer reader
local function rd_int_be(src, s, e) 
	return rd_int_basic(src, e - 1, s, -1) 
end

-- Little endian float reader
local function rd_flt_le(src, s) 
	return rd_flt_basic(string.byte(src, s, s + 3)) 
end

-- Big endian float reader
local function rd_flt_be(src, s)
	local f1, f2, f3, f4 = string.byte(src, s, s + 3)
	return rd_flt_basic(f4, f3, f2, f1)
end

-- Little endian double reader
local function rd_dbl_le(src, s) 
	return rd_dbl_basic(string.byte(src, s, s + 7)) 
end

-- Big endian double reader
local function rd_dbl_be(src, s)
	local f1, f2, f3, f4, f5, f6, f7, f8 = string.byte(src, s, s + 7)
	return rd_dbl_basic(f8, f7, f6, f5, f4, f3, f2, f1)
end

-- Float type mappings
local float_types = {
	[4] = {little = rd_flt_le, big = rd_flt_be},
	[8] = {little = rd_dbl_le, big = rd_dbl_be},
}

return {
	rd_int_le = rd_int_le,
	rd_int_be = rd_int_be,
	float_types = float_types,
}
