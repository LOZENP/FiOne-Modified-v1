--[[
FiOne - Modular Version
Copyright (C) 2025  Rerumu

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
]]--

local compat = require('fione.compat')
local deserializer = require('fione.deserializer')
local vm = require('fione.vm')

return {
	bc_to_state = deserializer.bc_to_state,
	wrap_state = vm.wrap_state,
	OPCODE_RM = require('fione.opcodes').OPCODE_RM,
	OPCODE_T = require('fione.opcodes').OPCODE_T,
	OPCODE_M = require('fione.opcodes').OPCODE_M,
}
