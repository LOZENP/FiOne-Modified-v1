--[[
Compatibility layer for different Lua versions
]]--

local bit = bit or bit32 or require('bit')

-- Polyfills for table functions
if not table.create then 
	if table.new then 
		table.create = table.new 
	else 
		function table.create(_) 
			return {} 
		end 
	end 
end

if not table.unpack then 
	table.unpack = unpack 
end

if not table.pack then 
	function table.pack(...) 
		return {n = select('#', ...), ...} 
	end 
end

if not table.move then
	function table.move(src, first, last, offset, dst)
		for i = 0, last - first do 
			dst[offset + i] = src[first + i] 
		end
	end
end

return {
	bit = bit,
}
