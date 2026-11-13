-- AHelper: curated list of open-world farmable trade goods.
-- Fields: id = itemID, cat = category, lvl = rough character level to farm comfortably, where = suggested spots.
-- Edit freely: anything added here shows up in the Farming tab and is included in the sniper rotation.
local _, ns = ...

ns.FarmDB = {
    -- Cloth (humanoid drops)
    { id = 2589,  cat = "Cloth", lvl = 10, where = "Defias in Westfall, Quilboar in Barrens" },
    { id = 2592,  cat = "Cloth", lvl = 25, where = "Hillsbrad, Arathi Highlands, Stromgarde" },
    { id = 4306,  cat = "Cloth", lvl = 35, where = "Stranglethorn (Bloodscalp/Skullsplitter), Badlands" },
    { id = 4338,  cat = "Cloth", lvl = 45, where = "Tanaris (Wastewander), Feralas, Hinterlands" },
    { id = 14047, cat = "Cloth", lvl = 55, where = "Eastern Plaguelands, Winterspring, Silithus, Burning Steppes" },
    { id = 14256, cat = "Cloth", lvl = 58, where = "Jaedenar (Felwood) satyrs, Shadow Hold" },

    -- Herbs
    { id = 2447,  cat = "Herb", lvl = 5,  where = "Starter zones" },
    { id = 765,   cat = "Herb", lvl = 5,  where = "Starter zones" },
    { id = 2449,  cat = "Herb", lvl = 8,  where = "Starter zones, Barrens, Westfall" },
    { id = 785,   cat = "Herb", lvl = 15, where = "Barrens, Westfall, Darkshore" },
    { id = 2450,  cat = "Herb", lvl = 15, where = "Barrens, Westfall, Redridge" },
    { id = 3820,  cat = "Herb", lvl = 20, where = "Coastlines: Wetlands, Darkshore, Hillsbrad" },
    { id = 2453,  cat = "Herb", lvl = 20, where = "Wetlands, Ashenvale, Stonetalon" },
    { id = 3355,  cat = "Herb", lvl = 30, where = "Arathi, Stranglethorn, Thousand Needles" },
    { id = 3369,  cat = "Herb", lvl = 30, where = "Graveyards: Duskwood, Arathi, Dustwallow" },
    { id = 3356,  cat = "Herb", lvl = 30, where = "Arathi, Hillsbrad, Stranglethorn" },
    { id = 3357,  cat = "Herb", lvl = 35, where = "Riverbanks: Stranglethorn, Swamp of Sorrows" },
    { id = 3818,  cat = "Herb", lvl = 35, where = "Stranglethorn, Swamp of Sorrows, Dustwallow" },
    { id = 3821,  cat = "Herb", lvl = 35, where = "Arathi, Stranglethorn, Badlands, Feralas" },
    { id = 3358,  cat = "Herb", lvl = 40, where = "Hinterlands, Stranglethorn, Feralas" },
    { id = 3819,  cat = "Herb", lvl = 40, where = "Alterac Mountains" },
    { id = 4625,  cat = "Herb", lvl = 45, where = "Searing Gorge, Blasted Lands, Tanaris" },
    { id = 8831,  cat = "Herb", lvl = 45, where = "Azshara, Feralas, Tanaris, Hinterlands" },
    { id = 8836,  cat = "Herb", lvl = 45, where = "Western/Eastern Plaguelands, Felwood" },
    { id = 8838,  cat = "Herb", lvl = 45, where = "Feralas, Un'Goro, Azshara, Hinterlands" },
    { id = 8839,  cat = "Herb", lvl = 45, where = "Swamp of Sorrows, Un'Goro" },
    { id = 8845,  cat = "Herb", lvl = 45, where = "Caves: Hinterlands, Maraudon, Feralas" },
    { id = 8846,  cat = "Herb", lvl = 50, where = "Felwood, Blasted Lands, Ashenvale (Demon Fall)" },
    { id = 13464, cat = "Herb", lvl = 50, where = "Felwood, Un'Goro, Azshara, Feralas" },
    { id = 13463, cat = "Herb", lvl = 52, where = "Un'Goro, Felwood, Azshara, Western Plaguelands" },
    { id = 13465, cat = "Herb", lvl = 52, where = "Winterspring, Azshara, Un'Goro, Burning Steppes" },
    { id = 13466, cat = "Herb", lvl = 55, where = "Eastern/Western Plaguelands, Felwood" },
    { id = 13467, cat = "Herb", lvl = 55, where = "Winterspring" },
    { id = 13468, cat = "Herb", lvl = 58, where = "Rare spawn: Burning Steppes, EPL, Silithus, Winterspring" },

    -- Ore & stone
    { id = 2770,  cat = "Ore", lvl = 8,  where = "Starter zones, Westfall, Barrens" },
    { id = 2771,  cat = "Ore", lvl = 20, where = "Redridge, Wetlands, Stonetalon, Hillsbrad" },
    { id = 2772,  cat = "Ore", lvl = 35, where = "Arathi, Desolace, Stranglethorn, Thousand Needles" },
    { id = 2775,  cat = "Ore", lvl = 25, where = "Rare node in Tin/Iron zones" },
    { id = 2776,  cat = "Ore", lvl = 35, where = "Rare node in Iron/Mithril zones" },
    { id = 3858,  cat = "Ore", lvl = 45, where = "Hinterlands, Badlands, Tanaris, Searing Gorge" },
    { id = 7911,  cat = "Ore", lvl = 45, where = "Rare node in Mithril zones" },
    { id = 10620, cat = "Ore", lvl = 55, where = "Un'Goro, Burning Steppes, Winterspring, Silithus" },
    { id = 11370, cat = "Ore", lvl = 58, where = "Blackrock Depths, Molten Core" },
    { id = 2836,  cat = "Ore", lvl = 20, where = "Mining Tin" },
    { id = 2838,  cat = "Ore", lvl = 35, where = "Mining Iron" },
    { id = 7912,  cat = "Ore", lvl = 45, where = "Mining Mithril" },
    { id = 12365, cat = "Ore", lvl = 55, where = "Mining Thorium" },
    { id = 12363, cat = "Ore", lvl = 55, where = "Rich Thorium veins (Un'Goro, Winterspring)" },

    -- Leather (skinning)
    { id = 2318,  cat = "Leather", lvl = 10, where = "Any beasts 1-20" },
    { id = 2319,  cat = "Leather", lvl = 20, where = "Beasts 20-30: Hillsbrad, Stonetalon" },
    { id = 4234,  cat = "Leather", lvl = 30, where = "Beasts 30-40: Arathi, Stranglethorn raptors" },
    { id = 4304,  cat = "Leather", lvl = 40, where = "Beasts 40-50: Feralas, Tanaris, Un'Goro" },
    { id = 8170,  cat = "Leather", lvl = 50, where = "Beasts 50+: Winterspring, Burning Steppes, Un'Goro" },
    { id = 15417, cat = "Leather", lvl = 60, where = "Devilsaurs in Un'Goro Crater" },
    { id = 8171,  cat = "Leather", lvl = 50, where = "Beasts 50+ (rare hide)" },
    { id = 8167,  cat = "Leather", lvl = 40, where = "Turtles: Feralas coast, Tanaris" },
    { id = 8154,  cat = "Leather", lvl = 45, where = "Scorpids: Tanaris, Blasted Lands, Searing Gorge" },
    { id = 15416, cat = "Leather", lvl = 55, where = "Black dragonkin: Burning Steppes" },
    { id = 15414, cat = "Leather", lvl = 55, where = "Red dragonkin: Swamp of Sorrows, Burning Steppes" },
    { id = 15412, cat = "Leather", lvl = 55, where = "Green dragonkin: Feralas, Hinterlands, Ashenvale portals" },
    { id = 15415, cat = "Leather", lvl = 55, where = "Blue dragonkin: Azshara, Winterspring" },

    -- Elemental reagents
    { id = 7068,  cat = "Elemental", lvl = 45, where = "Fire elementals: Searing Gorge, Burning Steppes" },
    { id = 7067,  cat = "Elemental", lvl = 40, where = "Earth elementals: Badlands, Desolace, Arathi" },
    { id = 7070,  cat = "Elemental", lvl = 40, where = "Water elementals: Dustwallow, Azshara, Felwood" },
    { id = 7069,  cat = "Elemental", lvl = 40, where = "Air elementals: Arathi, Azshara, Silithus" },
    { id = 7078,  cat = "Elemental", lvl = 55, where = "Searing Gorge / Burning Steppes fire elementals" },
    { id = 7076,  cat = "Elemental", lvl = 55, where = "Un'Goro / Felwood earth elementals" },
    { id = 7080,  cat = "Elemental", lvl = 55, where = "Felwood (Irontree), EPL, Azshara water elementals" },
    { id = 7082,  cat = "Elemental", lvl = 55, where = "Silithus, Winterspring, Azshara air elementals" },
    { id = 12808, cat = "Elemental", lvl = 55, where = "Undead: Western/Eastern Plaguelands, Scholomance" },
    { id = 12803, cat = "Elemental", lvl = 55, where = "Un'Goro bloodpetals/elementals, Felwood" },
    { id = 7972,  cat = "Elemental", lvl = 40, where = "Undead 40+: Plaguelands, Duskwood" },

    -- Silk / misc trade goods
    { id = 3182,  cat = "Misc", lvl = 20, where = "Spiders 20-30: Duskwood, Wetlands, Ashenvale" },
    { id = 4337,  cat = "Misc", lvl = 35, where = "Spiders 35-45: Stranglethorn, Dustwallow" },
    { id = 14227, cat = "Misc", lvl = 55, where = "Spiders 55+: Winterspring, Felwood, Burning Steppes" },
    { id = 10285, cat = "Misc", lvl = 45, where = "Spiders 45+: Tanaris, Searing Gorge, Hinterlands" },
    { id = 12207, cat = "Misc", lvl = 45, where = "Birds/hippogryphs: Feralas, Tanaris, Hinterlands" },
    { id = 12205, cat = "Misc", lvl = 50, where = "Spiders: Burning Steppes, Winterspring" },
    { id = 12208, cat = "Misc", lvl = 45, where = "Wolves/worgs: Winterspring, Burning Steppes" },
    { id = 7974,  cat = "Misc", lvl = 40, where = "Clams: Stranglethorn coast, Feralas, Azshara" },
    { id = 12662, cat = "Misc", lvl = 55, where = "Demons: Felwood, Blasted Lands, Azshara" },

    -- Fish
    { id = 6358,  cat = "Fish", lvl = 1,  where = "Pools: Barrens/Westfall coasts, Wetlands" },
    { id = 6359,  cat = "Fish", lvl = 1,  where = "Pools: Wetlands, Stranglethorn, Swamp of Sorrows" },
    { id = 6522,  cat = "Fish", lvl = 1,  where = "Wailing Caverns oasis (Barrens)" },
    { id = 13422, cat = "Fish", lvl = 1,  where = "Stonescale Eel pools: Feralas, Tanaris, Azshara coasts" },

    -- Gems (mining by-products / chests)
    { id = 7910,  cat = "Gem", lvl = 45, where = "Mithril/Truesilver nodes" },
    { id = 12361, cat = "Gem", lvl = 55, where = "Thorium veins (Alliance-side rarity)" },
    { id = 12799, cat = "Gem", lvl = 55, where = "Thorium veins (Horde-side rarity)" },
    { id = 12364, cat = "Gem", lvl = 55, where = "Rich Thorium veins" },
    { id = 12800, cat = "Gem", lvl = 55, where = "Rich Thorium veins" },
    { id = 5500,  cat = "Gem", lvl = 25, where = "Iridescent Pearls from clams" },
}

ns.FarmSet = {}
for _, e in ipairs(ns.FarmDB) do ns.FarmSet[e.id] = e end
