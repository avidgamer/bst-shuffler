-- BSTShuffler.lua
-- Ironmon Tracker Extension
-- Shuffles BST values across all mons inside PokemonData directly
-- This is what the tracker actually reads and displays
-- Place in your extensions folder and enable in Settings > Extensions

local function BSTShuffler()
	local self = {
		version         = "1.0.1",
		name            = "BST Shuffler",
		author          = "You",
		description     = "Shuffles BST values across all mons each run. Works on tracker display AND game memory.",
		extensionKey    = "BSTShuffler",
		requiredVersion = "v8.5.0",
		hasShuffled     = false,

		-- Fire Red ROM base stats table
		-- Used to write shuffled stats back to actual game memory too
		BASE_STATS_ADDR = 0x08254784,
		ENTRY_SIZE      = 28,
	}

	-- ============================================================
	-- FISHER-YATES SHUFFLE
	-- ============================================================
	function self.shuffle(t)
		for i = #t, 2, -1 do
			local j = math.random(i)
			t[i], t[j] = t[j], t[i]
		end
		return t
	end

	-- ============================================================
	-- STEP 1: Collect all BST values from PokemonData
	-- This is what the tracker actually reads — not ROM memory
	-- ============================================================
	function self.collectBSTs()
		local bst_pool = {}
		local indices  = {}

		for i, mon in pairs(PokemonData.Pokemon) do
			-- skip placeholder/empty entries
			-- tonumber() handles cases where bst is stored as a string
			local bst_val = tonumber(mon and mon.bst)
			if bst_val and bst_val > 0 then
				table.insert(bst_pool, bst_val)
				table.insert(indices, i)
			end
		end

		return bst_pool, indices
	end

	-- ============================================================
	-- STEP 2: Freely distribute a BST into 6 individual stats
	-- Matches real randomizer methodology:
	--   HP floor  = 1, all others floor = 11, cap at 255
	-- ============================================================
	function self.distributeStats(bst)
		local FLOORS      = { 1, 11, 11, 11, 11, 11 }
		local floor_total = 0
		for _, f in ipairs(FLOORS) do floor_total = floor_total + f end

		local remaining = math.max(0, bst - floor_total)

		-- 5 random cut points across [0, remaining] -> 6 segments
		local cuts = {}
		for i = 1, 5 do cuts[i] = math.random(0, remaining) end
		table.sort(cuts)

		local allocs = {}
		allocs[1] = cuts[1]
		for i = 2, 5 do allocs[i] = cuts[i] - cuts[i - 1] end
		allocs[6] = remaining - cuts[5]

		local stats = {}
		for i = 1, 6 do
			stats[i] = math.min(255, FLOORS[i] + allocs[i])
		end

		-- returns: hp, atk, def, spd, spatk, spdef
		return stats[1], stats[2], stats[3], stats[4], stats[5], stats[6]
	end

	-- ============================================================
	-- STEP 3: Write stats to ROM memory so the game uses them too
	-- ============================================================
	function self.writeToROM(dex_index, hp, atk, def, spd, spatk, spdef)
		-- dex_index is 1-based, ROM table is 0-based
		local base = self.BASE_STATS_ADDR + ((dex_index - 1) * self.ENTRY_SIZE)
		memory.write_u8(base + 0, hp)
		memory.write_u8(base + 1, atk)
		memory.write_u8(base + 2, def)
		memory.write_u8(base + 3, spd)
		memory.write_u8(base + 4, spatk)
		memory.write_u8(base + 5, spdef)
	end

	-- ============================================================
	-- MAIN SHUFFLE ROUTINE
	-- ============================================================
	function self.runShuffle()
		if self.hasShuffled then return end

		math.randomseed(os.time())

		-- Collect BST pool from tracker's internal PokemonData
		local bst_pool, indices = self.collectBSTs()
		local total = #bst_pool

		if total == 0 then
			print("[BSTShuffler] ERROR: PokemonData not ready yet.")
			return
		end

		-- Shuffle the BST pool
		self.shuffle(bst_pool)
		print(string.format("[BSTShuffler] Shuffling %d BST values...", total))

		-- Apply shuffled BSTs back into PokemonData AND ROM memory
		for i, dex_index in ipairs(indices) do
			local new_bst = bst_pool[i]
			local mon     = PokemonData.Pokemon[dex_index]

			if mon then
				-- Update tracker display (force number type)
				mon.bst = tonumber(new_bst)

				-- Only write to ROM for mons within the base Fire Red stats table
				-- NatDex mons beyond index 411 have no ROM slot — writing causes memory warnings
				if Main.IsOnBizhawk() and dex_index <= 411 then
					local hp, atk, def, spd, spatk, spdef = self.distributeStats(new_bst)
					self.writeToROM(dex_index, hp, atk, def, spd, spatk, spdef)
				end
			end
		end

		self.hasShuffled = true
		print(string.format("[BSTShuffler] Done. %d mons updated.", total))
	end

	-- ============================================================
	-- TRACKER EXTENSION HOOKS
	-- ============================================================

	-- Runs once after tracker loads all data including NatDex extension
	-- Because extensions run after PokemonData.buildData() this timing is correct
	function self.startup()
		-- Must be on BizHawk for memory writes
		-- Display shuffle still works on mGBA (just skips ROM write)
		self.runShuffle()
	end

	function self.unload()
		self.hasShuffled = false
		print("[BSTShuffler] Unloaded. Restart tracker for a fresh shuffle.")
	end

	function self.checkForUpdates()
		-- no update server
	end

	return self
end

return BSTShuffler
