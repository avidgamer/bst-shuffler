-- BSTShuffler.lua
-- Ironmon Tracker Extension
-- Reads all mon BSTs from ROM memory at startup, shuffles the pool,
-- then freely redistributes stats — no shape preservation, matches
-- real randomizer methodology (floor: HP min 1, all others min 11)

local function BSTShuffler()
	local self = {
		version      = "1.0.0",
		name         = "BST Shuffler",
		author       = "You",
		description  = "Shuffles BST values across all mons at game start. Each run is unique.",
		extensionKey = "BSTShuffler",       -- must match this filename exactly
		requiredVersion = "v8.5.0",         -- minimum tracker version

		-- Fire Red base stats table in ROM
		BASE_STATS_ADDR = 0x08254784,
		ENTRY_SIZE      = 28,
		TOTAL_MONS      = 1210,

		-- Track whether shuffle has run this session
		hasShuffled = false,
	}

	-- ============================================================
	-- CORE SHUFFLE LOGIC
	-- ============================================================

	-- Read every mon's current BST and ROM address
	function self.readAllBSTs()
		local mons = {}
		for i = 0, self.TOTAL_MONS - 1 do
			local base  = self.BASE_STATS_ADDR + (i * self.ENTRY_SIZE)
			local hp    = memory.read_u8(base + 0)
			local atk   = memory.read_u8(base + 1)
			local def   = memory.read_u8(base + 2)
			local spd   = memory.read_u8(base + 3)
			local spatk = memory.read_u8(base + 4)
			local spdef = memory.read_u8(base + 5)
			mons[i + 1] = {
				addr = base,
				bst  = hp + atk + def + spd + spatk + spdef,
			}
		end
		return mons
	end

	-- Fisher-Yates shuffle — every permutation equally likely
	function self.shuffle(t)
		for i = #t, 2, -1 do
			local j = math.random(i)
			t[i], t[j] = t[j], t[i]
		end
		return t
	end

	-- Freely distribute a BST across 6 stats using random cut points
	-- Matches real randomizer behavior:
	--   HP floor  = 1
	--   All other stat floors = 11
	--   Hard cap at 255 per stat
	function self.distributeStats(bst)
		local FLOORS     = { 1, 11, 11, 11, 11, 11 }
		local floor_total = 0
		for _, f in ipairs(FLOORS) do
			floor_total = floor_total + f
		end

		local remaining = math.max(0, bst - floor_total)

		-- Place 5 random cut points across [0, remaining]
		-- then sort to get 6 random segments that sum to remaining
		local cuts = {}
		for i = 1, 5 do
			cuts[i] = math.random(0, remaining)
		end
		table.sort(cuts)

		local allocs = {}
		allocs[1] = cuts[1]
		for i = 2, 5 do
			allocs[i] = cuts[i] - cuts[i - 1]
		end
		allocs[6] = remaining - cuts[5]

		-- Add floors back, cap each stat at 255
		local stats = {}
		for i = 1, 6 do
			stats[i] = math.min(255, FLOORS[i] + allocs[i])
		end

		-- stats order: HP, ATK, DEF, SPD, SPATK, SPDEF
		return stats[1], stats[2], stats[3], stats[4], stats[5], stats[6]
	end

	-- Write the 6 stats back to ROM memory for a mon
	function self.writeStats(addr, hp, atk, def, spd, spatk, spdef)
		memory.write_u8(addr + 0, hp)
		memory.write_u8(addr + 1, atk)
		memory.write_u8(addr + 2, def)
		memory.write_u8(addr + 3, spd)
		memory.write_u8(addr + 4, spatk)
		memory.write_u8(addr + 5, spdef)
	end

	-- Main shuffle routine — runs once per startup
	function self.runShuffle()
		if self.hasShuffled then
			return
		end

		math.randomseed(os.time())

		print("[BSTShuffler] Reading all BSTs from ROM...")
		local mons = self.readAllBSTs()

		-- Pull all BST values into a flat pool
		local bst_pool = {}
		for _, m in ipairs(mons) do
			table.insert(bst_pool, m.bst)
		end

		-- Shuffle the pool
		self.shuffle(bst_pool)
		print(string.format("[BSTShuffler] Pool of %d BSTs shuffled.", #bst_pool))

		-- Redistribute: each mon gets a random BST from the pool
		-- stats freely distributed within that BST
		for i, mon in ipairs(mons) do
			local new_bst                       = bst_pool[i]
			local hp, atk, def, spd, spatk, spdef = self.distributeStats(new_bst)
			self.writeStats(mon.addr, hp, atk, def, spd, spatk, spdef)
		end

		self.hasShuffled = true
		print(string.format("[BSTShuffler] Done. %d mons updated with shuffled BSTs.", self.TOTAL_MONS))
	end

	-- ============================================================
	-- TRACKER EXTENSION HOOKS
	-- ============================================================

	-- Called once when the extension is enabled or tracker starts
	function self.startup()
		-- Verify tracker version is compatible
		if not (Main and Main.IsOnBizhawk and Main.IsOnBizhawk()) then
			print("[BSTShuffler] Warning: Not running on BizHawk. Memory writes unavailable.")
			return
		end

		self.runShuffle()
	end

	-- Called when the user disables the extension
	-- We cannot undo memory writes after the fact, so we just notify
	function self.unload()
		print("[BSTShuffler] Extension unloaded. Restart the tracker to get a fresh shuffle.")
		self.hasShuffled = false
	end

	-- Optional: hook for tracker update checks (can be left empty)
	function self.checkForUpdates()
		-- no update server for this extension
	end

	return self
end

return BSTShuffler
