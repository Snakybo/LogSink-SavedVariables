-- LogSink: SavedVariables, an addon that captures the output of LibLog, and saves it in saved variables.
-- Copyright (C) 2026  Kevin Krol
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

local LibLog = LibStub("LibLog")

--- @class LogSinkSavedVariables : AceAddon, AceEvent-3.0
LogSinkSavedVariables = LibStub("AceAddon-3.0"):NewAddon("LogSinkSavedVariables", "AceEvent-3.0")

--- @class DBSchema
--- @field public sessionId integer
--- @field public buffer table<string, LibLog.LogMessage[]>

--- @class LogBuffer
--- @field public entries LibLog.LogMessage[]
--- @field public head integer

--- @alias BufferRestoreCallback fun(buffer: LibLog.LogMessage[])

local MAX_LOGS_PER_ADDON = 1000

--- @type table<string, LogBuffer>
local logs = {}

--- @type BufferRestoreCallback[]
local callbacks = {}

local sessionId = 1
local initialized = false

--- @param addon string
--- @param message LibLog.LogMessage
local function AddLog(addon, message)
	local buffer = logs[addon]

	if buffer == nil then
		buffer = {
			entries = {},
			head = 1
		}
		logs[addon] = buffer
	end

	buffer.entries[buffer.head] = message
	buffer.head = (buffer.head % MAX_LOGS_PER_ADDON) + 1
end

local function GetSortedBuffer()
	--- @type LibLog.LogMessage[]
	local result = {}

	for _, buffer in pairs(LogSinkSavedVariables:GetBuffer()) do
		for i = 1, #buffer do
			table.insert(result, buffer[i])
		end
	end

	table.sort(result, function(lhs, rhs)
		if lhs.time == rhs.time then
			return lhs.sequenceId < rhs.sequenceId
		end

		return lhs.time < rhs.time
	end)

	return result
end

local function NotifyCallbacks()
	local buffer = GetSortedBuffer()

	for _, func in ipairs(callbacks) do
		xpcall(func, geterrorhandler(), buffer)
	end
end

--- @param message LibLog.LogMessage
local function OnLogReceived(message)
	if message.addon == nil then
		return
	end

	AddLog(message.addon, message)
end

--- @param event string
--- @param isInitialLogin boolean
--- @param isReload boolean
local function PLAYER_ENTERING_WORLD(event, isInitialLogin, isReload)
	local addedAny = false

	--- @type DBSchema?
	local db = LogSinkSavedVariablesDB

	if isReload and db ~= nil then
		sessionId = db.sessionId + 1

		for addon, buffer in pairs(db.buffer) do
			local cache = logs[addon]
			logs[addon] = nil

			for _, message in ipairs(buffer) do
				AddLog(addon, message)
				addedAny = true
			end

			if cache ~= nil then
				for _, message in ipairs(cache.entries) do
					AddLog(addon, message)
				end
			end
		end
	end

	initialized = true

	if addedAny and #callbacks > 0 then
		NotifyCallbacks()
	end
end

local function PLAYER_LOGOUT()
	--- @type DBSchema
	LogSinkSavedVariablesDB = {
		buffer = LogSinkSavedVariables:GetBuffer(LogSinkSavedVariablesDB.buffer),
		sessionId = sessionId
	}

	for _, buffer in pairs(LogSinkSavedVariablesDB.buffer) do
		for _, log in ipairs(buffer) do
			---@diagnostic disable-next-line: inject-field
			log.sessionId = log.sessionId or sessionId
		end
	end
end

--- @private
function LogSinkSavedVariables:OnInitialize()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", PLAYER_ENTERING_WORLD)
	self:RegisterEvent("PLAYER_LOGOUT", PLAYER_LOGOUT)
end

--- Get the currently buffered logs.
---
--- This returns a dictionary format where addon->logs[]. In order to create a single table containing a sequential sequence of all logs, you can safely sort
--- your combined table on the `time` and `sequenceId` properties.
---
--- See the local `NotifyCallbacks` function for an example.
---
--- @param result? table<string, LibLog.LogMessage[]>
--- @return table<string, LibLog.LogMessage[]>
function LogSinkSavedVariables:GetBuffer(result)
	result = result or {}

	for addon, buffer in pairs(logs) do
		local current

		if #buffer.entries < MAX_LOGS_PER_ADDON then
			current = buffer.entries
		else
			current = {}

			for i = buffer.head, MAX_LOGS_PER_ADDON do
				table.insert(current, buffer.entries[i])
			end

			for i = 1, buffer.head - 1 do
				table.insert(current, buffer.entries[i])
			end
		end

		result[addon] = current
	end

	return result
end

--- Register a callback function to be invoked when the log buffer has become available. If no buffered logs are available, the callback function will **not**
--- be invoked.
---
--- @param func BufferRestoreCallback
function LogSinkSavedVariables:GetBufferWhenAvailable(func)
	if initialized then
		xpcall(func, geterrorhandler(), GetSortedBuffer())
	else
		table.insert(callbacks, func)
	end
end

LibLog:RegisterSink(LogSinkSavedVariables.name, OnLogReceived)
