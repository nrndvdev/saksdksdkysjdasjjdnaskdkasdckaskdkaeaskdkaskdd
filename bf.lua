-- Standalone client UI. No remote code downloads or executor installation.
-- Experimental Blox Fruits adapter. Server compatibility must be checked in-game.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer
assert(localPlayer, "Run this script on the client")
local playerGui = localPlayer:WaitForChild("PlayerGui")
local FARM_HEIGHT = 33
local WINDOW_WIDTH,WINDOW_HEIGHT=1080,688
local BUILD = "V32"
local ATTACK_INTERVAL = 0.025
local RAID_ATTACK_INTERVAL = 0.025
playerGui:SetAttribute("ViltrumFarmHeight", nil) -- discard the removed height preference
playerGui:SetAttribute("ViltrumAttackRate", nil)
playerGui:SetAttribute("ViltrumStyle",nil) -- slot 1 replaces the old style-name preference

local CONFIG = {
    AutoAura=playerGui:GetAttribute("ViltrumAutoAura")~=false,
    RaidRadius=100,
    RaidIslandRadius=450,
    RaidClearWait=2,
    RaidHeight=61,
    DodgeRadius=100,
    DodgeSide=60,
    DodgeSpeed=222,
    DodgeGrace=.2,
    WeaponType=playerGui:GetAttribute("ViltrumWeaponType")=="Fruit" and "Fruit" or playerGui:GetAttribute("ViltrumWeaponType")=="Sword" and "Sword" or "Melee",
    SwordSlot=3,
    FruitSlot=2,
    FruitPercent=20,
    FruitSkills={},
    TravelSpeed = 222,
    WalkSpeed = 32,
    FarmSideOffset = 0,
    FarmRadius=100,
    RaidSideOffset = 0,
    PositionTolerance = 1.5,
    QuestRange = 5,
    WorkerInterval = 0.025,
    QuestCooldown = 3,
    SpawnWait = 8,
    NoDamageTimeout = 15,
}
do
local savedSwordSlot=tonumber(playerGui:GetAttribute("ViltrumSwordSlot"))
if savedSwordSlot and savedSwordSlot>=1 and savedSwordSlot<=10 then CONFIG.SwordSlot=math.floor(savedSwordSlot)end
for _,key in ipairs({"Z","X","C","V"})do CONFIG.FruitSkills[key]=playerGui:GetAttribute("ViltrumFruit"..key)==true end
for key,attribute in pairs({FruitSlot="ViltrumFruitSlot",FruitPercent="ViltrumFruitPercent"})do
    local saved=tonumber(playerGui:GetAttribute(attribute))
    if saved and saved==saved then CONFIG[key]=math.floor(math.clamp(saved,1,key=="FruitSlot" and 10 or 50))end
end
local savedRaidRadius=tonumber(playerGui:GetAttribute("ViltrumRaidRadius"))
if savedRaidRadius and savedRaidRadius==savedRaidRadius then CONFIG.RaidRadius=math.floor(math.clamp(savedRaidRadius,50,100))end
local savedSpeed=tonumber(playerGui:GetAttribute("ViltrumWalkSpeed"))
if savedSpeed and savedSpeed==savedSpeed then CONFIG.WalkSpeed=math.floor(math.clamp(savedSpeed,1,222))end
end
local Core = (function()
local Core = {}
function Core.statAmount(value)
    local n=tonumber(value)
    if not n or n~=n or n==math.huge or n==-math.huge then return 0 end
    return math.clamp(math.floor(n),0,100)
end
function Core.statsPlan(rules,budget)
    local plan={}
    if type(budget)~="number" or budget~=budget or budget==math.huge or budget<=0 then return plan end
    budget=math.floor(budget)
    for _,rule in ipairs(rules)do
        local amount=math.min(Core.statAmount(rule.amount),budget)
        if amount>0 then table.insert(plan,{name=rule.remote,amount=amount});budget-=amount end
        if budget<=0 then break end
    end
    return plan
end
Core.SEA_BY_PLACE = {
    [2753915549]=1, [85211729168715]=1,
    [4442272183]=2, [79091703265657]=2,
    [7449423635]=3, [100117331123089]=3,
}

function Core.selectQuest(rows, level, sea)
    if type(level) ~= "number" or level ~= level or not rows then return nil end
    local floorLevel = sea == 1 and 0 or sea == 2 and 700 or 1500
    local ceiling = sea == 1 and 700 or sea == 2 and 1500 or math.huge
    local selected
    for _, row in ipairs(rows) do
        if row[1] >= floorLevel and row[1] < ceiling and row[1] <= level then
            if not selected or row[1] > selected[1] then selected = row end
        end
    end
    return selected
end

function Core.normalizeName(name)
    return string.lower((name:gsub("<.->", ""):gsub("%s*%[.-%]", "")):match("^%s*(.-)%s*$"))
end

function Core.styleKey(value)
    if type(value)~="string"then return "" end
    return (Core.normalizeName(value):gsub("[%s_%-]", ""))
end
local STYLE_NAMES = {
    ["combat"]=true, ["black leg"]=true, ["dark step"]=true,
    ["electro"]=true, ["electric"]=true, ["fishman karate"]=true,
    ["water kung fu"]=true, ["dragon claw"]=true, ["dragon breath"]=true,
    ["superhuman"]=true, ["death step"]=true, ["sharkman karate"]=true,
    ["electric claw"]=true, ["dragon talon"]=true, ["godhuman"]=true,
    ["sanguine art"]=true,
}
local STYLES={}
for name in pairs(STYLE_NAMES)do STYLES[Core.styleKey(name)]=true end
local NON_MELEE={sword=true,gun=true,fruit=true,bloxfruit=true,demonfruit=true}
function Core.isFightingStyle(name, tooltip, category)
    local tag = Core.styleKey(tooltip)
    local kind = Core.styleKey(category)
    if NON_MELEE[tag] or NON_MELEE[kind] then return false end
    return tag == "melee" or tag == "fightingstyle" or kind == "melee" or kind == "fightingstyle"
        or STYLES[Core.styleKey(name)] == true
end
function Core.weaponMatches(mode,name,tooltip,category)
    if mode=="Melee"then return Core.isFightingStyle(name,tooltip,category)end
    if mode=="Fruit"then
        local tag,kind=Core.styleKey(tooltip),Core.styleKey(category)
        local tags={fruit=true,bloxfruit=true,demonfruit=true}
        if tag=="melee" or tag=="sword" or tag=="gun" or kind=="melee" or kind=="sword" or kind=="gun"then return false end
        return tags[tag]==true or tags[kind]==true
    end
    if mode~="Sword"then return false end
    local tag,kind=Core.styleKey(tooltip),Core.styleKey(category)
    if tag=="melee" or tag=="fightingstyle" or tag=="gun" or tag=="fruit" or tag=="bloxfruit" or tag=="demonfruit"then return false end
    if kind=="melee" or kind=="fightingstyle" or kind=="gun" or kind=="fruit" or kind=="bloxfruit" or kind=="demonfruit"then return false end
    return tag=="sword" or kind=="sword"
end
function Core.fruitReady(target,percent,skills)
    if not target or type(target.maxHealth)~="number" or target.maxHealth<=0 or target.health<=0 then return false end
    local selected=false
    for _,key in ipairs({"Z","X","C","V"})do if skills[key]==true then selected=true end end
    return selected and target.health/target.maxHealth*100<=percent
end
function Core.npcSkillCue(info)
    if not info or info.playing==false then return false end
    local name=Core.styleKey(info.name)
    if name=="m1" or name=="basicattack" or name:match("^punch%d*$") or name:match("^hit%d+$")
        or name:match("^slash%d+$") or name:match("^combo") or name:match("^idle")
        or name:match("^walk") or name:match("^run") or name:match("^hurt")
        or name:match("^hitreaction") or name:match("^stun")then return false end
    if info.isSkill==false then return false end
    if info.isSkill==true or info.skillFolder or info.knownId or info.npcCasting then return true end
    local kind=Core.styleKey(info.kind)
    if kind=="skill" or kind=="ability"then return true end
    local key=Core.styleKey(info.key)
    if key=="z" or key=="x" or key=="c" or key=="v" or key=="f"then return true end
    if name=="z" or name=="x" or name=="c" or name=="v" or name=="f"then return true end
    return name:match("^skill")~=nil or name:match("^ability")~=nil or name:match("^cast")~=nil
end
Core.COMBAT_HEIGHTS={11,9,7,5,3}
function Core.updateCombatProbe(probe,weapon,target,health,now,startIndex,startMode)
    if not probe or probe.weapon~=weapon or probe.target~=target then
        return {weapon=weapon,target=target,health=health,heightIndex=startIndex or 1,
            mode=startMode or "Net",attempts=0,startedAt=now,progress=false}
    end
    probe.progress=health<probe.health
    if probe.progress then probe.attempts=0;probe.startedAt=now end
    probe.health=health
    if probe.attempts>=6 and now-probe.startedAt>=2 then
        if probe.mode=="Net" then
            probe.mode="Native"
        elseif probe.heightIndex<#Core.COMBAT_HEIGHTS then
            probe.heightIndex+=1;probe.mode="Native"
        else probe.mode=probe.mode=="Native" and "Net" or "Native"end
        probe.attempts=0;probe.startedAt=now
    end
    return probe
end
function Core.noteCombatAttempt(probe,now)
    if probe.attempts==0 then probe.startedAt=now end
    probe.attempts+=1
end

-- Fixed-height Raid cannot use the old reach ladder: resetting its height index
-- each step left Native selected forever. Retry Net even when Native sends fail.
function Core.updateFixedCombatProbe(probe,weapon,target,health,now)
    if not probe or probe.weapon~=weapon or probe.target~=target then
        return {weapon=weapon,target=target,health=health,heightIndex=1,mode="Net",observedMode="Net",
            modeSince=now,attempts=0,startedAt=now,progress=false}
    end
    if probe.mode~=probe.observedMode then
        probe.observedMode=probe.mode;probe.modeSince=now;probe.attempts=0;probe.startedAt=now
    end
    probe.progress=health<probe.health;probe.health=health
    if probe.progress and probe.mode=="Net"then probe.attempts=0;probe.startedAt=now end
    if probe.mode=="Native"and now-probe.modeSince>=2
        or probe.mode=="Net"and probe.attempts>=6 and now-probe.startedAt>=2 then
        probe.mode=probe.mode=="Native"and "Net"or "Native"
        probe.observedMode=probe.mode;probe.modeSince=now;probe.attempts=0;probe.startedAt=now
    end
    probe.heightIndex=1
    return probe
end

function Core.questMatches(title, mob)
    local text = Core.normalizeName(title)
    local name = Core.normalizeName(mob)
    if string.find(text, name, 1, true) then return true end
    if name:sub(-1) == "y" then
        return string.find(text, name:sub(1, -2) .. "ies", 1, true) ~= nil
    end
    return false
end

function Core.activeQuest(rows, title)
    if not rows or type(title)~="string" then return nil end
    local best,score=nil,0
    for _,row in ipairs(rows)do
        local length=#Core.normalizeName(row[4])
        if length>score and Core.questMatches(title,row[4])then best,score=row,length end
    end
    return best
end

function Core.isBossQuest(title, bossNames)
    if type(title)~="string" then return false end
    if string.find(string.lower(title),"[boss]",1,true)then return true end
    for _,name in ipairs(bossNames or {})do if Core.questMatches(title,name)then return true end end
    return false
end

function Core.nearestTarget(candidates, mob)
    local best, distance = nil, math.huge
    for _, candidate in ipairs(candidates) do
        if candidate.health > 0 and candidate.distance < distance
            and (not mob or Core.normalizeName(candidate.name) == Core.normalizeName(mob)) then
            best, distance = candidate, candidate.distance
        end
    end
    return best
end

-- Pure decision function: a step produces at most one effect.
function Core.decide(context)
    if not context.enabled then return "idle" end
    if not context.alive then return "respawn" end
    if context.autoQuest then
        if context.questVisible and context.questBoss then return "abandon_boss" end
        if not context.quest then return "no_quest" end
        if context.questVisible then
            if not context.questTitle then return "unknown_quest" end
            if not Core.questMatches(context.questTitle, context.quest[4]) then return "wrong_quest" end
        else
            if context.npcDistance > context.questRange then return "move_npc" end
            if context.now - context.lastQuest >= context.questCooldown then return "start_quest" end
            return "wait_quest"
        end
    end
    if not context.target then return "wait_mob" end
    if context.target.distance > context.attackRange
        or context.positionDistance and context.positionDistance > context.positionTolerance then return "move_mob" end
    if not context.hasWeapon then return "no_weapon" end
    if context.now - context.lastAttack >= context.attackCooldown then return "attack" end
    return "wait_attack"
end

return Core

end)()
local SEA_BY_PLACE = Core.SEA_BY_PLACE
local QUESTS = {
    [1] = {
        {0, "MarineQuest", 1, "Trainee", 1051.798, 14.513, 1557.743},
        {10, "JungleQuest", 1, "Monkey", -1679.763, 48.74, 175.64},
        {15, "JungleQuest", 2, "Gorilla", -1679.763, 48.74, 175.64},
        {30, "BuggyQuest1", 1, "Pirate", -1151.586, 16.615, 3863.125},
        {40, "BuggyQuest1", 2, "Brute", -1151.586, 16.615, 3863.125},
        {60, "DesertQuest", 1, "Desert Bandit", 922.315, 4.684, 4202.439},
        {75, "DesertQuest", 2, "Desert Officer", 922.315, 4.684, 4202.439},
        {90, "SnowQuest", 1, "Snow Bandit", 1400.564, 77.391, -1311.285},
        {100, "SnowQuest", 2, "Snowman", 1400.564, 77.391, -1311.285},
        {120, "MarineQuest2", 1, "Chief Petty Officer", -4699.331, 4.741, 4227.639},
        {150, "SkyQuest", 1, "Sky Bandit", -5406.294, 410.109, -694.039},
        {175, "SkyQuest", 2, "Dark Master", -5406.294, 410.109, -694.039},
        {190, "PrisonerQuest", 1, "Prisoner", 5208.339, 18.872, 736.586},
        {210, "PrisonerQuest", 2, "Dangerous Prisoner", 5208.339, 18.872, 736.586},
        {225, "ImpelQuest", 1, "Ruthless Prisoner", 5320.666, 18.886, 856.281},
        {250, "ColosseumQuest", 1, "Toga Warrior", -1342.255, 11.151, -2928.581},
        {275, "ColosseumQuest", 2, "Gladiator", -1342.255, 11.151, -2928.581},
        {300, "MagmaQuest", 1, "Military Soldier", -5308.867, 17.035, 8482.698},
        {325, "MagmaQuest", 2, "Military Spy", -5308.867, 17.035, 8482.698},
        {375, "FishmanQuest", 1, "Fishman Warrior", 61406.195, 24.519, 1626.816},
        {400, "FishmanQuest", 2, "Fishman Commando", 61406.195, 24.519, 1626.816},
        {450, "SkyExp1Quest", 1, "God's Guard", -5949.067, 5467.94, 2086.515},
        {475, "SkyExp1Quest", 2, "Shanda", -5949.067, 5467.94, 2086.515},
        {525, "SkyExp2Quest", 1, "Royal Squad", -7033.101, 5590.574, 1353.107},
        {550, "SkyExp2Quest", 2, "Royal Soldier", -7033.101, 5590.574, 1353.107},
        {625, "FountainQuest", 1, "Galley Pirate", 5263.488, 74.908, 4087.616},
        {650, "FountainQuest", 2, "Galley Captain", 5263.488, 74.908, 4087.616},
        {700, "Area1Quest", 1, "Raider", 5263.488, 74.908, 4087.616},
        {725, "Area1Quest", 2, "Mercenary", 5263.488, 74.908, 4087.616},
    },
    [2] = {
        {700, "Area1Quest", 1, "Raider", -429.544, 71.77, 1836.182},
        {725, "Area1Quest", 2, "Mercenary", -429.544, 71.77, 1836.182},
        {775, "Area2Quest", 1, "Swan Pirate", 638.445, 71.77, 918.236},
        {800, "Area2Quest", 2, "Factory Staff", 638.445, 71.77, 918.236},
        {875, "MarineQuest3", 1, "Marine Lieutenant", -2440.796, 71.714, -3216.068},
        {900, "MarineQuest3", 2, "Marine Captain", -2440.796, 71.714, -3216.068},
        {950, "ZombieQuest", 1, "Zombie", -5497.062, 47.592, -795.237},
        {975, "ZombieQuest", 2, "Vampire", -5497.062, 47.592, -795.237},
        {1000, "SnowMountainQuest", 1, "Snow Trooper", 609.859, 400.12, -5372.259},
        {1050, "SnowMountainQuest", 2, "Winter Warrior", 609.859, 400.12, -5372.259},
        {1100, "IceSideQuest", 1, "Lab Subordinate", -6231.272, 80.934, -4851.321},
        {1125, "IceSideQuest", 2, "Horned Warrior", -6231.272, 80.934, -4851.321},
        {1175, "FireSideQuest", 1, "Magma Ninja", -5403.368, 28.278, -5371.7},
        {1200, "FireSideQuest", 2, "Lava Pirate", -5403.368, 28.278, -5371.7},
        {1250, "ShipQuest1", 1, "Ship Deckhand", 1040.555, 124.943, 32909.105},
        {1275, "ShipQuest1", 2, "Ship Engineer", 1040.555, 124.943, 32909.105},
        {1300, "ShipQuest2", 1, "Ship Steward", 974.076, 124.939, 33253.621},
        {1325, "ShipQuest2", 2, "Ship Officer", 974.076, 124.939, 33253.621},
        {1350, "FrostQuest", 1, "Arctic Warrior", 5667.658, 26.8, -6486.09},
        {1375, "FrostQuest", 2, "Snow Lurker", 5667.658, 26.8, -6486.09},
        {1425, "ForgottenQuest", 1, "Sea Soldier", -3054.445, 238.344, -10142.819},
        {1450, "ForgottenQuest", 2, "Water Fighter", -3054.445, 238.344, -10142.819},
        {1500, "PiratePortQuest", 1, "Pirate Millionaire", -3054.445, 238.344, -10142.819},
        {1525, "PiratePortQuest", 2, "Pistol Billionaire", -3054.445, 238.344, -10142.819},
    },
    [3] = {
        {1500, "PiratePortQuest", 1, "Pirate Millionaire", -450.105, 107.681, 5950.726},
        {1525, "PiratePortQuest", 2, "Pistol Billionaire", -450.105, 107.681, 5950.726},
        {1575, "DragonCrewQuest", 1, "Dragon Crew Warrior", 6735.111, 126.99, -711.098},
        {1600, "DragonCrewQuest", 2, "Dragon Crew Archer", 6735.111, 126.99, -711.098},
        {1625, "VenomCrewQuest", 1, "Hydra Enforcer", 5214.339, 1003.468, 759.507},
        {1650, "VenomCrewQuest", 2, "Venomous Assailant", 5214.339, 1003.468, 759.507},
        {1700, "MarineTreeIsland", 1, "Marine Commodore", 2485.733, 73.346, -6788.625},
        {1725, "MarineTreeIsland", 2, "Marine Rear Admiral", 2485.733, 73.346, -6788.625},
        {1775, "DeepForestIsland3", 1, "Fishman Raider", -10581.656, 330.873, -8761.187},
        {1800, "DeepForestIsland3", 2, "Fishman Captain", -10581.656, 330.873, -8761.187},
        {1825, "DeepForestIsland", 1, "Forest Pirate", -13234.04, 331.488, -7625.401},
        {1850, "DeepForestIsland", 2, "Mythological Pirate", -13234.04, 331.488, -7625.401},
        {1900, "DeepForestIsland2", 1, "Jungle Pirate", -12680.382, 389.971, -9902.02},
        {1925, "DeepForestIsland2", 2, "Musketeer Pirate", -12680.382, 389.971, -9902.02},
        {1975, "HauntedQuest1", 1, "Reborn Skeleton", -9479.217, 141.215, 5566.093},
        {2000, "HauntedQuest1", 2, "Living Zombie", -9479.217, 141.215, 5566.093},
        {2025, "HauntedQuest2", 1, "Demonic Soul", -9516.993, 172.017, 6078.465},
        {2050, "HauntedQuest2", 2, "Posessed Mummy", -9516.993, 172.017, 6078.465},
        {2075, "NutsIslandQuest", 1, "Peanut Scout", -2105.532, 37.25, -10195.509},
        {2100, "NutsIslandQuest", 2, "Peanut President", -2105.532, 37.25, -10195.509},
        {2125, "IceCreamIslandQuest", 1, "Ice Cream Chef", -819.377, 64.926, -10967.283},
        {2150, "IceCreamIslandQuest", 2, "Ice Cream Commander", -819.377, 64.926, -10967.283},
        {2200, "CakeQuest1", 1, "Cookie Crafter", -2022.299, 36.928, -12030.977},
        {2225, "CakeQuest1", 2, "Cake Guard", -2022.299, 36.928, -12030.977},
        {2250, "CakeQuest2", 1, "Baking Staff", -1928.318, 37.73, -12840.626},
        {2275, "CakeQuest2", 2, "Head Baker", -1928.318, 37.73, -12840.626},
        {2300, "ChocQuest1", 1, "Cocoa Warrior", 231.75, 23.9, -12200.292},
        {2325, "ChocQuest1", 2, "Chocolate Bar Battler", 231.75, 23.9, -12200.292},
        {2350, "ChocQuest2", 1, "Sweet Thief", 151.198, 23.891, -12774.617},
        {2375, "ChocQuest2", 2, "Candy Rebel", 151.198, 23.891, -12774.617},
        {2400, "CandyQuest1", 1, "Candy Pirate", -1164.498, 59.269, -14492.618},
        {2425, "CandyQuest1", 2, "Snow Demon", -1164.498, 59.269, -14492.618},
        {2450, "TikiQuest1", 1, "Isle Outlaw", -16548.816, 55.606, -172.812},
        {2475, "TikiQuest1", 2, "Island Boy", -16548.816, 55.606, -172.812},
        {2500, "TikiQuest2", 1, "Sun-kissed Warrior", -16541.021, 54.771, 1051.461},
        {2525, "TikiQuest2", 2, "Isle Champion", -16541.021, 54.771, 1051.461},
        {2550, "TikiQuest3", 1, "Serpent Hunter", -16665.191, 104.596, 1579.694},
        {2575, "TikiQuest3", 2, "Skull Slayer", -16665.191, 104.596, 1579.694},
        {2600, "SubmergedQuest1", 1, "Reef Bandit", 10780.64, -2088.414, 9260.453},
        {2625, "SubmergedQuest1", 2, "Coral Pirate", 10780.64, -2088.414, 9260.453},
        {2650, "SubmergedQuest2", 1, "Sea Chanter", 9637.294, -1993.135, 9616.302},
        {2675, "SubmergedQuest2", 2, "Ocean Prophet", 9637.294, -1993.135, 9616.302},
        {2675, "SubmergedQuest3", 1, "High Disciple", 9637.294, -1993.135, 9616.302},
        {2700, "SubmergedQuest3", 2, "Grand Devotee", 9637.294, -1993.135, 9616.302},
    },
}
local BOSS_NAMES = {
    "Awakened Ice Admiral",
    "Beautiful Pirate",
    "Bobby",
    "Cake Prince",
    "Cake Queen",
    "Captain Elephant",
    "Chef",
    "Chief Warden",
    "Cursed Captain",
    "Cyborg",
    "Darkbeard",
    "Diamond",
    "Don Swan",
    "Dough King",
    "Fajita",
    "Fishman Lord",
    "Greybeard",
    "Hydra Leader",
    "Island Empress",
    "Jeremy",
    "Kilo Admiral",
    "Longma",
    "Magma Admiral",
    "Orbitus",
    "Saber Expert",
    "Smoke Admiral",
    "Stone",
    "Swan",
    "The Gorilla King",
    "The Saw",
    "Thunder God",
    "Tide Keeper",
    "Vice Admiral",
    "Warden",
    "Wysper",
    "Yeti",
    "rip_indra True Form",
}

-- Factual farming-area centers from the reviewed reference; live spawn markers take priority.
local FARM_AREAS = {
    ["AmazonQuest2:1"] = {4770.499, 758.955, 1069.868},
    ["AmazonQuest2:2"] = {4530.354, 656.757, -131.61},
    ["AmazonQuest:1"] = {6241.995, 51.522, -1243.977},
    ["AmazonQuest:2"] = {6488.916, 383.384, -110.662},
    ["Area1Quest:1"] = {-737.026, 10.175, 2392.58},
    ["Area1Quest:2"] = {-1022.213, 72.986, 1891.391},
    ["Area2Quest:1"] = {976.468, 111.174, 1229.108},
    ["Area2Quest:2"] = {336.746, 73.162, -224.129},
    ["BanditQuest1:1"] = {1353.449, 3.409, 1376.92},
    ["BuggyQuest1:1"] = {-1169.536, 5.095, 3933.841},
    ["BuggyQuest1:2"] = {-1165.1, 15.153, 4363.515},
    ["CakeQuest1:1"] = {-2286.684, 146.566, -12226.882},
    ["CakeQuest1:2"] = {-1817.975, 209.563, -12288.923},
    ["CakeQuest2:1"] = {-1818.348, 93.413, -12887.66},
    ["CakeQuest2:2"] = {-2288.795, 106.942, -12811.111},
    ["ColosseumQuest:1"] = {-1779.976, 44.608, -2736.355},
    ["ColosseumQuest:2"] = {-1274.759, 58.19, -3188.163},
    ["DeepForestIsland2:1"] = {-11982.222, 376.325, -10451.415},
    ["DeepForestIsland2:2"] = {-13282.305, 496.237, -9565.15},
    ["DeepForestIsland3:1"] = {-10322.4, 390.945, -8580.091},
    ["DeepForestIsland3:2"] = {-11194.542, 442.028, -8608.807},
    ["DeepForestIsland:1"] = {-13225.81, 428.194, -7753.125},
    ["DeepForestIsland:2"] = {-13869.173, 564.953, -7084.414},
    ["DesertQuest:1"] = {932.789, 6.85, 4488.246},
    ["DesertQuest:2"] = {1617.079, 1.554, 4295.549},
    ["FireSideQuest:1"] = {-5466.064, 57.695, -5837.428},
    ["FireSideQuest:2"] = {-5169.717, 34.123, -4669.736},
    ["FishmanQuest:1"] = {60946.609, 48.674, 1525.917},
    ["FishmanQuest:2"] = {60946.609, 48.674, 1525.917},
    ["ForgottenQuest:1"] = {-3115.782, 63.879, -9808.386},
    ["ForgottenQuest:2"] = {-3212.997, 263.809, -10551.88},
    ["FountainQuest:1"] = {5569.805, 38.527, 3849.012},
    ["FountainQuest:2"] = {5782.902, 94.533, 4716.782},
    ["FrostQuest:1"] = {5878.235, 81.389, -6136.356},
    ["FrostQuest:2"] = {5513.369, 60.547, -6809.95},
    ["HauntedQuest1:1"] = {-8817.881, 191.168, 6298.656},
    ["HauntedQuest1:2"] = {-10125.234, 183.947, 6242.014},
    ["HauntedQuest2:1"] = {-9712.031, 204.696, 6193.322},
    ["HauntedQuest2:2"] = {-9545.776, 69.62, 6339.562},
    ["IceCreamIslandQuest:1"] = {-821.614, 208.395, -10990.762},
    ["IceCreamIslandQuest:2"] = {-610.117, 208.269, -11253.687},
    ["IceSideQuest:1"] = {-5769.204, 37.929, -4468.387},
    ["IceSideQuest:2"] = {-6401.28, 15.978, -5948.243},
    ["JungleQuest:1"] = {-1402.746, 98.563, 90.642},
    ["JungleQuest:2"] = {-1267.89, 66.203, -531.818},
    ["MagmaQuest:1"] = {-5363.011, 41.506, 8548.473},
    ["MagmaQuest:2"] = {-5787.99, 120.864, 8762.253},
    ["MarineQuest2:1"] = {-4882.862, 22.652, 4255.535},
    ["MarineQuest3:1"] = {-2842.699, 72.992, -2901.905},
    ["MarineQuest3:2"] = {-1814.703, 72.992, -3208.866},
    ["MarineTreeIsland:1"] = {2490.084, 190.423, -7160.05},
    ["MarineTreeIsland:2"] = {3951.39, 229.115, -6912.816},
    ["NutsIslandQuest:1"] = {-2098.075, 192.612, -10248.887},
    ["NutsIslandQuest:2"] = {-1876.96, 192.611, -10542.294},
    ["PiratePortQuest:1"] = {81.165, 43.756, 5724.702},
    ["PiratePortQuest:2"] = {81.165, 43.756, 5724.702},
    ["ShipQuest1:1"] = {1163.809, 138.288, 33058.426},
    ["ShipQuest1:2"] = {921.302, 125.4, 32937.344},
    ["ShipQuest2:1"] = {917.961, 136.899, 33343.414},
    ["ShipQuest2:2"] = {944.45, 181.401, 33278.945},
    ["SkyExp1Quest:1"] = {-4716.957, 853.09, -1933.925},
    ["SkyExp1Quest:2"] = {-7904.574, 5584.376, -459.63},
    ["SkyExp2Quest:1"] = {-7555.042, 5606.905, -1303.247},
    ["SkyExp2Quest:2"] = {-7837.312, 5649.652, -1791.086},
    ["SkyQuest:1"] = {-4959.514, 365.393, -2974.568},
    ["SkyQuest:2"] = {-5079.981, 376.477, -2194.171},
    ["SnowMountainQuest:1"] = {621.003, 391.361, -5335.436},
    ["SnowMountainQuest:2"] = {1295.627, 429.448, -5087.045},
    ["SnowQuest:1"] = {1412.923, 55.35, -1260.62},
    ["SnowQuest:2"] = {1376.864, 97.278, -1396.931},
    ["ZombieQuest:1"] = {-5649.234, 126.058, -737.774},
    ["ZombieQuest:2"] = {-6030.32, 0.438, -1313.556},
}

-- Coordinate snapshots from reviewed local references; current live markers take priority.
-- Row: display name, fallback XYZ (false = spawned/live only), aliases.
local TELEPORT_LOCATIONS={
    [1]={
        {"Pirate Starter",{889,17,1434},{"WindMill","PirateStarter"}},
        {"Marine Starter",{-2728,25,2056},{"Marine","MarineStarter"}},
        {"Middle Town",{-688,15,1585}},
        {"Jungle",{-1614,37,146}},
        {"Pirate Village",{-1173,45,3837}},
        {"Desert",{922.315,4.684,4202.439}},
        {"Frozen Village",{1298,87,-1344},{"Snow Island","SnowVillage"}},
        {"Marine Fortress",{-4810,21,4359},{"MarineFord"}},
        {"Colosseum",{-1535,7,-3014}},
        {"Lower Skylands",{-4814,718,-2551},{"Sky Island 1","Skylands"}},
        {"Skylands Temple",{-4652,873,-1754},{"Sky Island 2"}},
        {"Upper Skylands",{-7895,5547,-380},{"Sky Island 3","UpperSky"}},
        {"Royal Skylands",{-7033.101,5590.574,1353.107}},
        {"Prison",{4870,6,736}},
        {"Magma Village",{-5290,9,8349}},
        {"Underwater City",{61164,5,1820},{"Under Water Island","FishmanIsland"}},
        {"Underwater Entrance",{3865,5,-1926}},
        {"Fountain City",{5263.488,74.908,4087.616}},
        {"Mob Leader Island",{-2850.2,7.392,5354.993}},
        {"Saber Room",{-1442.166,29.879,-28.355}},
    },
    [2]={
        {"Kingdom of Rose",{-429.544,71.77,1836.182},{"Dressrosa"}},
        {"Cafe",{-382,73,290},{"The Cafe","Café"}},
        {"Docks",{-11,29,2771},{"Frist Spot"}},
        {"Factory",{430.426,210.02,-432.505}},
        {"Colosseum",{-1836.582,44.589,1360.307}},
        {"Swan Mansion",{-317,331,597},{"Flamingo Mansion","Mansion"}},
        {"Don Swan Room",{2285,15,905},{"Flamingo Room"}},
        {"Green Zone",{-2258,73,-2696}},
        {"Graveyard",{-5497.062,47.592,-795.237},{"Zombie Island","Graveyard Island"}},
        {"Snow Mountain",{752,408,-5277},{"Two Snow Mountain"}},
        {"Hot and Cold",{-5897,18,-5096},{"Punk Hazard","IceFireIsland"}},
        {"Hot Side",{-5403.368,28.278,-5371.7},{"Hot Island"}},
        {"Cold Side",{-6231.272,80.934,-4851.321},{"Cold Island"}},
        {"Cursed Ship",{919,125,32869}},
        {"Ice Castle",{5505,40,-6178}},
        {"Forgotten Island",{-3050,240,-10178}},
        {"Usoap Island",{4816,8,2863},{"Ussop Island","Usoapp Island"}},
        {"Dark Arena",{3494,13,-3259},{"Dark Area"}},
        {"Mini Sky Island",{-260.359,49325.703,-35259.301}},
    },
    [3]={
        {"Port Town",{-334,7,5300}},
        {"Hydra Island",{6735.111,126.99,-711.098},{"Hydra"}},
        {"Great Tree",{2485.733,73.346,-6788.625}},
        {"Floating Turtle",{-12528,332,-8658},{"Turtle"}},
        {"Mansion",{-12471,374,-7551}},
        {"Castle on the Sea",{-5073,315,-3153},{"Castle On The Sea","Boat Castle"}},
        {"Haunted Castle",{-9517,142,5528}},
        {"Sea of Treats",{-2105.532,37.25,-10195.509}},
        {"Peanut Island",{-2062,50,-10232},{"Peanut Land"}},
        {"Ice Cream Island",{-902,79,-10988},{"Ice Cream Land"}},
        {"Cake Island",{-2022.299,36.928,-12030.977},{"Cake Land"}},
        {"Chocolate Island",{231.75,23.9,-12200.292},{"Chocolate Land"}},
        {"Candy Cane Island",{-1164.498,59.269,-14492.618},{"Candy Land"}},
        {"Tiki Outpost",{-16224,9,439},{"Tiki"}},
        {"Submerged Island",{10780.64,-2088.414,9260.453},{"Submerged"}},
        {"Friendly Arena",{5228.082,68.15,-1447.437}},
        {"Secret Temple",{5227.455,6.565,1171.449},{"Yama Temple"}},
        {"Tushita Temple",{5237.537,138.898,912.05}},
        {"Temple of Time",{28286,14897,103}},
        {"Dragon Dojo",false,{"Dojo","DragonDojo"}},
        {"Mirage Island",false,{"MysticIsland","MirageIsland"}},
        {"Kitsune Island",false,{"KitsuneIsland"}},
        {"Prehistoric Island",false,{"PrehistoricIsland"}},
        {"Frozen Dimension",false,{"FrozenDimension"}},
        {"Treasure Island",false,{"TreasureIsland"}},
    },
}

local STAT_RULES = {
    {label="Melee",remote="Melee",key="Melee",amount=0},
    {label="Defense",remote="Defense",key="Defense",amount=0},
    {label="Sword",remote="Sword",key="Sword",amount=0},
    {label="Gun",remote="Gun",key="Gun",amount=0},
    {label="Blox Fruit",remote="Demon Fruit",key="DemonFruit",amount=0},
}
for _,rule in ipairs(STAT_RULES)do rule.amount=Core.statAmount(playerGui:GetAttribute("ViltrumStat"..rule.key))end

do
local oldGui = playerGui:FindFirstChild("ViltrumModules")
if oldGui then
    local shutdown = oldGui:FindFirstChild("Shutdown")
    if shutdown and shutdown:IsA("BindableEvent") then shutdown:Fire() end
    oldGui:Destroy()
end
end

local appearance={scale=math.clamp(tonumber(playerGui:GetAttribute("BakaScale"))or 100,60,125),bindings=setmetatable({}, {__mode="k"})}
local colors = {
    background=Color3.fromRGB(18,18,21),sidebar=Color3.fromRGB(24,24,28),panel=Color3.fromRGB(29,29,34),
    card=Color3.fromRGB(25,25,29),input=Color3.fromRGB(36,36,43),selected=Color3.fromRGB(48,48,59),
    track=Color3.fromRGB(42,42,49),accent=Color3.fromRGB(148,150,255),accentText=Color3.fromRGB(148,150,255),
    dim=Color3.fromRGB(111,111,126),border=Color3.fromRGB(46,46,53),text=Color3.fromRGB(232,232,239),
    muted=Color3.fromRGB(157,157,171),dark=Color3.fromRGB(18,18,21),
}
local connections, tags, controls = {}, {}, {}
local state = {farm = false, quests = true, names = false, distance = false, walls = false,stats=false,raid=false,fruits=false,fruitprice=false,speed=false,dodge=playerGui:GetAttribute("ViltrumRaidDodge")~=false}
local disposed, worker, movement, movementDestination, movingRoot = false, nil, nil, nil, nil
local watchedMob, watchedHealth, lastDamageAt, attackCount = nil, nil, 0, 0
local lastAttack, lastQuest = -math.huge, -math.huge
local questRequest, questTimer, questAttempts = nil, nil, 0
local lastQuestReply="none"
local hoverAttachment, hoverAlign, hoverRoot, hoverMob,hoverOffset = nil, nil, nil, nil,nil
local auraRequest, auraTimer, auraRequestedCharacter = nil, nil, nil
local auraStatus, auraSentAt = "pending", 0
local spawnRouteKey, spawnRoutePoints, spawnRouteIndex, spawnArrivedAt = nil, nil, nil, nil
local bossAttempts,lastAbandon=0,-math.huge
local savedCollisions=setmetatable({}, {__mode="k"})
local collisionCharacter,collisionAdded,collisionRemoved=nil,nil,nil
local collisionParts={}
local lastStatusUpdate=-math.huge
local slotCharacter,slotInputInitialized=nil,false
local slotInputBackends={}
local slotLastKey,slotLastEquip,slotWaitUntil=-math.huge,-math.huge,0
local combatProbe=nil
local learnedHeights=setmetatable({}, {__mode="k"})
local nativeClickPoint,mouseHeldBackend,mouseHeldPoint,mouseHeldUntil=nil,nil,nil,0
local statusLabel, activeLabel
local statsStatusLabel,statsPointsLabel,statsWorker,statsJob,statsTimer
local statsLastTick=-math.huge
local statsSchedule={index=0,last={},pending=nil}
local stopRaid
local raidIndex,raidMarker,raidEmptyAt=0,nil,nil
local raidCachedMarkers,raidMarkersAt={},-math.huge
local raidIslandLabel
local raidRunning=false
local menuHideTask,menuShown,menuTransition=nil,true,0
local uiTweens=setmetatable({}, {__mode="k"})
local fruit={lastCast=-math.huge,index=0}
local slotMode=nil
local dodge={}
local raidCombat={}
local teleport={dirty=true,sea=nil,live={},rowConnections={}}
local fruitEsp={entries={},running=false}
local fruitPrice={}
local speedHack={}

local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(connections, c)
    return c
end
do
    function speedHack.restore()
        if speedHack.human and speedHack.human.Parent then
            if speedHack.human.WalkSpeed==speedHack.applied then speedHack.human.WalkSpeed=speedHack.original end
        end
        speedHack.human=nil;speedHack.original=nil;speedHack.applied=nil
    end
    function speedHack.tick()
        local character=localPlayer.Character
        local human=character and character:FindFirstChildOfClass("Humanoid")
        if not state.speed or disposed or state.farm or state.raid or teleport.flight or not human or human.Health<=0 then
            speedHack.restore();return
        end
        if speedHack.human~=human then
            speedHack.restore();speedHack.human=human;speedHack.original=human.WalkSpeed
        end
        if human.WalkSpeed~=CONFIG.WalkSpeed then human.WalkSpeed=CONFIG.WalkSpeed end
        speedHack.applied=CONFIG.WalkSpeed
    end
end
local function releaseNativeClick()
    if fruit.release then fruit.release()end
    if not mouseHeldBackend then return true end
    local ok=pcall(mouseHeldBackend.mouse,false,mouseHeldPoint)
    if not ok then ok=pcall(mouseHeldBackend.mouse,false,mouseHeldPoint)end
    if ok then mouseHeldBackend,mouseHeldPoint=nil,nil end
    return ok
end
function fruit.release()
    if not fruit.held then return true end
    local held=fruit.held
    local ok=pcall(held.backend.send,false,held.key)
    if not ok then ok=pcall(held.backend.send,false,held.key)end
    if ok then fruit.held=nil end
    return ok
end
function fruit.mode(target)
    if CONFIG.WeaponType~="Fruit"then fruit.target=nil;return CONFIG.WeaponType end
    if fruit.target and (not target or fruit.target~=target.model or target.health<=0)then fruit.release();fruit.target=nil end
    if Core.fruitReady(target,CONFIG.FruitPercent,CONFIG.FruitSkills)then fruit.target=target.model end
    return fruit.target and "Fruit" or "Melee"
end
function fruit.skillsSelected()
    for _,key in ipairs({"Z","X","C","V"})do if CONFIG.FruitSkills[key]then return true end end
    return false
end
local function create(class, properties, parent)
    local object = Instance.new(class)
    for key, value in pairs(properties) do object[key] = value end
    object.Parent = parent
    local roles={}
    for property,value in pairs(properties)do
        if property=="BackgroundColor3" or property=="TextColor3" or property=="PlaceholderColor3" or property=="Color" then
            for role,color in pairs(colors)do if value==color then roles[property]=role;break end end
        end
    end
    appearance.bindings[object]=roles
    return object
end
local function round(parent, radius)
    create("UICorner", {CornerRadius = UDim.new(0, radius)}, parent)
end
local function text(parent, value, position, size, fontSize, color)
    return create("TextLabel", {
        BackgroundTransparency = 1, Text = value, Position = position, Size = size,
        Font = Enum.Font.Gotham, TextSize = fontSize,
        TextColor3 = color or colors.text, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, parent)
end
local function animate(object, properties)
    if uiTweens[object]then uiTweens[object]:Cancel()end
    local tween=TweenService:Create(object, TweenInfo.new(.16, Enum.EasingStyle.Quad,Enum.EasingDirection.Out), properties)
    uiTweens[object]=tween;tween:Play()
end
local function status(message)
    if statusLabel and not disposed then
        local now=os.clock()
        if (state.farm or state.raid) and now-lastStatusUpdate<.25 then return end
        local value=message..((state.farm or state.raid) and (" · Aura: "..auraStatus) or "")
        if statusLabel.Text~=value then statusLabel.Text=value end
        lastStatusUpdate=now
    end
end
local function stopMovement()
    if movement then movement:Cancel() end
    movement, movementDestination, movingRoot = nil, nil, nil
end
local function stopHover()
    if hoverAlign then hoverAlign:Destroy() end
    if hoverAttachment then hoverAttachment:Destroy() end
    hoverAttachment, hoverAlign, hoverRoot, hoverMob,hoverOffset=nil, nil, nil, nil,nil
end
local function restoreCollisions()
    if collisionAdded then collisionAdded:Disconnect();collisionAdded=nil end
    if collisionRemoved then collisionRemoved:Disconnect();collisionRemoved=nil end
    for part,value in pairs(savedCollisions)do pcall(function()part.CanCollide=value end)end
    table.clear(savedCollisions)
    table.clear(collisionParts);collisionCharacter=nil
end
local function disableCollisions(character)
    if collisionCharacter~=character then
        restoreCollisions();collisionCharacter=character
        local function added(part)
            if part:IsA("BasePart")then
                collisionParts[part]=true
                if savedCollisions[part]==nil then savedCollisions[part]=part.CanCollide end
            end
        end
        for _,part in ipairs(character:GetDescendants())do added(part)end
        collisionAdded=character.DescendantAdded:Connect(added)
        collisionRemoved=character.DescendantRemoving:Connect(function(part)
            collisionParts[part]=nil
            if savedCollisions[part]~=nil then
                pcall(function()part.CanCollide=savedCollisions[part]end)
                savedCollisions[part]=nil
            end
        end)
    end
    for part in pairs(collisionParts)do if part.CanCollide then part.CanCollide=false end end
end
function raidCombat.body(model)
    for _,name in ipairs({"HumanoidRootPart","UpperTorso","Torso","Head"})do
        local part=model:FindFirstChild(name)
        if part and part:IsA("BasePart") and part.Parent==model then return part end
    end
end
function raidCombat.hitPart(model)
    for _,name in ipairs({"Head","UpperTorso","Torso","HumanoidRootPart"})do
        local part=model:FindFirstChild(name)
        if part and part:IsA("BasePart") and part.Parent==model then return part end
    end
end
local function holdPosition(root, position, mob, speed)
    if hoverRoot~=root then
        stopHover()
        hoverAttachment=create("Attachment", {Name="ViltrumHoverAttachment"}, root)
        hoverAlign=create("AlignPosition", {Name="ViltrumHover", Attachment0=hoverAttachment,
            Mode=Enum.PositionAlignmentMode.OneAttachment, ApplyAtCenterOfMass=true,
            ReactionForceEnabled=false, MaxForce=100000,
            MaxVelocity=CONFIG.TravelSpeed, Responsiveness=80, RigidityEnabled=false}, root)
        hoverRoot=root
    end
    local velocity=speed or CONFIG.TravelSpeed
    if hoverAlign.MaxVelocity~=velocity then hoverAlign.MaxVelocity=velocity end
    if (hoverAlign.Position-position).Magnitude>.05 then hoverAlign.Position=position end
    hoverMob=mob
    local mobRoot=mob and raidCombat.body(mob)
    hoverOffset=mobRoot and position-mobRoot.Position or nil
end
local function deactivateWeapon()
    local character = localPlayer.Character
    local tool = character and character:FindFirstChildOfClass("Tool")
    if tool then pcall(function() tool:Deactivate() end) end
end
local function cancelQuestRequest()
    if questTimer then task.cancel(questTimer); questTimer=nil end
    if questRequest then task.cancel(questRequest); questRequest=nil end
end
local function cancelAuraRequest()
    if auraTimer then task.cancel(auraTimer); auraTimer=nil end
    if auraRequest then task.cancel(auraRequest); auraRequest=nil end
end
local function hasAura(character)
    return character:FindFirstChild("HasBuso")~=nil or character:GetAttribute("HasBuso")==true
end
local function ensureAura(character)
    if not CONFIG.AutoAura then
        auraStatus=hasAura(character) and "on · auto off" or "auto off"
        return
    end
    if hasAura(character) then auraStatus="on"; return end
    if auraRequestedCharacter==character then
        if not auraRequest and auraStatus=="requested" and os.clock()-auraSentAt>8 then auraStatus="unconfirmed" end
        return
    end
    auraRequestedCharacter=character
    local remotes=ReplicatedStorage:FindFirstChild("Remotes")
    local remote=remotes and remotes:FindFirstChild("CommF_")
    if not remote or not remote:IsA("RemoteFunction") then auraStatus="remote unavailable";return end
    auraStatus="requested";auraSentAt=os.clock()
    local requestThread
    requestThread=task.defer(function()
        if disposed or not (state.farm or state.raid) or not CONFIG.AutoAura or localPlayer.Character~=character or hasAura(character) then
            if auraRequest==requestThread then
                auraRequest=nil
                if auraTimer then task.cancel(auraTimer);auraTimer=nil end
            end
            return
        end
        local ok=pcall(function()remote:InvokeServer("Buso")end)
        if auraRequest==requestThread then
            auraRequest=nil
            if auraTimer then task.cancel(auraTimer);auraTimer=nil end
            auraStatus=ok and (hasAura(character) and "on" or "requested") or "request failed"
        end
    end)
    auraRequest=requestThread
    auraTimer=task.delay(8,function()
        auraTimer=nil
        if auraRequest==requestThread then
            task.cancel(auraRequest);auraRequest=nil;auraStatus="request timed out"
        end
    end)
end
do
    -- Require a skill-specific cue; Action priority alone also describes ordinary hits.
    -- Skills with no replicated animation/casting signal remain unobservable.
    local watched,threats,owner={},{},nil
    local active,refreshAt,lastThreatAt,side=nil,-math.huge,-math.huge,1
    local function nearby(part,root)
        local delta=part.Position-root.Position
        return Vector3.new(delta.X,0,delta.Z).Magnitude<=CONFIG.DodgeRadius
    end
    local function disconnect(entry)
        if entry.connection then entry.connection:Disconnect()end
        for _,connection in ipairs(entry.casts)do connection:Disconnect()end
    end
    function dodge.reset()
        for _,entry in pairs(watched)do disconnect(entry)end
        table.clear(watched);table.clear(threats)
        owner=nil;active=nil;refreshAt=-math.huge;lastThreatAt=-math.huge;side=1
    end
    local function offensive(track,model,report)
        if not track or track.IsPlaying==false then return false end
        local animation=track.Animation
        if not animation then return false end
        local info={name=animation.Name,playing=track.IsPlaying,isSkill=animation:GetAttribute("IsSkill"),
            key=animation:GetAttribute("SkillKey"),kind=animation:GetAttribute("AttackType")}
        local attack=Core.npcSkillCue(info)
        if not attack and info.isSkill~=false and type(track.Name)=="string"then
            info.name=track.Name;attack=Core.npcSkillCue(info)
        end
        if report then
            local id=tostring(animation.AnimationId or ""):match("%d+")
            playerGui:SetAttribute("ViltrumLastNpcAnimationId",id)
            playerGui:SetAttribute("ViltrumLastNpcAnimationName",animation.Name)
            playerGui:SetAttribute("ViltrumLastNpcAnimationIsAttackCue",attack)
        end
        if report and dodge.cueLabel and attack then dodge.cueLabel.Text="Skill cue: named / tagged clip"end
        return attack
    end
    local function escape(root,caster,track,reason,entry,kind)
        local character=localPlayer.Character
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        if disposed or not state.raid or not raidRunning or not state.dodge or not humanoid or humanoid.Health<=0
            or root.Parent~=character or not caster.Parent or not nearby(caster,root)
            or (raidCombat.timer and not raidCombat.timer())then return end
        threats[track]={model=caster.Parent,track=track,reason=reason,entry=entry,kind=kind}
        lastThreatAt=os.clock()
        local started=not active
        if started then
            local forward=caster.CFrame and caster.CFrame.LookVector or Vector3.new(0,0,-1)
            forward=Vector3.new(forward.X,0,forward.Z)
            if forward.Magnitude<.01 then forward=Vector3.new(0,0,-1)end
            active={root=root,anchor=hoverMob or caster.Parent,
                offset=Vector3.new(-forward.Z,0,forward.X).Unit*side*CONFIG.DodgeSide,
                direction=side==1 and "right"or"left"}
            side=-side
        end
        local body=raidCombat.body(active.anchor)or caster
        local position=body.Position+Vector3.new(0,CONFIG.RaidHeight,0)+active.offset
        releaseNativeClick();deactivateWeapon()
        if started then root.CFrame=CFrame.new(position)*root.CFrame.Rotation end
        holdPosition(root,position,nil,CONFIG.DodgeSpeed)
    end
    function dodge.step(humanoid,root,list,now)
        if not state.dodge then dodge.reset();return false end
        if owner~=humanoid then dodge.reset();owner=humanoid end
        if now-refreshAt>=.1 then
            refreshAt=now
            local players={}
            for _,player in ipairs(Players:GetPlayers())do if player.Character then players[player.Character]=true end end
            local keep={}
            for _,candidate in ipairs(list)do
                local model=candidate.model
                if not players[model] and candidate.health>0 and nearby(candidate.part,root)then
                    keep[model]=true
                    local animator=candidate.humanoid:FindFirstChildOfClass("Animator")
                    local entry=watched[model]
                    if not entry or entry.animator~=animator or entry.part~=candidate.part then
                        if entry then disconnect(entry)end
                        entry={animator=animator,part=candidate.part,casts={}};watched[model]=entry
                        local function valid()
                            return watched[model]==entry and model.Parent==workspace:FindFirstChild("Enemies")and candidate.humanoid.Health>0
                        end
                        local function casting()
                            return model:GetAttribute("UsingSkill")==true
                        end
                        local castTrack=setmetatable({}, {__index=function(_,key)if key=="IsPlaying"then return casting()end end})
                        local function castChanged()
                            if valid()and casting()then escape(root,candidate.part,castTrack,"NPC casting state",entry,"state")end
                        end
                        for _,name in ipairs({"UsingSkill"})do table.insert(entry.casts,model:GetAttributeChangedSignal(name):Connect(castChanged))end
                        castChanged()
                        if animator then
                            local function played(track)
                                if valid()and offensive(track,model,true)then escape(root,candidate.part,track,"NPC skill animation",entry,"animation")end
                            end
                            entry.connection=animator.AnimationPlayed:Connect(played)
                            local ok,tracks=pcall(function()return animator:GetPlayingAnimationTracks()end)
                            if ok then for _,track in ipairs(tracks)do played(track)end end
                        end
                    end
                end
            end
            for model,entry in pairs(watched)do if not keep[model]then disconnect(entry);watched[model]=nil end end
        end
        local danger=false
        for track,threat in pairs(threats)do
            local model=threat.model
            local human=model.Parent and model:FindFirstChildOfClass("Humanoid")
            local part=human and raidCombat.body(model)
            if watched[model]~=threat.entry or not human or human.Health<=0 or not part or not nearby(part,root)or track.IsPlaying==false
                or (threat.kind=="animation" and not offensive(track,model,false))then threats[track]=nil
            else danger=true end
        end
        if danger then lastThreatAt=now end
        if active then
            if active.root~=root or (not danger and now-lastThreatAt>=CONFIG.DodgeGrace)then active=nil
            else
                local anchor=raidCombat.body(active.anchor)
                if not anchor then active=nil
                else
                    releaseNativeClick()
                    if dodge.cueLabel then
                        local value=danger and "Active NPC skill · dodging "..active.direction or "Skill ended · returning"
                        if dodge.cueLabel.Text~=value then dodge.cueLabel.Text=value end
                    end
                    holdPosition(root,anchor.Position+Vector3.new(0,CONFIG.RaidHeight,0)+active.offset,nil,CONFIG.DodgeSpeed)
                    return true,active.direction.." 60 studs · NPC skill active"
                end
            end
        end
        if not danger and dodge.cueLabel then
            local name=playerGui:GetAttribute("ViltrumLastNpcAnimationName")
            local id=playerGui:GetAttribute("ViltrumLastNpcAnimationId")
            local value="No active NPC skill"..(name and " · Last clip: "..name.." · ID "..tostring(id or "missing")or "")
            if dodge.cueLabel.Text~=value then dodge.cueLabel.Text=value end
        end
        return false
    end
end

local function stopFarm(message)
    fruit.target=nil
    state.farm = false
    releaseNativeClick()
    stopMovement()
    stopHover()
    deactivateWeapon()
    cancelQuestRequest()
    cancelAuraRequest()
    restoreCollisions()
    watchedMob, watchedHealth, attackCount = nil, nil, 0
    combatProbe=nil
    spawnRouteKey, spawnRoutePoints, spawnRouteIndex, spawnArrivedAt=nil,nil,nil,nil
    if controls.farm and not disposed then controls.farm(false) end
    if message then status(message) end
end
local function statsStatus(message)
    if statsStatusLabel and not disposed and statsStatusLabel.Text~=message then statsStatusLabel.Text=message end
end
stopRaid=function(message)
    fruit.target=nil
    state.raid=false;raidRunning=false
    dodge.reset()
    releaseNativeClick();stopMovement();stopHover();deactivateWeapon();cancelAuraRequest();restoreCollisions()
    raidIndex,raidMarker,raidEmptyAt=0,nil,nil;raidCachedMarkers={};raidMarkersAt=-math.huge;combatProbe=nil
    if controls.raid and not disposed then controls.raid(false)end
    if message then status(message)end
end
local function stopStats(message)
    state.stats=false
    if statsTimer then task.cancel(statsTimer);statsTimer=nil end
    if statsJob then task.cancel(statsJob);statsJob=nil end
    statsSchedule.pending=nil
    if controls.stats and not disposed then controls.stats(false)end
    if message then statsStatus(message)end
end

-- Location discovery runs only when this page opens, or its map data changes.
do
    local function key(name)return tostring(name):lower():gsub("[^%w]","")end
    local function finite(position)
        if not position then return false end
        for _,axis in ipairs({"X","Y","Z"})do
            local value=position[axis]
            if type(value)~="number" or value~=value or math.abs(value)>1000000 then return false end
        end
        return true
    end
    local function point(object)
        if not object or not object:IsDescendantOf(workspace)then return nil end
        if object:IsA("BasePart")then return finite(object.Position)and object.Position or nil end
        if object:IsA("Model")then
            local part=object.PrimaryPart or object:FindFirstChild("Entrance",true) or object:FindFirstChild("Spawn",true)
            if part and part:IsA("BasePart")and finite(part.Position)then return part.Position end
            if object:FindFirstChildWhichIsA("BasePart",true)then
                local ok,pivot=pcall(function()return object:GetPivot()end)
                if ok and finite(pivot.Position)then return pivot.Position end
            end
        end
        return nil
    end
    local ownership={}
    for sea,rows in pairs(TELEPORT_LOCATIONS)do
        for _,row in ipairs(rows)do
            local names={row[1]};for _,alias in ipairs(row[3]or{})do table.insert(names,alias)end
            for _,name in ipairs(names)do
                local normalized=key(name);ownership[normalized]=ownership[normalized]or{};ownership[normalized][sea]=true
            end
        end
    end
    function teleport.collect()
        local sea=Core.SEA_BY_PLACE[game.PlaceId]
        teleport.sea=sea;teleport.dirty=false;teleport.live={}
        if not sea or game.GameId~=994732206 then return {}end
        local origin=workspace:FindFirstChild("_WorldOrigin")
        local locations=origin and origin:FindFirstChild("Locations")
        local map=workspace:FindFirstChild("Map")
        local function add(object,onlyEvents)
            local normalized=key(object.Name)
            local owners=ownership[normalized]
            local declared=object:GetAttribute("Sea")
            if declared~=nil and tonumber(declared)~=sea then return end
            if owners and not owners[sea]then return end
            if normalized:match("^island%d+$")then return end
            if onlyEvents then
                local event=false
                for _,row in ipairs(TELEPORT_LOCATIONS[sea])do
                    if not row[2]then
                        if key(row[1])==normalized then event=true end
                        for _,alias in ipairs(row[3]or{})do if key(alias)==normalized then event=true end end
                    end
                end
                if not event then return end
            end
            if point(object)then teleport.live[normalized]=object end
        end
        if locations then for _,object in ipairs(locations:GetChildren())do add(object,false)end end
        if map then for _,object in ipairs(map:GetChildren())do
            if not teleport.live[key(object.Name)]then add(object,true)end
        end end
        local rows,used={},{}
        for _,source in ipairs(TELEPORT_LOCATIONS[sea])do
            local names={source[1]};for _,alias in ipairs(source[3]or{})do table.insert(names,alias)end
            local marker
            for _,name in ipairs(names)do
                local normalized=key(name);used[normalized]=true
                marker=marker or teleport.live[normalized]
            end
            if source[2]or marker then
                table.insert(rows,{name=source[1],fallback=source[2],marker=marker,sea=sea})
            end
        end
        local extra={}
        for normalized,marker in pairs(teleport.live)do
            if not used[normalized]then table.insert(extra,{name=marker.Name,marker=marker,sea=sea})end
        end
        table.sort(extra,function(a,b)return a.name<b.name end)
        for _,row in ipairs(extra)do table.insert(rows,row)end
        return rows
    end
    function teleport.cancel(message)
        if not teleport.flight then return end
        teleport.flight=nil
        stopMovement();stopHover();restoreCollisions()
        if teleport.updateFlightUI then teleport.updateFlightUI()end
        if message then status(message)end
    end
    local function destination(row)
        local marker=row.marker
        local declared=marker and marker:GetAttribute("Sea")
        local position=(declared==nil or tonumber(declared)==row.sea)and point(marker)or nil
        if not position and row.fallback then position=Vector3.new(row.fallback[1],row.fallback[2],row.fallback[3])end
        return finite(position)and position+Vector3.new(0,4,0)or nil
    end
    function teleport.begin(row)
        if disposed then return end
        if game.GameId~=994732206 or Core.SEA_BY_PLACE[game.PlaceId]~=row.sea then
            teleport.dirty=true;status("Location belongs to a different sea. Refresh Teleports.");return
        end
        local character=localPlayer.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local human=character and character:FindFirstChildOfClass("Humanoid")
        if not root or not root:IsA("BasePart")or not human or human.Health<=0 then status("Teleport: wait for your character to spawn.");return end
        local current
        for _,candidate in ipairs(teleport.collect())do if candidate.name==row.name then current=candidate;break end end
        teleport.dirty=true
        if not current then status("Location is no longer available. Refresh Teleports.");return end
        row=current
        local position=destination(row)
        if not position then teleport.dirty=true;status("Location is no longer available. Refresh Teleports.");return end
        teleport.cancel()
        stopFarm();stopRaid()
        human.Sit=false
        root.AssemblyLinearVelocity=Vector3.new(0,0,0);root.AssemblyAngularVelocity=Vector3.new(0,0,0)
        teleport.flight={row=row,character=character,root=root,human=human,statusAt=-math.huge}
        disableCollisions(character)
        holdPosition(root,position,nil,CONFIG.TravelSpeed)
        if teleport.updateFlightUI then teleport.updateFlightUI()end
        status("Flying: "..row.name.." · "..CONFIG.TravelSpeed.." studs/s · Farm / Raid stopped.")
    end
    function teleport.tick()
        local flight=teleport.flight
        if not flight then return end
        if game.GameId~=994732206 or Core.SEA_BY_PLACE[game.PlaceId]~=flight.row.sea then
            teleport.cancel("Flight stopped: world changed.");return
        end
        if localPlayer.Character~=flight.character or flight.human.Health<=0
            or flight.human.Parent~=flight.character or flight.root.Parent~=flight.character then
            teleport.cancel("Flight stopped: character unavailable.");return
        end
        local target=destination(flight.row)
        if not target then teleport.cancel("Flight stopped: location disappeared.");return end
        local distance=(flight.root.Position-target).Magnitude
        if distance<=CONFIG.PositionTolerance then
            flight.root.AssemblyLinearVelocity=Vector3.new(0,0,0)
            flight.root.AssemblyAngularVelocity=Vector3.new(0,0,0)
            teleport.cancel("Arrived: "..flight.row.name);return
        end
        holdPosition(flight.root,target,nil,CONFIG.TravelSpeed)
        if os.clock()-flight.statusAt>=.25 then
            flight.statusAt=os.clock();status("Flying: "..flight.row.name.." · "..math.ceil(distance).." studs left")
        end
    end
    local function changed(object)
        local origin=workspace:FindFirstChild("_WorldOrigin")
        local locations=origin and origin:FindFirstChild("Locations")
        local map=workspace:FindFirstChild("Map")
        if object.Name=="_WorldOrigin" or object.Name=="Locations" or object.Name=="Map"
            or locations and (object.Parent==locations or object:IsDescendantOf(locations))
            or map and (object.Parent==map or object:IsDescendantOf(map))then teleport.dirty=true end
    end
    connect(workspace.DescendantAdded,changed);connect(workspace.DescendantRemoving,changed)
end

-- Keep UI construction locals out of the worker/cleanup register scope.
local gui,shutdown,window,close,cameraConnection
do
local function constructBakaUI()
gui = create("ScreenGui", {Name="ViltrumModules", ResetOnSpawn=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling, DisplayOrder=20}, playerGui)
shutdown = create("BindableEvent", {Name="Shutdown"}, gui)
window = create("Frame", {Name="Window", AnchorPoint=Vector2.new(.5,.5),
    Position=UDim2.fromScale(.5,.5), Size=UDim2.fromOffset(WINDOW_WIDTH,WINDOW_HEIGHT),
    BackgroundColor3=colors.background, BorderSizePixel=0}, gui)
round(window,26)
window.ClipsDescendants=true
create("UIStroke",{Color=colors.border,Transparency=.25,Thickness=1},window)
local uiScale=create("UIScale",{Scale=1},window)
local ui
local function resize()
    local camera=workspace.CurrentCamera
    if camera then uiScale.Scale=math.min(appearance.scale/100,(camera.ViewportSize.X-24)/WINDOW_WIDTH,(camera.ViewportSize.Y-90)/WINDOW_HEIGHT) end
end
local function bindCamera()
    if cameraConnection then cameraConnection:Disconnect() end
    if workspace.CurrentCamera then cameraConnection=workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end
    resize()
end
connect(workspace:GetPropertyChangedSignal("CurrentCamera"),bindCamera);bindCamera()

local header=create("Frame",{Name="DragHeader",Active=true,BackgroundTransparency=1,
    Size=UDim2.new(1,-220,0,80),Position=UDim2.fromOffset(0,0)},window)
local contentX=292
local pageY=80
local sidebar=create("Frame",{Name="Sidebar",BackgroundColor3=colors.sidebar,BorderSizePixel=0,
    Position=UDim2.fromOffset(12,62),Size=UDim2.fromOffset(264,WINDOW_HEIGHT-76)},window)
round(sidebar,22)
local topbar=create("Frame",{Name="Topbar",BackgroundTransparency=1,Position=UDim2.fromOffset(0,0),
    Size=UDim2.new(1,0,0,64)},window)
local navigationBar=create("Frame",{Name="Navigation",BackgroundTransparency=1,
    Position=UDim2.fromOffset(20,148),Size=UDim2.fromOffset(248,430)},window)
text(sidebar,"BA",UDim2.fromOffset(24,6),UDim2.fromOffset(90,68),38,colors.text).Font=Enum.Font.GothamBold
text(sidebar,"KA",UDim2.fromOffset(78,6),UDim2.fromOffset(115,68),38,colors.accent).Font=Enum.Font.GothamBold
text(navigationBar,"VISUALS",UDim2.fromOffset(18,248),UDim2.fromOffset(160,22),9,colors.dim)
text(navigationBar,"CLIENT",UDim2.fromOffset(18,344),UDim2.fromOffset(160,22),9,colors.dim)
local function topButton(name,label,x,width)
    local b=create("TextButton",{Name=name,Text=label,Font=Enum.Font.Gotham,TextSize=12,
        TextColor3=colors.muted,BackgroundColor3=colors.input,BackgroundTransparency=.45,BorderSizePixel=0,
        AutoButtonColor=false,Position=UDim2.fromOffset(x,18),Size=UDim2.fromOffset(width,34)},topbar)
    round(b,8);create("UIStroke",{Color=colors.border,Transparency=.6,Thickness=1},b);return b
end
local save=topButton("SaveSettings","Save",WINDOW_WIDTH-212,48)
local minimize=topButton("Minimize","−",WINDOW_WIDTH-108,26)
close=topButton("Close","×",WINDOW_WIDTH-74,26)
local appButton=topButton("OpenAppSettings","⚙",WINDOW_WIDTH-154,34)
for _,b in ipairs({save,minimize,close,appButton})do b.BackgroundTransparency=1 end
local previous=topButton("PreviousPage","‹",contentX,32)
local nextPage=topButton("NextPage","›",contentX+32,32)
previous.BackgroundColor3=colors.card;nextPage.BackgroundColor3=colors.card
previous.TextSize=22;nextPage.TextSize=22
local profile=text(window,"Auto Farm",UDim2.fromOffset(contentX+82,19),UDim2.fromOffset(230,32),16,colors.text)
local search=topButton("Search","⌕",24,30);search.BackgroundColor3=colors.card;search.TextSize=22
local searchBox=create("TextBox",{Name="ModuleSearch",Text="",PlaceholderText="Search function ...",ClearTextOnFocus=false,
    TextColor3=colors.text,PlaceholderColor3=colors.dim,Font=Enum.Font.Gotham,TextSize=12,
    BorderSizePixel=0,BackgroundColor3=colors.card,Position=UDim2.fromOffset(57,18),Size=UDim2.fromOffset(211,34),Visible=true},window)
round(searchBox,12)
local avatar=create("Frame",{BackgroundColor3=colors.selected,BorderSizePixel=0,Position=UDim2.fromOffset(34,WINDOW_HEIGHT-54),Size=UDim2.fromOffset(28,28)},window)
round(avatar,14);text(avatar,"B",UDim2.fromOffset(8,0),UDim2.fromOffset(18,28),12,colors.accent)
text(window,"Baka",UDim2.fromOffset(72,WINDOW_HEIGHT-56),UDim2.fromOffset(170,22),12,colors.text)
text(window,"Client session",UDim2.fromOffset(72,WINDOW_HEIGHT-34),UDim2.fromOffset(170,14),9,colors.dim)
local restore=create("TextButton",{Name="Restore",Text="",AutoButtonColor=false,
    BackgroundColor3=colors.background,BorderSizePixel=0,
    Size=UDim2.fromOffset(40,40),Position=UDim2.new(0,18,.5,-20),Visible=false},gui)
round(restore,10)
create("UIStroke",{Color=colors.border,Thickness=1,Transparency=.15},restore)
for y=14,26,6 do
    create("Frame",{BackgroundColor3=colors.accent,BorderSizePixel=0,
        Position=UDim2.fromOffset(13,y),Size=UDim2.fromOffset(14,1)},restore)
end
local restoreDragInput,restoreDragStart,restoreStart,restoreDragged=nil,nil,nil,false
local restoreSuppressUntil=0
local function setMenuVisible(visible)
    if not visible and ui then ui.close()end
    menuShown=visible;menuTransition+=1
    local transition=menuTransition
    if menuHideTask then task.cancel(menuHideTask);menuHideTask=nil end
    local camera=workspace.CurrentCamera
    local baseScale=camera and math.min(appearance.scale/100,(camera.ViewportSize.X-24)/WINDOW_WIDTH,(camera.ViewportSize.Y-90)/WINDOW_HEIGHT)or appearance.scale/100
    if visible then
        window.Visible=true;restore.Visible=false
        uiScale.Scale=baseScale*.97;window.BackgroundTransparency=.15
        animate(uiScale,{Scale=baseScale});animate(window,{BackgroundTransparency=0})
    else
        animate(uiScale,{Scale=baseScale*.97});animate(window,{BackgroundTransparency=.15})
        menuHideTask=task.delay(.16,function()
            if disposed or transition~=menuTransition or menuShown then return end
            menuHideTask=nil;window.Visible=false;restore.Visible=true
        end)
    end
end
connect(minimize.Activated,function()setMenuVisible(false)end)
connect(restore.Activated,function()
    if os.clock()<restoreSuppressUntil then return end
    setMenuVisible(true)
end)
connect(restore.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        restoreDragInput,restoreDragStart,restoreStart=input,input.Position,restore.AbsolutePosition
        restoreDragged=false;restoreSuppressUntil=0
    end
end)
connect(UserInputService.InputChanged,function(input)
    if not restoreDragInput then return end
    if input.UserInputType==Enum.UserInputType.MouseMovement or input==restoreDragInput then
        local delta=input.Position-restoreDragStart
        if delta.Magnitude>6 then restoreDragged=true end
        if restoreDragged and workspace.CurrentCamera then
            local viewport=workspace.CurrentCamera.ViewportSize
            restore.Position=UDim2.fromOffset(math.clamp(restoreStart.X+delta.X,8,math.max(8,viewport.X-48)),
                math.clamp(restoreStart.Y+delta.Y,8,math.max(8,viewport.Y-48)))
            restoreSuppressUntil=os.clock()+.25
        end
    end
end)
connect(UserInputService.InputEnded,function(input)
    if input==restoreDragInput then
        if restoreDragged then restoreSuppressUntil=os.clock()+.25 end
        restoreDragInput=nil
    end
end)
connect(UserInputService.InputBegan,function(input,processed)
    if not processed and input.KeyCode==Enum.KeyCode.RightShift then setMenuVisible(not menuShown)end
end)
local dragInput,dragStart,windowStart
connect(header.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragInput,dragStart,windowStart=input,input.Position,window.Position
    end
end)
connect(UserInputService.InputChanged,function(input)
    if not dragInput then return end
    if input.UserInputType==Enum.UserInputType.MouseMovement or input==dragInput then
        local delta=input.Position-dragStart
        local camera=workspace.CurrentCamera
        if camera then
            local viewport,scaled=camera.ViewportSize,window.AbsoluteSize
            window.Position=UDim2.fromOffset(
                math.clamp(viewport.X*windowStart.X.Scale+windowStart.X.Offset+delta.X,scaled.X/2,viewport.X-scaled.X/2),
                math.clamp(viewport.Y*windowStart.Y.Scale+windowStart.Y.Offset+delta.Y,scaled.Y/2,viewport.Y-scaled.Y/2))
        end
    end
end)
connect(UserInputService.InputEnded,function(input)if input==dragInput then dragInput=nil end end)

local pages,tabButtons,columns,cards={},{},{},{}
local currentPage="farm"
for _,name in ipairs({"farm","raid","stats","teleports","players","settings"}) do
    pages[name]=create("CanvasGroup",{Name="Page_"..name,BackgroundTransparency=1,Visible=name=="farm",GroupTransparency=0,
        Position=UDim2.fromOffset(contentX,pageY),Size=UDim2.fromOffset(752,WINDOW_HEIGHT-148)},window)
    columns[pages[name]]={}
    for index=1,2 do
        local column=create("ScrollingFrame",{Name="Column"..index,BackgroundTransparency=1,BorderSizePixel=0,
            Position=UDim2.fromOffset((index-1)*384,0),Size=UDim2.fromOffset(368,WINDOW_HEIGHT-148),
            CanvasSize=UDim2.fromOffset(0,0),ScrollBarThickness=3,ScrollBarImageColor3=colors.border,ClipsDescendants=true},pages[name])
        columns[pages[name]][index]=column;cards[column]={}
    end
end
local function selectPage(name)
    if ui then ui.close()end
    currentPage=name
    for id,p in pairs(pages)do p.Visible=id==name end
    local titles={farm="Auto Farm",raid="Auto Raid",stats="Auto Stats",teleports="Teleports",players="Players",settings="Settings"}
    profile.Text=titles[name]
    if name=="teleports" and teleport.refreshUI then teleport.refreshUI()end
    pages[name].GroupTransparency=1;pages[name].Position=UDim2.fromOffset(contentX,pageY+4)
    animate(pages[name],{GroupTransparency=0,Position=UDim2.fromOffset(contentX,pageY)})
    for id,b in pairs(tabButtons)do
        animate(b,{BackgroundTransparency=id==name and 0 or 1})
        b:FindFirstChild("Indicator").Visible=id==name
        b:FindFirstChild("Caption").TextColor3=id==name and colors.text or colors.muted
        for _,part in ipairs(b:FindFirstChild("Icon"):GetDescendants())do
            if part:IsA("Frame")then animate(part,{BackgroundColor3=id==name and colors.accentText or colors.muted})end
            if part:IsA("UIStroke")then part.Color=id==name and colors.accentText or colors.muted end
        end
    end
end
local function icon(parent,name,x,y,color)
    local group=create("Frame",{Name="Icon",BackgroundTransparency=1,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(20,20)},parent)
    local function line(px,py,w,h,rotation)
        local f=create("Frame",{BackgroundColor3=color,BorderSizePixel=0,Rotation=rotation or 0,
            Position=UDim2.fromOffset(px,py),Size=UDim2.fromOffset(w,h)},group)
        round(f,1);return f
    end
    if name=="farm"then
        for _,size in ipairs({17,8})do
            local f=line((20-size)/2,(20-size)/2,size,size);f.BackgroundTransparency=1;round(f,size/2)
            create("UIStroke",{Color=color,Thickness=1.3},f)
        end
    elseif name=="raid"then
        line(6,4,2,9,30);line(11,10,2,9,30);line(5,9,7,1.5);line(9,5,7,1.5);line(12,2,1.5,5)
    elseif name=="stats"then
        line(2,10,3,8);line(8,6,3,12);line(14,2,3,16)
    elseif name=="players"then
        for _,bounds in ipairs({{4,2,6,6,3},{1,11,12,7,4},{12,3,5,5,3},{13,11,6,6,3}})do
            local part=line(bounds[1],bounds[2],bounds[3],bounds[4]);part.BackgroundTransparency=1;round(part,bounds[5])
            create("UIStroke",{Color=color,Thickness=1.2},part)
        end
    elseif name=="teleports"then
        local globe=line(2,2,16,16);globe.BackgroundTransparency=1;round(globe,8)
        create("UIStroke",{Color=color,Thickness=1.3},globe)
        local longitude=line(6,2,8,16);longitude.BackgroundTransparency=1;round(longitude,4)
        create("UIStroke",{Color=color,Thickness=1},longitude);line(2,10,16,1)
    else
        for index,y in ipairs({4,10,16})do
            line(2,y,16,1)
            local knob=line(index==2 and 12 or 6,y-2,4,4);knob.BackgroundColor3=colors.card;round(knob,2)
            create("UIStroke",{Color=color,Thickness=1.2},knob)
        end
    end
    return group
end
local function navigation(name,label,y)
    local b=create("TextButton",{Name="Tab_"..name,Text="",AutoButtonColor=false,BorderSizePixel=0,
        BackgroundColor3=colors.selected,BackgroundTransparency=name=="farm" and 0 or 1,
        Position=UDim2.fromOffset(4,y),Size=UDim2.fromOffset(240,42)},navigationBar)
    round(b,9)
    icon(b,name,16,11,name=="farm" and colors.accentText or colors.muted)
    local indicator=create("Frame",{Name="Indicator",BackgroundColor3=colors.accent,BorderSizePixel=0,
        Position=UDim2.fromOffset(-3,12),Size=UDim2.fromOffset(3,18),Visible=name=="farm"},b)
    round(indicator,1)
    local caption=text(b,label,UDim2.fromOffset(48,0),UDim2.fromOffset(166,42),15,name=="farm" and colors.text or colors.muted)
    caption.Name="Caption"
    tabButtons[name]=b
    connect(b.Activated,function()selectPage(name)end)
end
navigation("farm","Auto Farm",0)
navigation("raid","Auto Raid",54)
navigation("stats","Auto Stats",108)
navigation("teleports","Teleports",162)
navigation("players","Players",274)
navigation("settings","Settings",372)
appButton.Text="";icon(appButton,"settings",7,7,colors.muted)
do
    local order={"farm","raid","stats","teleports","players","settings"}
    local function shift(offset)
        for index,name in ipairs(order)do if name==currentPage then selectPage(order[(index-1+offset)%#order+1]);return end end
    end
    connect(previous.Activated,function()shift(-1)end);connect(nextPage.Activated,function()shift(1)end)
end
do
    local page=pages.teleports
    local heading=text(page,"Current sea",UDim2.fromOffset(2,0),UDim2.fromOffset(530,36),13,colors.text)
    heading.Name="TeleportSea"
    local refresh=create("TextButton",{Name="RefreshTeleports",Text="Refresh",Font=Enum.Font.Gotham,
        TextSize=12,TextColor3=colors.accentText,BackgroundColor3=colors.card,BorderSizePixel=0,
        Position=UDim2.fromOffset(664,2),Size=UDim2.fromOffset(88,30),AutoButtonColor=false},page)
    round(refresh,10)
    local cancel=create("TextButton",{Name="CancelFlight",Text="Stop flight",Font=Enum.Font.Gotham,
        TextSize=12,TextColor3=colors.muted,BackgroundColor3=colors.card,BorderSizePixel=0,Visible=false,
        Position=UDim2.fromOffset(558,2),Size=UDim2.fromOffset(98,30),AutoButtonColor=false},page)
    round(cancel,10)
    function teleport.updateFlightUI()cancel.Visible=teleport.flight~=nil end
    connect(cancel.Activated,function()teleport.cancel("Flight stopped.")end)
    for _,column in ipairs(columns[page])do
        column.Position=UDim2.fromOffset(column.Position.X.Offset,44)
        column.Size=UDim2.fromOffset(368,WINDOW_HEIGHT-192)
    end
    function teleport.clearUI()
        for _,connection in ipairs(teleport.rowConnections)do connection:Disconnect()end
        table.clear(teleport.rowConnections)
        for _,column in ipairs(columns[page])do
            for _,entry in ipairs(cards[column])do entry.card:Destroy()end
            table.clear(cards[column])
        end
    end
    function teleport.refreshUI()
        teleport.clearUI()
        local rows=teleport.collect()
        heading.Text=#rows>0 and ("Sea "..teleport.sea.." · "..#rows.." locations")or "Current sea is unsupported or unavailable"
        for index,row in ipairs(rows)do
            local column=columns[page][(index-1)%2+1]
            local button=create("TextButton",{Name="Teleport_"..row.name:gsub("%W",""),Text="",AutoButtonColor=false,
                BorderSizePixel=0,BackgroundColor3=colors.card,Size=UDim2.fromOffset(368,58)},column)
            round(button,14);icon(button,"teleports",14,19,colors.accentText)
            text(button,row.name,UDim2.fromOffset(44,8),UDim2.fromOffset(276,24),13,colors.text)
            text(button,row.marker and "Live location · Fly here"or "Island / landmark · Fly here",
                UDim2.fromOffset(44,31),UDim2.fromOffset(280,18),10,colors.muted)
            text(button,"›",UDim2.fromOffset(340,15),UDim2.fromOffset(18,28),20,colors.accentText)
            button:SetAttribute("Sea",row.sea);button:SetAttribute("Location",row.name)
            button.Visible=row.name:lower():find(searchBox.Text:lower(),1,true)~=nil
            table.insert(cards[column],{card=button,label=row.name})
            table.insert(teleport.rowConnections,button.Activated:Connect(function()teleport.begin(row)end))
        end
        for _,column in ipairs(columns[page])do
            local function reflow()
                local y=0
                for _,entry in ipairs(cards[column])do
                    if entry.card.Visible then entry.card.Position=UDim2.fromOffset(0,y);y+=68 end
                end
                column.CanvasSize=UDim2.fromOffset(0,math.max(0,y-10))
            end
            for _,entry in ipairs(cards[column])do entry.reflow=reflow end
            reflow()
        end
    end
    connect(refresh.Activated,teleport.refreshUI)
    local elapsed=0
    connect(RunService.Heartbeat,function(dt)
        if not menuShown or currentPage~="teleports" then return end
        elapsed+=dt;if elapsed<1 then return end;elapsed=0
        if teleport.dirty or teleport.sea~=Core.SEA_BY_PLACE[game.PlaceId]then teleport.refreshUI()end
    end)
end
activeLabel=text(window,"01 / 10 ACTIVE",UDim2.new(1,-149,1,-26),UDim2.fromOffset(125,16),9,colors.dim)
local function updateCount()
    local count=0;for key,enabled in pairs(state)do if key~="dodge" and enabled then count+=1 end end
    activeLabel.Text=string.format("%02d / 10 ACTIVE",count)
end
local installBaka=(function()
-- Popup components for the Baka presentation layer. No game actions live here.
return function(api)
    local create,round,text,connect,animate=api.create,api.round,api.text,api.connect,api.animate
    local colors,window,scale=api.colors,api.window,api.scale
    local ui={entry=nil,theme="Dark",language="English",h=.663,s=.42,v=1}
    local dragging
    local layer=create("Frame",{Name="BakaOverlays",BackgroundTransparency=1,Size=UDim2.fromScale(1,1),Visible=false,ZIndex=90},window)
    ui.layer=layer
    local shade=create("TextButton",{Name="DismissOverlay",Text="",AutoButtonColor=false,BackgroundColor3=Color3.fromRGB(0,0,0),
        BackgroundTransparency=.42,BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=1},layer)
    round(shade,26)
    local popup=create("Frame",{Name="ModulePopover",BackgroundColor3=colors.panel,BorderSizePixel=0,Visible=false,ZIndex=2,
        Position=UDim2.fromOffset(300,110),Size=UDim2.fromOffset(368,220)},layer)
    round(popup,18);create("UIStroke",{Color=colors.border,Transparency=.4,Thickness=1},popup)
    local title=text(popup,"Module settings",UDim2.fromOffset(18,9),UDim2.fromOffset(300,30),15,colors.text)
    local function button(parent,name,label,x,y,w,h)
        local b=create("TextButton",{Name=name,Text=label,Font=Enum.Font.Gotham,TextSize=13,TextColor3=colors.text,
            BackgroundColor3=colors.input,AutoButtonColor=false,BorderSizePixel=0,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h)},parent)
        round(b,9);return b
    end
    local moduleClose=button(popup,"CloseModulePopover","×",328,10,26,26);moduleClose.BackgroundTransparency=1
    local app=create("Frame",{Name="AppSettings",BackgroundColor3=colors.panel,BorderSizePixel=0,Visible=false,ZIndex=2,
        Position=UDim2.fromOffset(292,12),Size=UDim2.fromOffset(302,264)},layer)
    round(app,18);create("UIStroke",{Color=colors.border,Transparency=.6,Thickness=1},app)
    text(app,"App settings",UDim2.fromOffset(18,10),UDim2.fromOffset(242,30),13,colors.text)
    local appClose=button(app,"CloseAppSettings","×",266,12,22,22);appClose.BackgroundTransparency=1
    local themeTrack=create("Frame",{Name="ThemeTrack",BackgroundColor3=colors.input,BorderSizePixel=0,Position=UDim2.fromOffset(18,50),Size=UDim2.fromOffset(266,38)},app)
    round(themeTrack,19)
    local themes={}
    for i,name in ipairs({"Light","Dark","Black"})do
        local b=button(themeTrack,"Theme"..name,name,(i-1)*88+2,2,86,34);b.TextColor3=colors.muted
        connect(b.Activated,function()ui.setTheme(name)end);themes[name]=b
    end
    do
        local sun=create("Frame",{Name="SunIcon",BackgroundTransparency=1,Position=UDim2.fromOffset(9,12),Size=UDim2.fromOffset(10,10)},themes.Light)
        round(sun,5);create("UIStroke",{Color=colors.muted,Thickness=1},sun)
        for angle=0,315,45 do
            local a=math.rad(angle)
            create("Frame",{BackgroundColor3=colors.muted,BorderSizePixel=0,Position=UDim2.fromOffset(13+math.cos(a)*9,16+math.sin(a)*9),Size=UDim2.fromOffset(3,1),Rotation=angle},themes.Light)
        end
        local moon=create("Frame",{BackgroundColor3=colors.text,BorderSizePixel=0,Position=UDim2.fromOffset(9,10),Size=UDim2.fromOffset(14,14)},themes.Dark);round(moon,7)
        local cut=create("Frame",{Name="MoonCutout",BackgroundColor3=colors.selected,BorderSizePixel=0,Position=UDim2.fromOffset(15,6),Size=UDim2.fromOffset(14,14)},themes.Dark);round(cut,7)
        text(themes.Black,"Zz",UDim2.fromOffset(7,8),UDim2.fromOffset(18,20),10,colors.muted)
        for _,b in pairs(themes)do b.TextXAlignment=Enum.TextXAlignment.Right end
    end
    local palette={Color3.fromRGB(121,112,213),Color3.fromRGB(148,150,255),Color3.fromRGB(151,190,255),Color3.fromRGB(145,229,250),Color3.fromRGB(158,255,215)}
    for i,color in ipairs(palette)do
        local b=button(app,"Accent"..i,"",18+(i-1)*28,105,18,18);b.BackgroundColor3=color;round(b,9)
        b:SetAttribute("FixedColor",true)
        connect(b.Activated,function()ui.setAccent(color)end)
    end
    local accentButton=button(app,"OpenColorPicker","",266,105,18,18);accentButton.BackgroundColor3=colors.accent;round(accentButton,9)
    local accentRing=create("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(4,4),Size=UDim2.fromOffset(10,10)},accentButton)
    round(accentRing,5);create("UIStroke",{Color=colors.text,Thickness=1},accentRing)
    local languageButton=button(app,"LanguageMenu","English  ›",18,138,266,32);languageButton.BackgroundTransparency=1;languageButton.TextXAlignment=Enum.TextXAlignment.Left
    create("Frame",{BackgroundColor3=colors.border,BorderSizePixel=0,Position=UDim2.fromOffset(18,179),Size=UDim2.fromOffset(266,1)},app)
    text(app,"Interface scale",UDim2.fromOffset(18,190),UDim2.fromOffset(185,24),12,colors.muted)
    local scaleValue=text(app,tostring(api.appearance.scale).."%",UDim2.fromOffset(230,190),UDim2.fromOffset(54,24),12,colors.text)
    scaleValue.TextXAlignment=Enum.TextXAlignment.Right
    local scaleSlider=button(app,"InterfaceScale","",18,215,266,26);scaleSlider.BackgroundTransparency=1
    local scaleTrack=create("Frame",{BackgroundColor3=colors.track,BorderSizePixel=0,Position=UDim2.fromOffset(0,9),Size=UDim2.new(1,0,0,10)},scaleSlider);round(scaleTrack,5)
    local scaleFill=create("Frame",{BackgroundColor3=colors.accent,BorderSizePixel=0,Size=UDim2.fromScale((api.appearance.scale-60)/65,1)},scaleTrack);round(scaleFill,5)
    local scaleKnob=create("Frame",{BackgroundColor3=Color3.fromRGB(255,255,255),BorderSizePixel=0,AnchorPoint=Vector2.new(.5,.5),
        Position=UDim2.fromScale((api.appearance.scale-60)/65,.5),Size=UDim2.fromOffset(16,16)},scaleTrack);round(scaleKnob,8)
    local picker=create("Frame",{Name="ColorPicker",BackgroundColor3=colors.panel,BorderSizePixel=0,Visible=false,ZIndex=4,
        Position=UDim2.fromOffset(604,114),Size=UDim2.fromOffset(192,286)},layer)
    round(picker,18);create("UIStroke",{Color=colors.border,Transparency=.5,Thickness=1},picker)
    local preview=create("Frame",{Name="ColorPreview",BackgroundColor3=colors.panel,BorderSizePixel=0,Visible=false,ZIndex=3,
        Position=UDim2.fromOffset(180,320),Size=UDim2.fromOffset(300,84)},layer)
    round(preview,18)
    local swatch=create("Frame",{Name="ColorPreviewSwatch",BackgroundColor3=colors.accent,BorderSizePixel=0,
        Position=UDim2.fromOffset(16,15),Size=UDim2.fromOffset(54,54),ClipsDescendants=true},preview);round(swatch,12)
    for index=1,3 do
        create("Frame",{BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=.86,BorderSizePixel=0,Position=UDim2.fromOffset(index*13,0),Size=UDim2.fromOffset(1,54)},swatch)
        create("Frame",{BackgroundColor3=Color3.fromRGB(255,255,255),BackgroundTransparency=.86,BorderSizePixel=0,Position=UDim2.fromOffset(0,index*13),Size=UDim2.fromOffset(54,1)},swatch)
    end
    local swatchRing=create("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(21,21),Size=UDim2.fromOffset(12,12)},swatch)
    round(swatchRing,6);create("UIStroke",{Color=Color3.fromRGB(255,255,255),Thickness=1.5},swatchRing)
    local rgbLabel=text(preview,"RGB: 148 150 255",UDim2.fromOffset(86,17),UDim2.fromOffset(200,24),14,colors.text)
    local saveColor=button(preview,"SaveAccent","Save the selected color.",86,43,200,22)
    saveColor.BackgroundTransparency=1;saveColor.TextColor3=colors.muted;saveColor.TextXAlignment=Enum.TextXAlignment.Left;saveColor.TextSize=12
    connect(saveColor.Activated,function()ui.setAccent(colors.accent);saveColor.Text="Color saved."end)
    local wheel=button(picker,"ColorWheel","",16,16,160,160);wheel.BackgroundColor3=colors.input;round(wheel,80)
    local selector=create("Frame",{Name="WheelSelector",BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.29,.5),Size=UDim2.fromOffset(14,14),ZIndex=3},wheel)
    round(selector,7);create("UIStroke",{Color=Color3.fromRGB(255,255,255),Thickness=3},selector)
    local wheelAsset=api.wheelAsset()
    if wheelAsset then
        create("ImageLabel",{Name="BakaWheelImage",BackgroundTransparency=1,Image=wheelAsset,Size=UDim2.fromScale(1,1),ZIndex=2},wheel)
    else
        -- The picker remains usable without an executor's local asset API.
        for i,color in ipairs(palette)do
            local b=button(wheel,"WheelPreset"..i,"",12+(i-1)*28,68,24,24);b.BackgroundColor3=color;round(b,12)
            b:SetAttribute("FixedColor",true);connect(b.Activated,function()ui.setAccent(color)end)
        end
    end
    local saturation=button(picker,"ColorSaturation","",18,186,156,18);saturation.BackgroundTransparency=1
    local satTrack=create("Frame",{BackgroundColor3=colors.accent,BorderSizePixel=0,Position=UDim2.fromOffset(0,6),Size=UDim2.new(1,0,0,7)},saturation);round(satTrack,4)
    local satGradient=create("UIGradient",{Color=ColorSequence.new(Color3.fromRGB(255,255,255),colors.accent)},satTrack)
    local satKnob=create("Frame",{BackgroundColor3=Color3.fromRGB(255,255,255),BorderSizePixel=0,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(ui.s,.5),Size=UDim2.fromOffset(12,12)},satTrack);round(satKnob,6)
    local brightness=button(picker,"ColorBrightness","",18,210,156,18);brightness.BackgroundTransparency=1
    local valueTrack=create("Frame",{BackgroundColor3=colors.accent,BorderSizePixel=0,Position=UDim2.fromOffset(0,6),Size=UDim2.new(1,0,0,7)},brightness);round(valueTrack,4)
    local valueGradient=create("UIGradient",{Color=ColorSequence.new(Color3.fromRGB(0,0,0),colors.accent)},valueTrack)
    local valueKnob=create("Frame",{BackgroundColor3=Color3.fromRGB(255,255,255),BorderSizePixel=0,AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(1,.5),Size=UDim2.fromOffset(12,12)},valueTrack);round(valueKnob,6)
    local hex=create("TextBox",{Name="AccentHex",Text="#9496FF",ClearTextOnFocus=false,Font=Enum.Font.Gotham,TextSize=12,TextColor3=colors.text,
        BackgroundColor3=colors.input,BorderSizePixel=0,Position=UDim2.fromOffset(18,244),Size=UDim2.fromOffset(156,28)},picker);round(hex,8)
    local options=create("Frame",{Name="ChoicePopover",BackgroundColor3=colors.panel,BorderSizePixel=0,Visible=false,ZIndex=5,Size=UDim2.fromOffset(150,84)},layer);round(options,12)
    create("UIStroke",{Color=colors.border,Transparency=.35,Thickness=1},options)
    local choiceRows={button(options,"ChoiceFirst","",6,6,138,32),button(options,"ChoiceSecond","",6,42,138,32)}
    local choiceCallbacks={}
    for index,row in ipairs(choiceRows)do connect(row.Activated,function()
        options.Visible=false;if choiceCallbacks[index]then choiceCallbacks[index]()end
    end)end
    function ui.close()
        dragging=nil
        if ui.dismissExtras then ui.dismissExtras()end
        if ui.entry then
            local entry=ui.entry
            entry.body.Parent=entry.card;entry.body.Position=UDim2.fromOffset(0,64);entry.body.Visible=true;entry.expanded=false
        ui.entry=nil
        end
        popup.Visible=false;app.Visible=false;picker.Visible=false;preview.Visible=false;options.Visible=false;layer.Visible=false
    end
    local revealScales={}
    local function reveal(object)
        object.Visible=true;layer.Visible=true
        local revealScale=revealScales[object]
        if not revealScale then revealScale=create("UIScale",{Scale=1},object);revealScales[object]=revealScale end
        revealScale.Scale=.97;animate(revealScale,{Scale=1})
        shade.BackgroundTransparency=.7;animate(shade,{BackgroundTransparency=.42})
    end
    function ui.openModule(entry)
        if ui.entry==entry then ui.close();return end
        ui.close();ui.entry=entry;entry.expanded=true
        entry.body.Parent=popup;entry.body.Visible=true;entry.body.Position=UDim2.fromOffset(0,44)
        title.Text=entry.label;popup.Size=UDim2.fromOffset(368,entry.height+62)
        local origin=entry.card.AbsolutePosition-window.AbsolutePosition
        local x=math.clamp(origin.X/math.max(.1,scale.Scale)+20,292,api.width-386)
        local y=math.clamp(origin.Y/math.max(.1,scale.Scale)+18,76,api.height-entry.height-82)
        popup.Position=UDim2.fromOffset(x,y);reveal(popup)
        entry.body.GroupTransparency=1;animate(entry.body,{GroupTransparency=0})
    end
    function ui.openApp()ui.close();reveal(app)end
    function ui.openChoices(anchor,rows)
        choiceCallbacks={}
        for i,b in ipairs(choiceRows)do
            b.Visible=rows[i]~=nil
            if rows[i]then b.Text=rows[i][1];choiceCallbacks[i]=rows[i][2]end
        end
        local p=(anchor.AbsolutePosition-window.AbsolutePosition)/math.max(.1,scale.Scale)
        options.Position=UDim2.fromOffset(math.clamp(p.X,12,api.width-164),math.clamp(p.Y+34,12,api.height-96))
        reveal(options)
    end
    function ui.setTheme(name)
        if not api.palettes[name]then return end
        ui.theme=name;api.applyTheme(name)
        for id,b in pairs(themes)do b.BackgroundColor3=id==name and colors.selected or colors.input;b.TextColor3=id==name and colors.text or colors.muted end
        themes.Dark:FindFirstChild("MoonCutout").BackgroundColor3=themes.Dark.BackgroundColor3
        api.playerGui:SetAttribute("BakaTheme",name)
    end
    local function rgb(color)return math.floor(color.R*255+.5),math.floor(color.G*255+.5),math.floor(color.B*255+.5)end
    function ui.setAccent(color)
        ui.h,ui.s,ui.v=color:ToHSV()
        api.applyAccent(color);accentButton.BackgroundColor3=color;satTrack.BackgroundColor3=color;valueTrack.BackgroundColor3=color
        local r,g,b=rgb(color);hex.Text=string.format("#%02X%02X%02X",r,g,b)
        rgbLabel.Text=string.format("RGB: %d %d %d",r,g,b);swatch.BackgroundColor3=color;saveColor.Text="Save the selected color."
        selector.Position=UDim2.fromScale(.5+math.cos((.9-ui.h)*2*math.pi)*ui.s*.5,.5+math.sin((.9-ui.h)*2*math.pi)*ui.s*.5)
        satGradient.Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromHSV(ui.h,1,1))
        valueGradient.Color=ColorSequence.new(Color3.fromRGB(0,0,0),Color3.fromHSV(ui.h,ui.s,1))
        satKnob.Position=UDim2.fromScale(ui.s,.5);valueKnob.Position=UDim2.fromScale(ui.v,.5)
        api.playerGui:SetAttribute("BakaAccent",hex.Text)
    end
    connect(hex.FocusLost,function()
        local value=hex.Text:gsub("#","")
        if value:match("^%x%x%x%x%x%x$")then ui.setAccent(Color3.fromRGB(tonumber(value:sub(1,2),16),tonumber(value:sub(3,4),16),tonumber(value:sub(5,6),16)))
        else local r,g,b=rgb(colors.accent);hex.Text=string.format("#%02X%02X%02X",r,g,b)end
    end)
    dragging=nil
    local function updatePointer(object,position)
        if object==wheel then
            local size=wheel.AbsoluteSize;local dx=(position.X-wheel.AbsolutePosition.X)/math.max(1,size.X)*2-1
            local dy=(position.Y-wheel.AbsolutePosition.Y)/math.max(1,size.Y)*2-1
            ui.setAccent(Color3.fromHSV((.9-math.atan2(dy,dx)/(2*math.pi)+1)%1,math.min(1,math.sqrt(dx*dx+dy*dy)),ui.v))
        else
            local fraction=math.clamp((position.X-object.AbsolutePosition.X)/math.max(1,object.AbsoluteSize.X),0,1)
            if object==scaleSlider then
                api.appearance.scale=math.floor(60+65*fraction+.5)
                scaleValue.Text=api.appearance.scale.."%";scaleFill.Size=UDim2.fromScale(fraction,1);scaleKnob.Position=UDim2.fromScale(fraction,.5)
                api.resize();api.playerGui:SetAttribute("BakaScale",api.appearance.scale)
            elseif object==saturation then ui.setAccent(Color3.fromHSV(ui.h,fraction,ui.v))
            else ui.setAccent(Color3.fromHSV(ui.h,ui.s,fraction))end
        end
    end
    for _,object in ipairs({wheel,saturation,brightness,scaleSlider})do
        connect(object.InputBegan,function(input)
            if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
                dragging={object=object,input=input};updatePointer(object,input.Position)
            end
        end)
    end
    connect(api.input.InputChanged,function(input)
        if dragging and layer.Visible and (input==dragging.input or input.UserInputType==Enum.UserInputType.MouseMovement)then updatePointer(dragging.object,input.Position)end
    end)
    connect(api.input.InputEnded,function(input)if dragging and input==dragging.input then dragging=nil end end)
    connect(shade.Activated,function()dragging=nil;ui.close()end);connect(moduleClose.Activated,ui.close);connect(appClose.Activated,ui.close)
    connect(api.input.InputBegan,function(input,processed)if not processed and input.KeyCode==Enum.KeyCode.Escape then ui.close()end end)
    connect(accentButton.Activated,function()
        if picker.Visible then picker.Visible=false;preview.Visible=false else reveal(picker);preview.Visible=true end
        options.Visible=false
    end)
    function ui.setLanguage(name)
        ui.language=name;languageButton.Text=name.."  ›";api.translate(name=="Русский")
    end
    connect(languageButton.Activated,function()
        ui.openChoices(languageButton,{{"English",function()ui.setLanguage("English")end},
            {"Русский",function()ui.setLanguage("Русский")end}})
    end)
    function ui.refresh()
        for name,b in pairs(themes)do
            b.BackgroundColor3=name==ui.theme and colors.selected or colors.input
            b.TextColor3=name==ui.theme and colors.text or colors.muted
        end
        themes.Dark:FindFirstChild("MoonCutout").BackgroundColor3=themes.Dark.BackgroundColor3
    end
    ui.refresh()
    return ui
end

end)()
do
local assets=(function()
-- Locally generated HSV wheel; no external requests.
return {wheel="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"}

end)()
local assetCache
local function wheelAsset()
    if assetCache then return assetCache end
    if playerGui:GetAttribute("ViltrumHeadlessUI")then assetCache="bakaasset://wheel";return assetCache end
    local loader=getcustomasset or getsynasset
    if type(loader)~="function" or type(writefile)~="function"then return nil end
    local ok,result=pcall(function()
        local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local lookup={};for i=1,#alphabet do lookup[alphabet:sub(i,i)]=i-1 end
        local bytes={};local buffer,bits=0,0
        for i=1,#assets.wheel do
            local value=lookup[assets.wheel:sub(i,i)]
            if value then
                buffer=buffer*64+value;bits+=6
                if bits>=8 then bits-=8;local power=2^bits;bytes[#bytes+1]=string.char(math.floor(buffer/power)%256);buffer%=power end
            end
        end
        local path="baka-color-wheel-v29.png"
        writefile(path,table.concat(bytes));return loader(path)
    end)
    if ok and type(result)=="string"then assetCache=result;return result end
    return nil
end
local palettes={
    Dark={background={18,18,21},sidebar={24,24,28},panel={29,29,34},card={25,25,29},input={36,36,43},selected={48,48,59},track={42,42,49},dim={111,111,126},border={46,46,53},text={232,232,239},muted={157,157,171},dark={18,18,21}},
    Light={background={241,242,248},sidebar={250,250,253},panel={255,255,255},card={250,250,254},input={233,234,242},selected={218,219,236},track={224,225,235},dim={125,125,142},border={220,221,230},text={32,32,43},muted={97,97,115},dark={241,242,248}},
    Black={background={0,0,0},sidebar={10,10,12},panel={18,18,21},card={11,11,14},input={25,25,30},selected={39,39,49},track={29,29,36},dim={102,102,116},border={32,32,39},text={232,232,239},muted={152,152,166},dark={0,0,0}},
}
local function refreshAppearance()
    for object,roles in pairs(appearance.bindings)do
        if object.Parent and object:GetAttribute("FixedColor")~=true then
            for property,role in pairs(roles)do if colors[role]then object[property]=colors[role]end end
            if object:IsA("TextButton")and object:GetAttribute("Selected")~=nil then
                object.BackgroundColor3=object:GetAttribute("Selected")and colors.selected or colors.input
                object.TextColor3=object:GetAttribute("Selected")and colors.accentText or colors.muted
            end
        end
    end
    for key,refresh in pairs(controls)do refresh(state[key])end
    if appearance.refresh then appearance.refresh()end
end
local translations={
    ["Auto Farm"]="Автофарм",["Auto Raid"]="Авторейд",["Auto Stats"]="Автостаты",["Teleports"]="Телепорты",["Players"]="Игроки",["Settings"]="Настройки",
    ["App settings"]="Настройки GUI",["Interface scale"]="Масштаб интерфейса",["Combat"]="Бой",["Weapon control"]="Оружие",["Fruit finisher"]="Добивание фруктом",
    ["Quest routing"]="Квесты",["Point allocation"]="Распределение очков",["Allocation rules"]="Правила распределения",["Island progress"]="Прогресс островов",["Raid controls"]="Параметры рейда",
    ["Display"]="Отображение",["Interface"]="Интерфейс",["Fruit ESP"]="ESP фруктов",["Speed Hack"]="Скорость",["Player names"]="Имена игроков",["Distance"]="Дистанция",["Through walls"]="Сквозь стены",
    ["Auto Quests"]="Автоквесты",["Weapon type"]="Тип оружия",["Search function ..."]="Поиск функции ...",["Walking speed"]="Скорость ходьбы",["Client session"]="Сессия клиента",
}
local originalText=setmetatable({}, {__mode="k"})
ui=installBaka({create=create,round=round,text=text,connect=connect,animate=animate,colors=colors,window=window,scale=uiScale,
    width=WINDOW_WIDTH,height=WINDOW_HEIGHT,input=UserInputService,playerGui=playerGui,appearance=appearance,palettes=palettes,resize=resize,wheelAsset=wheelAsset,
    applyTheme=function(name)
        for role,rgb in pairs(palettes[name])do colors[role]=Color3.fromRGB(rgb[1],rgb[2],rgb[3])end
        refreshAppearance()
    end,
    applyAccent=function(color)
        colors.accent=color;colors.accentText=color;refreshAppearance();if ui then ui.refresh()end
    end,
    translate=function(russian)
        for _,object in ipairs(window:GetDescendants())do
            if object:IsA("TextLabel")or object:IsA("TextButton")then
                local value=originalText[object]or object.Text
                if translations[value]then originalText[object]=value;object.Text=russian and translations[value]or value end
            end
        end
        searchBox.PlaceholderText=russian and translations["Search function ..."]or "Search function ..."
        playerGui:SetAttribute("BakaLanguage",russian and "Русский"or "English")
    end,
})
connect(appButton.Activated,ui.openApp)
end

local function section(parent,label,x,y,height,category)
    local columnIndex=(label=="Auto Farm" or label=="Weapon control" or label=="Fruit finisher" or label=="Auto Raid" or label=="Raid controls" or label=="Auto Stats" or label=="Allocation rules" or label=="Players" or label=="Interface" or label=="Speed Hack")and 1 or 2
    local column=columns[parent][columnIndex]
    local card=create("Frame",{Name="Card_"..label:gsub("%W",""),BackgroundColor3=colors.card,BorderSizePixel=0,
        Position=UDim2.fromOffset(0,0),Size=UDim2.fromOffset(368,height+78),ClipsDescendants=true},column)
    round(card,14)
    icon(card,category or "settings",14,19,colors.accent)
    text(card,label,UDim2.fromOffset(43,9),UDim2.fromOffset(220,22),15,colors.text)
    local descriptions={
        ["Auto Farm"]="Quest farming automation",["Combat"]="Aura activation",["Weapon control"]="Melee, fruit and sword slots",
        ["Fruit finisher"]="Finish low HP enemies with skills",["Quest routing"]="Active quest and world",
        ["Auto Raid"]="Raid automation",["Raid controls"]="Group attacks and side dodge",["Island progress"]="Current raid island",
        ["Auto Stats"]="Allocate available stat points",["Point allocation"]="Amount per stat",["Allocation rules"]="Timing and allocation status",
        ["Players"]="Names and distance overlay",["Display"]="Overlay display options",["Interface"]="Menu controls",
        ["Fruit ESP"]="Dropped fruit names and distance",["Speed Hack"]="Adjust walking speed",
        ["Show fruit price"]="Normal values in inventory and trade",
    }
    text(card,descriptions[label]or"Module settings",UDim2.fromOffset(43,31),UDim2.fromOffset(220,16),10,colors.muted)
    local body=create("CanvasGroup",{BackgroundTransparency=1,BorderSizePixel=0,Visible=true,GroupTransparency=0,
        Name="CardBody",Position=UDim2.fromOffset(0,64),Size=UDim2.fromOffset(368,height)},card)
    local gear=create("TextButton",{Name="Expand_"..label:gsub("%W",""),Text="···",TextSize=18,Font=Enum.Font.Gotham,
        TextColor3=colors.text,BackgroundTransparency=1,BorderSizePixel=0,Position=UDim2.new(1,-80,0,17),Size=UDim2.fromOffset(24,24)},card)
    local entry={card=card,label=label,expanded=false,height=height,body=body}
    table.insert(cards[column],entry)
    local function reflow()
        local top=0
        for _,item in ipairs(cards[column])do
            if item.card.Visible then
                animate(item.card,{Position=UDim2.fromOffset(0,top),Size=UDim2.fromOffset(368,item.height+78)})
                top+=item.height+90
            end
        end
        column.CanvasSize=UDim2.fromOffset(0,top)
    end
    entry.reflow=reflow
    connect(gear.Activated,function()ui.openModule(entry)end)
    reflow()
    return body
end
connect(search.Activated,function()searchBox.Text="";searchBox:CaptureFocus()end)
connect(searchBox:GetPropertyChangedSignal("Text"),function()
    local query=searchBox.Text:lower()
    for _,entries in pairs(cards)do
        for _,entry in ipairs(entries)do entry.card.Visible=entry.label:lower():find(query,1,true)~=nil end
        if entries[1]then entries[1].reflow()end
    end
end)
local function divider(parent,y)
    create("Frame",{BackgroundColor3=colors.border,BackgroundTransparency=.65,BorderSizePixel=0,
        Position=UDim2.fromOffset(13,y),Size=UDim2.new(1,-26,0,1)},parent)
end
local function toggle(parent,y,key,label,callback)
    local moduleHeader=label=="Enabled"
    if not moduleHeader then text(parent,label,UDim2.fromOffset(14,y),UDim2.fromOffset(244,38),12,colors.muted)
    else
        text(parent,key=="farm" and "Complete the active quest." or key=="raid" and "Continue a started raid." or key=="fruits" and "Show dropped fruits on the map." or key=="fruitprice" and "Normal values in inventory and trade." or key=="speed" and "Walking speed; paused during flight." or "Allocate your available points.",
            UDim2.fromOffset(14,y),UDim2.fromOffset(308,32),11,colors.muted)
    end
    local b=create("TextButton",{Name=key,Text="",AutoButtonColor=false,BorderSizePixel=0,
        Position=UDim2.new(1,-46,0,moduleHeader and 16 or y+6),Size=UDim2.fromOffset(28,14),BackgroundColor3=colors.track},moduleHeader and parent.Parent or parent)
    round(b,7)
    local knob=create("Frame",{Name="Knob",BorderSizePixel=0,Size=UDim2.fromOffset(10,10),
        Position=UDim2.fromOffset(2,2),BackgroundTransparency=1},b)
    b.Size=UDim2.fromOffset(26,26);round(b,8)
    local checkmark=create("Frame",{Name="Checkmark",BackgroundTransparency=1,Size=UDim2.fromScale(1,1)},b)
    create("Frame",{BackgroundColor3=colors.text,BorderSizePixel=0,Position=UDim2.fromOffset(6,13),Size=UDim2.fromOffset(7,1.5),Rotation=45},checkmark)
    create("Frame",{BackgroundColor3=colors.text,BorderSizePixel=0,Position=UDim2.fromOffset(10,11),Size=UDim2.fromOffset(12,1.5),Rotation=-45},checkmark)
    controls[key]=function(value)
        checkmark.Visible=value
        b:SetAttribute("On",value)
        animate(b,{BackgroundColor3=value and colors.accent or colors.track})
        animate(knob,{Position=UDim2.fromOffset(value and 16 or 2,2),BackgroundColor3=colors.card})
        updateCount()
    end
    controls[key](state[key])
    connect(b.Activated,function()
        local value=not state[key]
        if callback and callback(value)==false then return end
        state[key]=value;controls[key](value)
    end)
end
local mainSection=section(pages.farm,"Auto Farm",0,0,114,"farm")
toggle(mainSection,0,"farm","Enabled",function(enabled)
    if enabled then
        if game.GameId~=994732206 then status("Auto Farm: this adapter is for Blox Fruits.");return false end
        if state.quests and not SEA_BY_PLACE[game.PlaceId]then
            status("Unknown sea: PlaceId="..tostring(game.PlaceId).." · GameId="..tostring(game.GameId))
            return false
        end
        teleport.cancel()
        lastAttack,lastQuest=-math.huge,-math.huge;questAttempts=0
        if state.raid then stopRaid()end
        lastQuestReply="none"
        bossAttempts,lastAbandon=0,-math.huge
        auraRequestedCharacter=nil;auraStatus="pending"
        slotCharacter=nil;combatProbe=nil
        local character=localPlayer.Character
        if character then
            local root=character:FindFirstChild("HumanoidRootPart")
            if root then holdPosition(root,root.Position,nil) end
            disableCollisions(character);ensureAura(character)
        end
        watchedMob,watchedHealth,attackCount=nil,nil,0;status("Starting "..CONFIG.WeaponType.." Auto Farm…")
    else stopFarm("Auto Farm stopped.") end
end)
divider(mainSection,38)
toggle(mainSection,38,"quests","Auto Quests",function()
    stopMovement();stopHover();cancelQuestRequest();questAttempts=0;watchedMob=nil
end)
divider(mainSection,76)
text(mainSection,"Weapon type",UDim2.fromOffset(14,76),UDim2.fromOffset(110,38),12,colors.muted)
local weaponTypeButton=create("TextButton",{Name="WeaponType",Text="Melee",Font=Enum.Font.Gotham,
    TextSize=12,TextColor3=colors.text,BackgroundColor3=colors.selected,BorderSizePixel=0,
    Position=UDim2.new(1,-205,0,82),Size=UDim2.fromOffset(60,26)},mainSection)
round(weaponTypeButton,5)
local fruitTypeButton=create("TextButton",{Name="ChooseFruit",Text="Fruit",Font=Enum.Font.Gotham,
    TextSize=12,TextColor3=colors.text,BackgroundColor3=colors.input,BorderSizePixel=0,
    Position=UDim2.new(1,-139,0,82),Size=UDim2.fromOffset(60,26)},mainSection)
round(fruitTypeButton,5)
local swordTypeButton=create("TextButton",{Name="ChooseSword",Text="Sword",Font=Enum.Font.Gotham,
    TextSize=12,TextColor3=colors.text,BackgroundColor3=colors.selected,BorderSizePixel=0,
    Position=UDim2.new(1,-78,0,82),Size=UDim2.fromOffset(62,26)},mainSection)
round(swordTypeButton,5)
local positionSection=section(pages.farm,"Combat",352,0,114,"farm")
text(positionSection,"Target",UDim2.fromOffset(14,0),UDim2.fromOffset(135,38),12,colors.muted)
text(positionSection,"Quest group",UDim2.new(1,-93,0,0),UDim2.fromOffset(84,38),11,colors.text)
divider(positionSection,38)
text(positionSection,"Aura",UDim2.fromOffset(14,38),UDim2.fromOffset(85,38),12,colors.muted)
local auraOffButton=create("TextButton",{Name="AuraOff",Text="Не включать",Font=Enum.Font.Gotham,
    TextSize=11,TextColor3=colors.muted,BackgroundColor3=colors.input,BorderSizePixel=0,
    Position=UDim2.new(1,-228,0,44),Size=UDim2.fromOffset(112,26)},positionSection)
local auraOnButton=create("TextButton",{Name="AuraOn",Text="Включать",Font=Enum.Font.Gotham,
    TextSize=11,TextColor3=colors.muted,BackgroundColor3=colors.input,BorderSizePixel=0,
    Position=UDim2.new(1,-110,0,44),Size=UDim2.fromOffset(96,26)},positionSection)
round(auraOffButton,4);round(auraOnButton,4)
local function updateAuraChoice()
    auraOffButton:SetAttribute("Selected",not CONFIG.AutoAura)
    auraOnButton:SetAttribute("Selected",CONFIG.AutoAura)
    animate(auraOffButton,{BackgroundColor3=not CONFIG.AutoAura and colors.selected or colors.input})
    animate(auraOnButton,{BackgroundColor3=CONFIG.AutoAura and colors.selected or colors.input})
    auraOffButton.TextColor3=not CONFIG.AutoAura and colors.accentText or colors.muted
    auraOnButton.TextColor3=CONFIG.AutoAura and colors.accentText or colors.muted
end
local function selectAura(enabled)
    if CONFIG.AutoAura==enabled then return end
    cancelAuraRequest();auraRequestedCharacter=nil;CONFIG.AutoAura=enabled
    updateAuraChoice()
    local character=localPlayer.Character
    if character then
        if state.farm or state.raid then ensureAura(character)
        else auraStatus=hasAura(character) and "on" or enabled and "pending" or "auto off"end
    end
    status(enabled and "Aura: automatic activation enabled." or "Aura: automatic activation disabled.")
end
updateAuraChoice()
connect(auraOffButton.Activated,function()selectAura(false)end)
connect(auraOnButton.Activated,function()selectAura(true)end)
divider(positionSection,76)
text(positionSection,"Height above NPC",UDim2.fromOffset(14,76),UDim2.fromOffset(220,38),12,colors.muted)
text(positionSection,"33 studs",UDim2.new(1,-84,0,76),UDim2.fromOffset(70,38),11)
local styleSection=section(pages.farm,"Weapon control",704,0,83,"settings")
text(styleSection,"Hotbar slot",UDim2.fromOffset(14,5),UDim2.fromOffset(150,28),12,colors.muted)
local function chosenSlot()return CONFIG.WeaponType=="Melee" and 1 or CONFIG.WeaponType=="Fruit" and CONFIG.FruitSlot or CONFIG.SwordSlot end
local slotBox=create("TextBox",{Name="WeaponSlot",Text=tostring(chosenSlot()),
    ClearTextOnFocus=false,Font=Enum.Font.Gotham,TextSize=12,TextColor3=colors.text,BackgroundColor3=colors.input,
    BorderSizePixel=0,Position=UDim2.new(1,-62,0,7),Size=UDim2.fromOffset(48,25)},styleSection)
round(slotBox,5)
connect(slotBox.FocusLost,function()
    local value=tonumber(slotBox.Text)
    if CONFIG.WeaponType=="Sword" and value and value>=1 and value<=10 then CONFIG.SwordSlot=math.floor(value)end
    if CONFIG.WeaponType=="Fruit" and value and value>=1 and value<=10 then CONFIG.FruitSlot=math.floor(value)end
    releaseNativeClick()
    slotBox.Text=tostring(chosenSlot())
    slotCharacter=nil;combatProbe=nil
end)
local function updateWeaponChoice()
    weaponTypeButton.BackgroundColor3=CONFIG.WeaponType=="Melee" and colors.selected or colors.input
    swordTypeButton.BackgroundColor3=CONFIG.WeaponType=="Sword" and colors.selected or colors.input
    weaponTypeButton.TextColor3=CONFIG.WeaponType=="Melee" and colors.accentText or colors.muted
    swordTypeButton.TextColor3=CONFIG.WeaponType=="Sword" and colors.accentText or colors.muted
    fruitTypeButton.BackgroundColor3=CONFIG.WeaponType=="Fruit" and colors.selected or colors.input
    fruitTypeButton.TextColor3=CONFIG.WeaponType=="Fruit" and colors.accentText or colors.muted
end
local function selectWeaponType(mode)
    if CONFIG.WeaponType==mode then return end
    releaseNativeClick();deactivateWeapon();fruit.target=nil;CONFIG.WeaponType=mode
    updateWeaponChoice()
    slotBox.Text=tostring(chosenSlot())
    slotCharacter=nil;combatProbe=nil;lastAttack=-math.huge
    status("Weapon type: "..CONFIG.WeaponType)
end
updateWeaponChoice()
connect(weaponTypeButton.Activated,function()selectWeaponType("Melee")end)
connect(swordTypeButton.Activated,function()selectWeaponType("Sword")end)
connect(fruitTypeButton.Activated,function()selectWeaponType("Fruit")end)
do
    local menu=create("TextButton",{Name="WeaponMenu",Text=CONFIG.WeaponType.."  ›",Font=Enum.Font.Gotham,TextSize=12,
        TextColor3=colors.text,BackgroundColor3=colors.input,BorderSizePixel=0,AutoButtonColor=false,
        Position=UDim2.new(1,-195,0,82),Size=UDim2.fromOffset(180,26)},mainSection)
    round(menu,8)
    local choices=create("Frame",{Name="WeaponChoices",BackgroundColor3=colors.panel,BorderSizePixel=0,Visible=false,ZIndex=6,
        Position=UDim2.fromOffset(600,210),Size=UDim2.fromOffset(180,114)},ui.layer)
    round(choices,12);create("UIStroke",{Color=colors.border,Thickness=1,Transparency=.4},choices)
    for index,button in ipairs({weaponTypeButton,fruitTypeButton,swordTypeButton})do
        button.Parent=choices;button.Position=UDim2.fromOffset(6,6+(index-1)*34);button.Size=UDim2.fromOffset(168,30)
        connect(button.Activated,function()menu.Text=CONFIG.WeaponType.."  ›";choices.Visible=false;if not ui.entry then ui.close()end end)
    end
    connect(menu.Activated,function()
        if choices.Visible then choices.Visible=false;return end
        local p=(menu.AbsolutePosition-window.AbsolutePosition)/math.max(.1,uiScale.Scale)
        choices.Position=UDim2.fromOffset(math.clamp(p.X,292,WINDOW_WIDTH-198),math.clamp(p.Y+32,76,WINDOW_HEIGHT-132))
        ui.layer.Visible=true;choices.Visible=true
    end)
    ui.dismissExtras=function()choices.Visible=false end
end

do
    local card=section(pages.farm,"Fruit finisher",704,190,135,"farm")
    text(card,"Selected skills",UDim2.fromOffset(14,0),UDim2.fromOffset(280,24),12,colors.muted)
    for index,key in ipairs({"Z","X","C","V"})do
        local button=create("TextButton",{Name="FruitSkill"..key,Text=key,Font=Enum.Font.Gotham,TextSize=12,
            BorderSizePixel=0,Position=UDim2.fromOffset(14+(index-1)*78,29),Size=UDim2.fromOffset(70,28)},card)
        round(button,7)
        local function refresh()
            button:SetAttribute("Selected",CONFIG.FruitSkills[key])
            animate(button,{BackgroundColor3=CONFIG.FruitSkills[key] and colors.selected or colors.input})
            button.TextColor3=CONFIG.FruitSkills[key] and colors.accentText or colors.muted
        end
        refresh();connect(button.Activated,function()
            releaseNativeClick();fruit.target=nil;CONFIG.FruitSkills[key]=not CONFIG.FruitSkills[key];refresh()
        end)
    end
    divider(card,67)
    text(card,"Finish below HP %",UDim2.fromOffset(14,73),UDim2.fromOffset(230,28),12,colors.muted)
    local box=create("TextBox",{Name="FruitPercent",Text=tostring(CONFIG.FruitPercent),ClearTextOnFocus=false,
        Font=Enum.Font.Gotham,TextSize=12,TextColor3=colors.text,BackgroundColor3=colors.input,BorderSizePixel=0,
        Position=UDim2.new(1,-62,0,75),Size=UDim2.fromOffset(48,25)},card)
    round(box,5);connect(box.FocusLost,function()
        local n=tonumber(box.Text)
        if n and n==n and n>=1 and n<=50 then CONFIG.FruitPercent=math.floor(n)end
        box.Text=tostring(CONFIG.FruitPercent);releaseNativeClick();fruit.target=nil
    end)
    text(card,"Melee first · then selected fruit skills",UDim2.fromOffset(14,108),UDim2.fromOffset(308,24),10,colors.dim)
end
divider(styleSection,38)
text(styleSection,"Equip before travel",UDim2.fromOffset(14,40),UDim2.fromOffset(250,30),11,colors.muted)
local infoSection=section(pages.farm,"Quest routing",352,180,83,"raid")
text(infoSection,"Sea",UDim2.fromOffset(14,5),UDim2.fromOffset(120,30),12,colors.muted)
text(infoSection,tostring(SEA_BY_PLACE[game.PlaceId]or"Unknown"),UDim2.new(1,-74,0,5),UDim2.fromOffset(63,30),11)
divider(infoSection,38)
text(infoSection,"Quest priority",UDim2.fromOffset(14,42),UDim2.fromOffset(150,30),12,colors.muted)
text(infoSection,"Active first",UDim2.new(1,-84,0,42),UDim2.fromOffset(73,30),11)
local visualSection=section(pages.players,"Players",0,0,114,"players")
toggle(visualSection,0,"names","Player names");divider(visualSection,38)
toggle(visualSection,38,"distance","Distance");divider(visualSection,76)
toggle(visualSection,76,"walls","Through walls")
do
    local fruitCard=section(pages.players,"Fruit ESP",352,0,76,"players")
    toggle(fruitCard,0,"fruits","Enabled",function(enabled)fruitEsp.set(enabled)end)
    text(fruitCard,"Fruit name + distance · Studs",UDim2.fromOffset(14,38),UDim2.fromOffset(330,30),11,colors.muted)
    do
        local priceCard=section(pages.players,"Show fruit price",352,0,114,"players")
        toggle(priceCard,0,"fruitprice","Enabled",function(enabled)fruitPrice.set(enabled)end)
        divider(priceCard,38)
        text(priceCard,"Market value",UDim2.fromOffset(14,38),UDim2.fromOffset(200,38),12,colors.muted)
        text(priceCard,"Normal",UDim2.new(1,-70,0,38),UDim2.fromOffset(56,38),11,colors.text)
        divider(priceCard,76)
        fruitPrice.label=text(priceCard,"Game.Guide · Normal",UDim2.fromOffset(14,76),UDim2.fromOffset(240,38),10,colors.muted)
        fruitPrice.label.Name="FruitPriceSource"
        local refresh=create("TextButton",{Name="RefreshFruitPrices",Text="Refresh",Font=Enum.Font.Gotham,TextSize=11,
            AutoButtonColor=false,BorderSizePixel=0,BackgroundColor3=colors.input,TextColor3=colors.accent,
            Position=UDim2.new(1,-85,0,82),Size=UDim2.fromOffset(70,26)},priceCard)
        round(refresh,7);connect(refresh.Activated,function()fruitPrice.refresh(true)end)
    end
    local speedCard=section(pages.settings,"Speed Hack",0,0,114,"stats")
    toggle(speedCard,0,"speed","Enabled",function(enabled)
        if not enabled then speedHack.restore()end
    end)
    local value=text(speedCard,tostring(CONFIG.WalkSpeed).." studs/s",UDim2.fromOffset(220,37),UDim2.fromOffset(132,30),12,colors.text)
    value.Name="SpeedValue"
    text(speedCard,"Walking speed",UDim2.fromOffset(14,37),UDim2.fromOffset(200,30),12,colors.muted)
    local slider=create("TextButton",{Name="SpeedSlider",Text="",AutoButtonColor=false,BackgroundTransparency=1,
        BorderSizePixel=0,Position=UDim2.fromOffset(14,73),Size=UDim2.fromOffset(338,26)},speedCard)
    local track=create("Frame",{Name="Track",BackgroundColor3=colors.track,BorderSizePixel=0,
        Position=UDim2.fromOffset(0,11),Size=UDim2.new(1,0,0,4)},slider);round(track,2)
    local fill=create("Frame",{Name="Fill",BackgroundColor3=colors.accent,BorderSizePixel=0,
        Size=UDim2.new((CONFIG.WalkSpeed-1)/221,0,1,0)},track);round(fill,2)
    local knob=create("Frame",{Name="Knob",BackgroundColor3=colors.accent,BorderSizePixel=0,
        AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new((CONFIG.WalkSpeed-1)/221,0,.5,0),Size=UDim2.fromOffset(12,12)},track);round(knob,6)
    local dragging
    local function setPosition(position)
        local ratio=math.clamp((position.X-slider.AbsolutePosition.X)/math.max(1,slider.AbsoluteSize.X),0,1)
        CONFIG.WalkSpeed=math.clamp(math.floor(1+ratio*221+.5),1,222)
        value.Text=tostring(CONFIG.WalkSpeed).." studs/s"
        fill.Size=UDim2.new((CONFIG.WalkSpeed-1)/221,0,1,0)
        knob.Position=UDim2.new((CONFIG.WalkSpeed-1)/221,0,.5,0)
        speedHack.tick()
    end
    connect(slider.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            dragging=input;setPosition(input.Position)
        end
    end)
    connect(UserInputService.InputChanged,function(input)
        if dragging and (input==dragging or dragging.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement)then setPosition(input.Position)end
    end)
    connect(UserInputService.InputEnded,function(input)if input==dragging then dragging=nil end end)
    text(speedCard,"1",UDim2.fromOffset(14,98),UDim2.fromOffset(30,16),9,colors.dim)
    text(speedCard,"222",UDim2.fromOffset(326,98),UDim2.fromOffset(30,16),9,colors.dim)
end
local units=section(pages.players,"Display",352,0,76,"settings")
text(units,"Distance units",UDim2.fromOffset(14,0),UDim2.fromOffset(160,38),12,colors.muted)
text(units,"Studs",UDim2.new(1,-58,0,0),UDim2.fromOffset(48,38),11)
divider(units,38)
text(units,"Names",UDim2.fromOffset(14,38),UDim2.fromOffset(110,38),12,colors.muted)
text(units,"Display + @user",UDim2.new(1,-115,0,38),UDim2.fromOffset(104,38),11)
local settings=section(pages.settings,"Interface",0,0,114,"settings")
local raidMain=section(pages.raid,"Auto Raid",0,0,152,"raid")
toggle(raidMain,0,"raid","Enabled",function(enabled)
    if enabled then
        if game.GameId~=994732206 or not SEA_BY_PLACE[game.PlaceId] or SEA_BY_PLACE[game.PlaceId]==1 then
            status("Auto Raid requires Blox Fruits sea 2 or 3.");return false
        end
        teleport.cancel()
        if state.farm then stopFarm()end
        raidIndex,raidMarker,raidEmptyAt=0,nil,nil;raidMarkersAt=-math.huge;raidCachedMarkers={}
        combatProbe=nil;slotCharacter=nil;lastAttack=-math.huge
        auraRequestedCharacter=nil;auraStatus="pending"
        status("Auto Raid enabled; waiting for a started raid.")
    else stopRaid("Auto Raid stopped.")end
end)
divider(raidMain,38)
text(raidMain,"Search radius · studs",UDim2.fromOffset(14,38),UDim2.fromOffset(220,38),12,colors.muted)
local raidRadiusInput=create("TextBox",{Name="RaidRadius",Text=tostring(CONFIG.RaidRadius),ClearTextOnFocus=false,
    Font=Enum.Font.Gotham,TextSize=12,TextColor3=colors.text,BackgroundColor3=colors.input,
    BorderSizePixel=0,Position=UDim2.new(1,-66,0,44),Size=UDim2.fromOffset(53,26)},raidMain)
round(raidRadiusInput,5)
connect(raidRadiusInput.FocusLost,function()
    local amount=tonumber(raidRadiusInput.Text)
    if amount and amount==amount then CONFIG.RaidRadius=math.floor(math.clamp(amount,50,100))end
    raidRadiusInput.Text=tostring(CONFIG.RaidRadius)
end)
divider(raidMain,76)
text(raidMain,"Height above NPC",UDim2.fromOffset(14,76),UDim2.fromOffset(220,38),12,colors.muted)
text(raidMain,"61 studs",UDim2.new(1,-84,0,76),UDim2.fromOffset(70,38),11)
divider(raidMain,114)
toggle(raidMain,114,"dodge","Side dodge",function()dodge.reset()end)
local raidInfo=section(pages.raid,"Island progress",352,0,114,"stats")
text(raidInfo,"Island",UDim2.fromOffset(14,0),UDim2.fromOffset(160,38),12,colors.muted)
raidIslandLabel=text(raidInfo,"Waiting",UDim2.new(1,-95,0,0),UDim2.fromOffset(82,38),11)
divider(raidInfo,38)
text(raidInfo,"Weapon / Aura",UDim2.fromOffset(14,38),UDim2.fromOffset(160,38),12,colors.muted)
text(raidInfo,"From Auto Farm",UDim2.new(1,-120,0,38),UDim2.fromOffset(107,38),11)
divider(raidInfo,76)
text(raidInfo,"Next island",UDim2.fromOffset(14,76),UDim2.fromOffset(160,38),12,colors.muted)
text(raidInfo,"After clearing",UDim2.new(1,-115,0,76),UDim2.fromOffset(102,38),11)
local raidGuide=section(pages.raid,"Raid controls",704,0,220,"settings")
local raidHint=text(raidGuide,"Start a raid in-game, then enable Auto Raid.\n\nWeapon and Aura are selected on the Farm tab.\n\nHeight: 61 studs. Side dodge: 60 studs, skill cues only. Group attacks: 40 attempts/sec.\n\nAuto Farm pauses while this module runs.",
    UDim2.fromOffset(14,0),UDim2.new(1,-28,0,150),12,colors.muted)
raidHint.TextWrapped=true;raidHint.TextTruncate=Enum.TextTruncate.None
dodge.cueLabel=text(raidGuide,"Skill cue: waiting for NPC animation / casting state",UDim2.fromOffset(14,160),UDim2.new(1,-28,0,52),10,colors.dim)
dodge.cueLabel.TextWrapped=true;dodge.cueLabel.TextTruncate=Enum.TextTruncate.None
local statsMain=section(pages.stats,"Auto Stats",0,0,76,"stats")
toggle(statsMain,0,"stats","Enabled",function(enabled)
    if enabled then
        if game.GameId~=994732206 then statsStatus("Auto Stats is for Blox Fruits.");return false end
        statsLastTick=-math.huge;statsSchedule.index=0;statsSchedule.last={};statsSchedule.pending=nil;statsStatus("Auto Stats enabled.")
    else stopStats("Auto Stats stopped.")end
end)
divider(statsMain,38)
text(statsMain,"Available points",UDim2.fromOffset(14,38),UDim2.fromOffset(170,38),12,colors.muted)
statsPointsLabel=text(statsMain,"—",UDim2.new(1,-75,0,38),UDim2.fromOffset(65,38),11)
local statsAllocation=section(pages.stats,"Point allocation",352,0,190,"stats")
for i,rule in ipairs(STAT_RULES)do
    local y=(i-1)*38
    if i>1 then divider(statsAllocation,y)end
    text(statsAllocation,rule.label,UDim2.fromOffset(14,y),UDim2.fromOffset(180,38),12,colors.muted)
    local input=create("TextBox",{Name="Stat_"..rule.key,Text=tostring(rule.amount),ClearTextOnFocus=false,
        Font=Enum.Font.Gotham,TextSize=12,TextColor3=colors.text,BackgroundColor3=colors.input,
        BorderSizePixel=0,Position=UDim2.new(1,-66,0,y+6),Size=UDim2.fromOffset(53,26)},statsAllocation)
    round(input,5)
    connect(input.FocusLost,function()rule.amount=Core.statAmount(input.Text);input.Text=tostring(rule.amount)end)
end
local statsRules=section(pages.stats,"Allocation rules",704,0,180,"settings")
text(statsRules,"0  ·  Skip this stat",UDim2.fromOffset(14,0),UDim2.fromOffset(308,28),12,colors.muted)
text(statsRules,"1  ·  One point each second",UDim2.fromOffset(14,34),UDim2.fromOffset(308,28),12,colors.muted)
text(statsRules,"2  ·  Two points each second",UDim2.fromOffset(14,68),UDim2.fromOffset(308,28),12,colors.muted)
statsStatusLabel=text(statsRules,"Set the amount for each stat. Available points are allocated from top to bottom.",
    UDim2.fromOffset(14,112),UDim2.new(1,-28,0,65),11,colors.muted)
statsStatusLabel.TextWrapped=true;statsStatusLabel.TextTruncate=Enum.TextTruncate.None
text(settings,"Toggle menu",UDim2.fromOffset(14,0),UDim2.fromOffset(150,38),12,colors.muted)
text(settings,"Right Shift",UDim2.new(1,-87,0,0),UDim2.fromOffset(76,38),11)
divider(settings,38)
text(settings,"Attacks",UDim2.fromOffset(14,38),UDim2.fromOffset(180,38),12,colors.muted)
text(settings,"Until disabled",UDim2.new(1,-106,0,38),UDim2.fromOffset(95,38),11)
divider(settings,76)
text(settings,"Quest attempts",UDim2.fromOffset(14,76),UDim2.fromOffset(180,38),12,colors.muted)
text(settings,"3 max",UDim2.new(1,-62,0,76),UDim2.fromOffset(51,38),11)
local statusCard=create("Frame",{Name="StatusCard",BackgroundColor3=colors.panel,BorderSizePixel=0,
    Position=UDim2.fromOffset(contentX,WINDOW_HEIGHT-66),Size=UDim2.fromOffset(752,34)},window)
round(statusCard,12);create("UIStroke",{Color=colors.border,Transparency=.5,Thickness=1},statusCard)
local statusDot=create("Frame",{BackgroundColor3=colors.accent,BorderSizePixel=0,Position=UDim2.fromOffset(17,14),Size=UDim2.fromOffset(6,6)},statusCard)
round(statusDot,3)
statusLabel=text(statusCard,"Ready. "..CONFIG.WeaponType.." selected.",UDim2.fromOffset(36,0),UDim2.new(1,-52,0,34),11,colors.muted)
statusLabel.TextWrapped=true;statusLabel.TextTruncate=Enum.TextTruncate.None
text(window,BUILD.."  /  RIGHT SHIFT",UDim2.fromOffset(contentX,WINDOW_HEIGHT-26),UDim2.fromOffset(280,16),9,colors.dim)
connect(save.Activated,function()
    playerGui:SetAttribute("ViltrumWalkSpeed",CONFIG.WalkSpeed)
    playerGui:SetAttribute("ViltrumAutoAura",CONFIG.AutoAura)
    playerGui:SetAttribute("ViltrumWeaponType",CONFIG.WeaponType)
    playerGui:SetAttribute("ViltrumFruitSlot",CONFIG.FruitSlot)
    playerGui:SetAttribute("ViltrumFruitPercent",CONFIG.FruitPercent)
    for _,key in ipairs({"Z","X","C","V"})do playerGui:SetAttribute("ViltrumFruit"..key,CONFIG.FruitSkills[key])end
    playerGui:SetAttribute("ViltrumSwordSlot",CONFIG.SwordSlot)
    playerGui:SetAttribute("ViltrumRaidRadius",CONFIG.RaidRadius)
    playerGui:SetAttribute("ViltrumRaidDodge",state.dodge)
    for _,rule in ipairs(STAT_RULES)do playerGui:SetAttribute("ViltrumStat"..rule.key,rule.amount)end
    status("Settings saved for this client session.")
end)
updateCount()
appearance.refresh=function()
    updateAuraChoice();updateWeaponChoice()
    for id,b in pairs(tabButtons)do
        b:FindFirstChild("Caption").TextColor3=id==currentPage and colors.text or colors.muted
        for _,part in ipairs(b:FindFirstChild("Icon"):GetDescendants())do
            if part:IsA("Frame")then part.BackgroundColor3=id==currentPage and colors.accentText or colors.muted end
            if part:IsA("UIStroke")then part.Color=id==currentPage and colors.accentText or colors.muted end
        end
    end
end
ui.setTheme(playerGui:GetAttribute("BakaTheme")or "Dark")
do
    local accent=playerGui:GetAttribute("BakaAccent")
    if type(accent)=="string" and accent:match("^#%x%x%x%x%x%x$")then
        ui.setAccent(Color3.fromRGB(tonumber(accent:sub(2,3),16),tonumber(accent:sub(4,5),16),tonumber(accent:sub(6,7),16)))
    else
        ui.setAccent(colors.accent)
    end
end
ui.setLanguage(playerGui:GetAttribute("BakaLanguage")or "English")
setMenuVisible(true)
end
constructBakaUI()
end

do
local priceCore=(function()
local PriceCore={}
function PriceCore.plain(value)
    return tostring(value or ""):gsub("<[^>]*>",""):gsub("&amp;","&"):gsub("&nbsp;"," "):gsub("&#39;","'")
        :gsub("&quot;",'"'):gsub("^%s+",""):gsub("%s+$","")
end
function PriceCore.name(value)
    local name=PriceCore.plain(value):lower():gsub("%s+"," "):gsub(" fruit$","")
    if name=="lighting"then name="lightning"end
    return name
end
function PriceCore.category(value)
    local plain=PriceCore.plain(value):lower():gsub("%s+"," ")
    return plain=="blox fruit" or plain=="bloxfruit"
end
function PriceCore.parseValue(raw)
    local token=PriceCore.plain(raw):upper():gsub(",",""):gsub("%s","")
    local digits,suffix=token:match("^(%d+%.?%d*)([KMB]?)$")
    local number=tonumber(digits)
    if not number or number~=number then return nil end
    local amount=number*({K=1000,M=1000000,B=1000000000,[""]=1})[suffix]
    if amount<=0 or amount>1e15 then return nil end
    return {amount=amount,display=token}
end
function PriceCore.formatAmount(amount)
    local divisor,suffix=1,""
    if amount>=1000000000 then divisor,suffix=1000000000,"B"
    elseif amount>=1000000 then divisor,suffix=1000000,"M"
    elseif amount>=1000 then divisor,suffix=1000,"K"end
    return string.format("%.6f",amount/divisor):gsub("0+$",""):gsub("%.$","")..suffix
end
function PriceCore.parseHTML(html)
    if type(html)~="string" or #html>2000000 then return nil,"invalid response size"end
    local result,count={},0
    for name,after in html:gmatch('class=["\'][^"\']*cos%-unit%-card%-name[^"\']*["\'][^>]*>(.-)</div>()')do
        local nextCard=html:find('cos%-unit%-card%-name',after)
        local boundary=math.min(after+2000,nextCard and nextCard-1 or #html)
        local body=html:sub(after,boundary)
        local raw=body:match('Normal:%s*</span>%s*<span[^>]*>%s*([^<]+)')
        local price=raw and PriceCore.parseValue(raw)
        local key=PriceCore.name(name)
        if price and key~="" then result[key]=price;count+=1 end
    end
    if count<5 then return nil,"value list layout unavailable"end
    return result,count
end
return PriceCore

end)()
local priceData=(function()
-- Factual snapshot from the user-specified Game.Guide value list.
return {source="https://www.game.guide/blox-fruits-value-list",retrievedAt="2026-10-14T18:21:15.619Z",values={
    ["Eclipse Chromatic"]={amount=56500000000,display="56.50B"},
    ["Rabid Skin"]={amount=23000000000,display="23B"},
    ["DogHouse Frame Break"]={amount=16000000000,display="16B"},
    ["Vibes (Frame Break)"]={amount=15750000000,display="15.75B"},
    ["Galaxy Kitsune"]={amount=9810000000,display="9.81B"},
    ["Crimson Kitsune"]={amount=7570000000,display="7.57B"},
    ["Parrot Skin"]={amount=7150000000,display="7.15B"},
    ["Ember Dragon"]={amount=6300000000,display="6.30B"},
    ["Meme Fruit"]={amount=6250000000,display="6.25B"},
    ["Purple Lightning"]={amount=4830000000,display="4.83B"},
    ["Fruit Notifier"]={amount=4019999999.9999995,display="4.02B"},
    ["West Dragon"]={amount=3830000000,display="3.83B"},
    ["Arcsteel Magnet"]={amount=3440000000,display="3.44B"},
    ["East Dragon"]={amount=3270000000,display="3.27B"},
    ["Super Spirit Pain"]={amount=2610000000,display="2.61B"},
    ["Red Lightning"]={amount=2300000000,display="2.30B"},
    ["Runic Fiend"]={amount=2020000000,display="2.02B"},
    ["Divine portal"]={amount=1890000000,display="1.89B"},
    ["Dog Blade"]={amount=1700000000,display="1.70B"},
    ["Werewolf"]={amount=1180000000,display="1.18B"},
    ["Dark Blade"]={amount=1150000000,display="1.15B"},
    ["Fiend Yeti"]={amount=1080000000,display="1.08B"},
    ["3x Mythical Scroll"]={amount=1070000000.0000001,display="1.07B"},
    ["Magnet Fruit"]={amount=700000000,display="700M"},
    ["Celestial Pain"]={amount=642500000,display="642.50M"},
    ["5x Legendary Scroll"]={amount=620000000,display="620M"},
    ["Kitsune"]={amount=587500000,display="587.50M"},
    ["Sadness Pain"]={amount=565000000,display="565M"},
    ["Azura Bomb"]={amount=547500000,display="547.50M"},
    ["Frustration Pain"]={amount=547500000,display="547.50M"},
    ["Nuclear Bomb"]={amount=540000000,display="540M"},
    ["Thermite Bomb"]={amount=500000000,display="500M"},
    ["2x Mastery"]={amount=463750000,display="463.75M"},
    ["2x Money"]={amount=463750000,display="463.75M"},
    ["+1 Fruit Storage"]={amount=440000000,display="440M"},
    ["Starlight Gravity"]={amount=438330000,display="438.33M"},
    ["Matrix Eagle"]={amount=373330000,display="373.33M"},
    ["Yellow Lightning"]={amount=363750000,display="363.75M"},
    ["2x Boss Drops"]={amount=353750000,display="353.75M"},
    ["Fast Boats"]={amount=353750000,display="353.75M"},
    ["Green Lightning"]={amount=295000000,display="295M"},
    ["Rose Quartz Diamond"]={amount=270000000,display="270M"},
    ["Emerald Diamond"]={amount=187500000,display="187.50M"},
    ["Requiem Eagle"]={amount=168330000,display="168.33M"},
    ["Control"]={amount=150000000,display="150M"},
    ["Tiger"]={amount=137500000,display="137.50M"},
    ["Ruby Diamond"]={amount=135000000,display="135M"},
    ["Yeti"]={amount=127500000,display="127.50M"},
    ["Torment Pain"]={amount=123750000,display="123.75M"},
    ["Gas"]={amount=62500000,display="62.50M"},
    ["Lightning"]={amount=50000000,display="50M"},
    ["Topaz Diamond"]={amount=35000000,display="35M"},
    ["Dough"]={amount=31250000,display="31.25M"},
    ["Scarlet Ghost"]={amount=28330000,display="28.33M"},
    ["Venom"]={amount=22500000,display="22.50M"},
    ["T-Rex"]={amount=21250000,display="21.25M"},
    ["Glacier Eagle"]={amount=18330000,display="18.33M"},
    ["Stat Reset"]={amount=15000000,display="15M"},
    ["Buddha"]={amount=11250000,display="11.25M"},
    ["Celebration Bomb"]={amount=11250000,display="11.25M"},
    ["Portal"]={amount=11250000,display="11.25M"},
    ["Gravity"]={amount=10000000,display="10M"},
    ["Spirit"]={amount=10000000,display="10M"},
    ["Pain"]={amount=10000000,display="10M"},
    ["Lime Blade"]={amount=10000000,display="10M"},
    ["Mammoth"]={amount=9750000,display="9.75M"},
    ["Shadow"]={amount=6500000,display="6.50M"},
    ["Blizzard"]={amount=5250000,display="5.25M"},
    ["Phoenix"]={amount=2410000,display="2.41M"},
    ["Sound"]={amount=2370000,display="2.37M"},
    ["Creation"]={amount=2350000,display="2.35M"},
    ["Spider"]={amount=1500000,display="1.50M"},
    ["Love"]={amount=1360000,display="1.36M"},
    ["Magma"]={amount=1160000,display="1.16M"},
    ["Quake"]={amount=1000000,display="1M"},
    ["Diamond"]={amount=850000,display="850K"},
    ["Light"]={amount=825000,display="825K"},
    ["Ghost"]={amount=812500,display="812.5K"},
    ["Eagle"]={amount=750000,display="750K"},
    ["Rubber"]={amount=720000,display="720K"},
    ["Ice"]={amount=537500,display="537.5K"},
    ["Sand"]={amount=440000,display="440K"},
    ["Dark"]={amount=425000,display="425K"},
    ["Flame"]={amount=257500,display="257.5K"},
    ["Spike"]={amount=180000,display="180K"},
    ["Smoke"]={amount=100000,display="100K"},
    ["Bomb"]={amount=80000,display="80K"},
    ["Spring"]={amount=60000,display="60K"},
    ["Blade"]={amount=45000,display="45K"},
    ["Spin"]={amount=7500,display="7.5K"},
    ["Rocket"]={amount=5000,display="5K"},
}}

end)()
local makePrices=(function()
-- Inventory/trade presentation only. Fetches public HTML as data, never executes it.
return function(api)
    local Core=api.core
    local controller={label=api.label,running=false,request=nil,timeout=nil,lastAttempt=-math.huge,lastSuccess=-math.huge,generation=0}
    local values={};for name,price in pairs(api.snapshot.values)do values[Core.name(name)]=price end
    local records,categories,dirty,rootConnections={},{},{},{}
    local elapsed=0
    local tradeTitles={}
    local totalsDirty=true
    local totalLabels,visibilityWatches={},{}
    local function note(message)
        if controller.label and controller.label.Parent then controller.label.Text=message end
    end
    local function ignored(object)
        if object:IsDescendantOf(api.gui)then return true end
        local parent=object
        while parent and parent~=api.playerGui do
            if parent.Name=="ExperienceChat" or parent.Name=="Chat" or parent.Name=="BubbleChat"then return true end
            parent=parent.Parent
        end
        return false
    end
    local function markAll()
        for object in pairs(categories)do dirty[object]=true end
        totalsDirty=true
    end
    local function originalText(object)
        return records[object]and records[object].base or object.Text
    end
    local function isText(object)return object:IsA("TextLabel")or object:IsA("TextButton")end
    local function isTradeTitle(value)
        local title=Core.plain(value):lower():gsub("%s+"," ")
        return title=="treasure trade" or title=="fruit trade"
    end
    local function tradeContext(object)
        local parent=object.Parent
        while parent and parent~=api.playerGui do
            local name=parent.Name:lower():gsub("[^%a]","")
            if name=="trade" or name=="trading" or name=="treasuretrade" or name=="tradewindow"
                or name=="tradingwindow" or name=="tradegui"then return parent end
            for title in pairs(tradeTitles)do
                if title.Parent and not ignored(title)then
                    local root=title.Parent
                    for _=1,2 do
                        if not root or root==api.playerGui or root:IsA("LayerCollector")or root.Name=="Main"then break end
                        if root==parent then return parent end
                        root=root.Parent
                    end
                end
            end
            parent=parent.Parent
        end
        return false
    end
    local function restore(record)
        record.writing=true
        if record.object.Parent then
            if record.ours and record.object.Text==record.ours then record.object.Text=record.base end
            if record.originalScaled~=nil then record.object.TextScaled=record.originalScaled end
            if record.originalTruncate~=nil then record.object.TextTruncate=record.originalTruncate end
        end
        record.ours=nil;record.writing=false
        record.tradeSlot=nil;record.tradeKey=nil
    end
    local function findFruit(record)
        local parent=record.object.Parent
        for _=1,3 do
            if not parent or parent==api.playerGui or parent:IsA("LayerCollector")then return nil end
            if parent:IsA("GuiObject")then
                local names,categoryCount,imageCount,total={},0,0,0
                local declared=parent:GetAttribute("FruitName")
                if type(declared)=="string" and values[Core.name(declared)]then names[Core.name(declared)]=true end
                for _,child in ipairs(parent:GetDescendants())do
                    total+=1;if total>100 then break end
                    if child:IsA("ImageLabel")or child:IsA("ImageButton")then imageCount+=1 end
                    if isText(child)then
                        local plain=originalText(child)
                        if Core.category(plain)then categoryCount+=1 end
                        local key=Core.name(plain)
                        if child~=record.object and values[key]then names[key]=true end
                    end
                end
                local count,found=0,nil;for name in pairs(names)do count+=1;found=name end
                if categoryCount>1 then return nil end
                if total<=100 and categoryCount==1 and count==1 and (imageCount>0 or declared)then return found end
            end
            parent=parent.Parent
        end
        return nil
    end
    local function findTradeFruit(record)
        local key=Core.name(record.base)
        if not values[key]or not tradeContext(record.object)then return nil end
        local parent=record.object.Parent
        for _=1,3 do
            if not parent or parent==api.playerGui or parent:IsA("LayerCollector")then return nil end
            if parent:IsA("GuiObject")then
                local imageCount,knownLabels,costLabels,categoryCount,total=0,0,0,0,0
                for _,child in ipairs(parent:GetDescendants())do
                    total+=1;if total>60 then break end
                    if child:IsA("ImageLabel")or child:IsA("ImageButton")then imageCount+=1 end
                    if isText(child)then
                        local plain=Core.plain(originalText(child))
                        if values[Core.name(plain)]then knownLabels+=1 end
                        if Core.category(plain)then categoryCount+=1 end
                        if plain:match("^%$[%d,%.]+$")or plain:lower()=="special"then costLabels+=1 end
                    end
                end
                if total<=60 and categoryCount==0 and imageCount>=1 and knownLabels==1 and costLabels==1 then return key,parent end
                if knownLabels>1 or categoryCount>0 or costLabels>1 then return nil end
            end
            parent=parent.Parent
        end
        return nil
    end
    local function update(record)
        if not record.object.Parent then restore(record);return end
        if totalLabels[record.object]then return end
        local key,slot
        if Core.category(record.base)then key=findFruit(record)else key,slot=findTradeFruit(record)end
        record.tradeSlot=slot;record.tradeKey=slot and key or nil
        local price=key and values[key]
        if not price then restore(record);return end
        local desired=record.base.." · "..price.display
        record.writing=true
        if record.originalScaled==nil then record.originalScaled=record.object.TextScaled or false end
        if record.originalTruncate==nil then record.originalTruncate=record.object.TextTruncate end
        record.object.TextScaled=true;record.object.TextTruncate=Enum.TextTruncate.None
        record.ours=desired
        if record.object.Text~=desired then record.object.Text=desired end
        record.writing=false
    end
    local function visible(object)
        while object and object~=api.playerGui do
            if object:IsA("GuiObject")and object.Visible==false or object:IsA("LayerCollector")and object.Enabled==false then return false end
            object=object.Parent
        end
        return object==api.playerGui
    end
    local function watchVisibility(object)
        while object and object~=api.playerGui do
            if not visibilityWatches[object]then
                local property=object:IsA("GuiObject")and "Visible"or object:IsA("LayerCollector")and "Enabled"
                if property then
                    visibilityWatches[object]={object:GetPropertyChangedSignal(property):Connect(markAll),object:GetPropertyChangedSignal("Parent"):Connect(markAll)}
                end
            end
            object=object.Parent
        end
    end
    local function side(object,root)
        while object and object~=root do
            local name=object.Name:lower():gsub("[^%a%d]","")
            if name:find("left",1,true)or name:find("local",1,true)or name:find("your",1,true)or name:find("player1",1,true)then return 1 end
            if name:find("right",1,true)or name:find("other",1,true)or name:find("partner",1,true)or name:find("player2",1,true)then return 2 end
            object=object.Parent
        end
    end
    local function unknownSlot(record)
        local plain=Core.plain(record.base)
        if plain==""or Core.category(plain)or plain:match("^%$")or plain:lower()=="special"then return nil end
        local name=record.object.Name:lower():gsub("[^%a]","")
        if name~="name"and name~="itemname"and name~="fruitname"then return nil end
        local parent=record.object.Parent
        if not parent or not parent:IsA("GuiObject")then return nil end
        local images,costs,titles,categoriesFound=0,0,0,0
        local descendants=parent:GetDescendants();if #descendants>60 then return nil end
        for _,child in ipairs(descendants)do
            if child:IsA("ImageLabel")or child:IsA("ImageButton")then images+=1 end
            if isText(child)then
                local value=Core.plain(originalText(child))
                if Core.category(value)then categoriesFound+=1 end
                if value:match("^%$[%d,%.]+$")or value:lower()=="special"then costs+=1
                elseif value~=""then titles+=1 end
            end
        end
        if images>=1 and costs==1 and titles==1 and categoriesFound==0 then return parent end
    end
    local function rebuildTotals()
        local names={}
        if api.players then
            for _,player in ipairs(api.players:GetPlayers())do
                for _,name in ipairs({player.Name,player.DisplayName or player.Name})do names[Core.plain(name):lower()]=true end
            end
        end
        local groups={}
        for object,record in pairs(records)do
            if object.Parent then
                local base=Core.plain(record.base)
                local id=object.Name:lower():gsub("[^%a%d]","")
                local nick=names[base:lower()]or id=="player1"or id=="player2"or id=="leftname"or id=="rightname"or id=="username"or id=="playername"or id=="yourname"or id=="partnername"
                if record.tradeSlot or nick or id=="name"or id=="itemname"or id=="fruitname"then
                    local root=tradeContext(object)
                    if root then
                        groups[root]=groups[root]or {headers={},slots={}}
                        local group=groups[root]
                        local slot=record.tradeSlot or unknownSlot(record)
                        if slot then
                            watchVisibility(slot)
                            if visible(object)and visible(slot)then group.slots[slot]={object=slot,key=record.tradeKey,side=side(slot,root)}end
                        elseif nick and base~=""then
                            watchVisibility(object)
                            if visible(object)then group.headers[#group.headers+1]={record=record,side=side(object,root),center=object.AbsolutePosition.X+object.AbsoluteSize.X/2}end
                        end
                    end
                end
            end
        end
        local updated={}
        for root,group in pairs(groups)do
            if #group.headers==2 then
                local totals={0,0};local missing={0,0}
                for _,slot in pairs(group.slots)do
                    local chosen
                    if math.abs(group.headers[1].center-group.headers[2].center)>1 then
                        local center=slot.object.AbsolutePosition.X+slot.object.AbsoluteSize.X/2
                        chosen=math.abs(center-group.headers[1].center)<math.abs(center-group.headers[2].center)and 1 or 2
                    end
                    if not chosen and slot.side then for i,header in ipairs(group.headers)do if header.side==slot.side then chosen=i end end end
                    if not chosen then
                        for i,header in ipairs(group.headers)do
                            local parent=slot.object.Parent
                            while parent and parent~=root do
                                if header.record.object:IsDescendantOf(parent)then chosen=i;break end
                                parent=parent.Parent
                            end
                        end
                    end
                    if chosen then
                        local price=slot.key and values[slot.key]
                        if price then totals[chosen]+=price.amount else missing[chosen]+=1 end
                    else
                        missing[1]+=1;missing[2]+=1
                    end
                end
                for i,header in ipairs(group.headers)do
                    local record=header.record
                    local amount=Core.formatAmount(totals[i])
                    if missing[i]>0 then amount=totals[i]>0 and (amount.." + ?")or "?"end
                    local desired=record.base.." · "..amount
                    record.writing=true
                    if record.originalScaled==nil then record.originalScaled=record.object.TextScaled or false end
                    if record.originalTruncate==nil then record.originalTruncate=record.object.TextTruncate end
                    record.object.TextScaled=true;record.object.TextTruncate=Enum.TextTruncate.None;record.ours=desired
                    if record.object.Text~=desired then record.object.Text=desired end
                    record.writing=false;updated[record.object]=true
                end
            end
        end
        for object in pairs(totalLabels)do if not updated[object]and records[object]then restore(records[object])end end
        totalLabels=updated
    end
    function controller.flush()
        if not controller.running then return end
        local pending=dirty;dirty={}
        for object in pairs(pending)do if records[object]then update(records[object])end end
        if totalsDirty then totalsDirty=false;rebuildTotals()end
    end
    local function unwatch(object)
        local record=records[object]
        if not record then return end
        record.textConnection:Disconnect();record.parentConnection:Disconnect()
        restore(record);records[object]=nil;categories[object]=nil;dirty[object]=nil;tradeTitles[object]=nil;totalLabels[object]=nil
    end
    local function watch(object)
        if not isText(object)or records[object]or ignored(object)then return end
        local record={object=object,base=object.Text,writing=false}
        records[object]=record
        local function changed()
            if record.writing then return end
            local previous=record.base
            record.base=object.Text;record.ours=nil
            if isTradeTitle(record.base)then tradeTitles[object]=true else tradeTitles[object]=nil end
            if Core.category(record.base)or values[Core.name(record.base)]then categories[object]=true;dirty[object]=true
            else
                if categories[object]then restore(record)end
                categories[object]=nil;dirty[object]=nil
            end
            if values[Core.name(previous)]or values[Core.name(record.base)]or isTradeTitle(previous)or isTradeTitle(record.base)
                or Core.plain(previous):match("^%$")or Core.plain(record.base):match("^%$")
                or Core.plain(previous):lower()=="special"or Core.plain(record.base):lower()=="special"or tradeContext(object)then markAll()end
        end
        record.textConnection=object:GetPropertyChangedSignal("Text"):Connect(changed)
        record.parentConnection=object:GetPropertyChangedSignal("Parent"):Connect(markAll)
        if isTradeTitle(record.base)then tradeTitles[object]=true end
        if Core.category(record.base)or values[Core.name(record.base)]then categories[object]=true;dirty[object]=true end
    end
    local function cancelRequest()
        controller.generation+=1
        if controller.timeout then task.cancel(controller.timeout);controller.timeout=nil end
        if controller.request then task.cancel(controller.request);controller.request=nil end
    end
    local function fetch()
        local requester=request or http_request or syn and syn.request
        if type(requester)=="function"then
            local response=requester({Url=api.snapshot.source,Method="GET",Timeout=15,Headers={["Cache-Control"]="no-cache",Pragma="no-cache"}})
            if type(response)~="table"then error("unsupported HTTP response")end
            local code=tonumber(response.StatusCode or response.Status)
            if code and (code<200 or code>=300)then error("HTTP status rejected")end
            return response.Body or response.body
        end
        return game:HttpGet(api.snapshot.source)
    end
    function controller.refresh(manual)
        if not controller.running or controller.request then return false end
        local now=os.clock()
        if now-controller.lastAttempt<10 or not manual and (now-controller.lastAttempt<300 or now-controller.lastSuccess<300)then return false end
        controller.lastAttempt=now;controller.generation+=1
        local generation=controller.generation
        note("Updating · Game.Guide")
        controller.request=task.defer(function()
            local ok,html=pcall(fetch)
            if not controller.running or api.disposed()or generation~=controller.generation then return end
            local parsed=ok and Core.parseHTML(html)
            if parsed then
                for key,price in pairs(parsed)do values[key]=price end
                for object,record in pairs(records)do
                    if Core.category(record.base)or values[Core.name(record.base)]then categories[object]=true;dirty[object]=true end
                end
                controller.lastSuccess=os.clock();markAll();controller.flush();note("Game.Guide · Normal · updated")
            else note("Game.Guide · Normal · cached")end
            controller.request=nil
            if controller.timeout then task.cancel(controller.timeout);controller.timeout=nil end
        end)
        controller.timeout=task.delay(15,function()
            if generation~=controller.generation or not controller.request then return end
            cancelRequest();note("Game.Guide · Normal · cached")
        end)
        return true
    end
    function controller.set(enabled)
        if controller.running==enabled then return end
        controller.running=enabled
        if enabled then
            for _,object in ipairs(api.playerGui:GetDescendants())do watch(object)end
            table.insert(rootConnections,api.playerGui.DescendantAdded:Connect(function(object)
                if ignored(object)then return end
                watch(object)
                if object:IsA("ImageLabel")or object:IsA("ImageButton")or isText(object)then markAll()end
            end))
            table.insert(rootConnections,api.playerGui.DescendantRemoving:Connect(function(object)
                if ignored(object)then return end
                if visibilityWatches[object]then for _,connection in ipairs(visibilityWatches[object])do connection:Disconnect()end;visibilityWatches[object]=nil end
                unwatch(object);markAll()
            end))
            if api.players then
                table.insert(rootConnections,api.players.PlayerAdded:Connect(markAll));table.insert(rootConnections,api.players.PlayerRemoving:Connect(markAll))
            end
            table.insert(rootConnections,api.heartbeat:Connect(function(dt)
                elapsed+=dt;if elapsed<.15 then return end;elapsed=0;controller.flush();controller.refresh(false)
            end))
            controller.flush();note("Game.Guide · Normal · cached");controller.refresh(false)
        else
            cancelRequest()
            for _,connection in ipairs(rootConnections)do connection:Disconnect()end
            table.clear(rootConnections)
            local tracked={};for object in pairs(records)do tracked[#tracked+1]=object end
            for _,object in ipairs(tracked)do unwatch(object)end
            for _,watchers in pairs(visibilityWatches)do for _,connection in ipairs(watchers)do connection:Disconnect()end end
            table.clear(visibilityWatches);table.clear(totalLabels);totalsDirty=true
            table.clear(dirty);table.clear(categories);table.clear(tradeTitles);elapsed=0
            note("Game.Guide · Normal")
        end
    end
    return controller
end

end)()
fruitPrice=makePrices({core=priceCore,snapshot=priceData,players=Players,playerGui=playerGui,gui=gui,heartbeat=RunService.Heartbeat,label=fruitPrice.label,disposed=function()return disposed end})
end

do
    local function fruitOwner(object)
        local current,candidate=object,nil
        while current and current~=workspace do
            if current:IsA("Model")and current:FindFirstChildOfClass("Humanoid")then return nil end
            if current:IsA("Backpack")or current.Name=="Inventory" or current.Name=="Storage"then return nil end
            if current:IsA("Tool")or current:IsA("Model")then
                local named=current.Name:lower():match("fruit$")~=nil
                local declared=current:GetAttribute("FruitName")
                if current:GetAttribute("IsFruit")~=false and (named or current:GetAttribute("IsFruit")==true or type(declared)=="string" and declared~="")then
                    candidate=current
                end
            end
            current=current.Parent
        end
        if current==workspace and candidate then
            for _,player in ipairs(Players:GetPlayers())do
                local character=player.Character
                if character and (candidate==character or candidate:IsDescendantOf(character))then return nil end
            end
            return candidate
        end
        return nil
    end
    local function handle(owner)
        local part=owner and owner:FindFirstChild("Handle",true)
        return part and part:IsA("BasePart")and part or nil
    end
    local function remove(owner)
        local entry=fruitEsp.entries[owner]
        if entry then entry.gui:Destroy();fruitEsp.entries[owner]=nil end
    end
    local function consider(object)
        if not fruitEsp.running then return end
        local owner=fruitOwner(object)
        local part=handle(owner)
        if not part or fruitEsp.entries[owner]then return end
        local billboard=create("BillboardGui",{Name="ViltrumFruitESP",Size=UDim2.fromOffset(240,48),StudsOffsetWorldSpace=Vector3.new(0,2.5,0),
            ResetOnSpawn=false,AlwaysOnTop=true,Enabled=false,Adornee=part},gui)
        local label=text(billboard,"",UDim2.fromScale(0,0),UDim2.fromScale(1,1),13,Color3.fromRGB(255,190,100))
        label.TextXAlignment=Enum.TextXAlignment.Center;label.TextStrokeTransparency=.2
        label.TextStrokeColor3=Color3.new(0,0,0);label.TextTruncate=Enum.TextTruncate.None
        fruitEsp.entries[owner]={gui=billboard,label=label,part=part}
    end
    function fruitEsp.update()
        if not fruitEsp.running then return end
        local character=localPlayer.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        for owner,entry in pairs(fruitEsp.entries)do
            local part=handle(owner)
            if fruitOwner(owner)~=owner or not part then remove(owner)
            else
                entry.part=part;entry.gui.Adornee=part;entry.gui.Enabled=root~=nil
                local declared=owner:GetAttribute("FruitName")
                local name=type(declared)=="string"and declared~=""and declared or owner.Name
                if root then
                    local value=name.."\n"..math.floor((root.Position-part.Position).Magnitude+.5).." studs"
                    if entry.label.Text~=value then entry.label.Text=value end
                end
            end
        end
    end
    function fruitEsp.set(enabled)
        fruitEsp.running=enabled
        if enabled then
            for _,object in ipairs(workspace:GetDescendants())do consider(object)end
            fruitEsp.update()
        else
            for owner in pairs(fruitEsp.entries)do remove(owner)end
        end
    end
    connect(workspace.DescendantAdded,consider)
    connect(workspace.DescendantRemoving,function(object)
        if not fruitEsp.running then return end
        for owner,entry in pairs(fruitEsp.entries)do
            if owner==object or owner:IsDescendantOf(object)or entry.part==object or entry.part:IsDescendantOf(object)then remove(owner)end
        end
    end)
    local elapsed=0
    connect(RunService.Heartbeat,function(dt)
        if not fruitEsp.running then return end
        elapsed+=dt;if elapsed<.2 then return end;elapsed=0
        fruitEsp.update()
    end)
end
local function addPlayer(player)
    if player==localPlayer or tags[player] then return end
    local billboard=create("BillboardGui", {Name="Tag_"..player.UserId, Size=UDim2.fromOffset(260, 56),
        StudsOffsetWorldSpace=Vector3.new(0, 3, 0), ResetOnSpawn=false, Enabled=false}, gui)
    local label=text(billboard, "", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 14,Color3.fromRGB(255,255,255))
    label.TextXAlignment=Enum.TextXAlignment.Center; label.TextStrokeTransparency=.25
    label.TextStrokeColor3=Color3.new(0, 0, 0); label.TextTruncate=Enum.TextTruncate.None
    tags[player]={gui=billboard,label=label}
end
connect(Players.PlayerAdded, addPlayer)
connect(Players.PlayerRemoving, function(player)
    if tags[player] then tags[player].gui:Destroy(); tags[player]=nil end
end)
for _, player in ipairs(Players:GetPlayers()) do addPlayer(player) end
local visualElapsed=0
connect(RunService.Heartbeat, function(dt)
    if fruit.held then
        local held=fruit.held
        local human=held.target.Parent and held.target:FindFirstChildOfClass("Humanoid")
        if os.clock()>=held.untilTime or not human or human.Health<=0 then fruit.release()end
    end
    if mouseHeldBackend and os.clock()>=mouseHeldUntil then releaseNativeClick()end
    if (state.farm or state.raid and raidRunning) and hoverAlign and hoverRoot and hoverMob and hoverMob.Parent then
        local mobRoot=raidCombat.body(hoverMob)
        if mobRoot and mobRoot:IsA("BasePart") then
            local position=mobRoot.Position+(hoverOffset or Vector3.new(CONFIG.FarmSideOffset,FARM_HEIGHT,0))
            if (hoverAlign.Position-position).Magnitude>.05 then hoverAlign.Position=position end
        end
    end
    visualElapsed+=dt
    if visualElapsed<.1 then return end
    visualElapsed=0
    local character=localPlayer.Character
    local origin=character and character:FindFirstChild("HumanoidRootPart")
    for player, tag in pairs(tags) do
        local c=player.Character
        local head=c and c:FindFirstChild("Head")
        local root=c and c:FindFirstChild("HumanoidRootPart")
        tag.gui.Enabled=(state.names or state.distance) and head~=nil and root~=nil
            and (not state.distance or origin~=nil)
        tag.gui.Adornee=head; tag.gui.AlwaysOnTop=state.walls
        if tag.gui.Enabled then
            local lines={}
            if state.names then table.insert(lines, player.DisplayName.." (@"..player.Name..")") end
            if state.distance then table.insert(lines, string.format("%d studs", math.floor((origin.Position-root.Position).Magnitude+.5))) end
            local value=table.concat(lines,"\n")
            if tag.label.Text~=value then tag.label.Text=value end
        end
    end
end)
connect(RunService.PreSimulation,function()
    speedHack.tick()
    if (state.farm or state.raid and raidRunning or teleport.flight) and localPlayer.Character then disableCollisions(localPlayer.Character) end
end)

local function moveTo(root, destination)
    if movement and movingRoot==root and movementDestination
        and (movementDestination-destination).Magnitude<2
        and movement.PlaybackState==Enum.PlaybackState.Playing then return end
    stopMovement()
    local distance=(root.Position-destination).Magnitude
    movementDestination, movingRoot=destination, root
    movement=TweenService:Create(root, TweenInfo.new(math.max(.1, distance/CONFIG.TravelSpeed), Enum.EasingStyle.Linear),
        {CFrame=CFrame.new(destination) * root.CFrame.Rotation})
    movement:Play()
end
local inventorySummary
local function findWeapon(character,mode)
    mode=mode or CONFIG.WeaponType
    local backpack=localPlayer:FindFirstChild("Backpack")
    local fallback,count=nil,0
    for _, container in ipairs({character, backpack}) do
        if container then for _, tool in ipairs(container:GetChildren())do
            if tool:IsA("Tool")then
                local category=tool:GetAttribute("WeaponType") or tool:GetAttribute("Category") or tool:GetAttribute("Type")
                if Core.weaponMatches(mode,tool.Name,tool.ToolTip,category)then
                    if container==character then return tool end
                    fallback=tool;count+=1
                end
            end
        end end
    end
    -- GetChildren order is not hotbar order. Only a unique matching Tool is an unambiguous fallback.
    return count==1 and fallback or nil
end
local function initializeInput()
    if not slotInputInitialized then
        slotInputInitialized=true
        local ok,input=pcall(function()return UserInputService:CreateVirtualInput()end)
        if ok and input then
            table.insert(slotInputBackends,{name="VirtualInput",send=function(down,key)input:SendKey(down,key,false)end,
                mouse=function(down,point)input:SendMouseButton(point,Enum.UserInputType.MouseButton1,down,0)end,
                aim=function(point)
                    if not pcall(function()input:SendMousePosition(point)end)then
                        input:SendMouseDelta(point-UserInputService:GetMouseLocation())
                    end
                end})
        end
        -- Optional legacy API; ordinary LocalScripts may not have access.
        local legacyOk,legacy=pcall(function()return game:GetService("VirtualInputManager")end)
        if legacyOk and legacy then
            table.insert(slotInputBackends,{name="legacy input",send=function(down,key)legacy:SendKeyEvent(down,key,false,game)end,
                mouse=function(down,point)legacy:SendMouseButtonEvent(point.X,point.Y,0,down,game,0)end,
                aim=function(point)legacy:SendMouseMoveEvent(point.X,point.Y,game)end})
        end
    end
end
local function pressFirstSlot(mode)
    initializeInput()
    local keys={Enum.KeyCode.One,Enum.KeyCode.Two,Enum.KeyCode.Three,Enum.KeyCode.Four,Enum.KeyCode.Five,
        Enum.KeyCode.Six,Enum.KeyCode.Seven,Enum.KeyCode.Eight,Enum.KeyCode.Nine,Enum.KeyCode.Zero}
    local key=keys[mode=="Melee" and 1 or mode=="Fruit" and CONFIG.FruitSlot or CONFIG.SwordSlot]
    for _,backend in ipairs(slotInputBackends)do
        local downOk=pcall(backend.send,true,key)
        local upOk=pcall(backend.send,false,key) -- always release, even when key-down failed
        if not upOk then pcall(backend.send,false,key)end
        if downOk and upOk then return true,backend.name end
    end
    return false,"input unavailable"
end
local function prepareFirstSlot(character,humanoid,now,mode)
    mode=mode or (CONFIG.WeaponType=="Fruit" and (fruit.target and "Fruit" or "Melee") or CONFIG.WeaponType)
    if slotCharacter~=character or slotMode~=mode then
        releaseNativeClick();deactivateWeapon()
        slotCharacter=character;slotMode=mode;slotLastKey,slotLastEquip,slotWaitUntil=-math.huge,-math.huge,0
    end
    local weapon=findWeapon(character,mode)
    if weapon and weapon.Parent==character then return weapon end
    local focusOk,focused=pcall(function()return UserInputService:GetFocusedTextBox()end)
    local slot=mode=="Melee" and 1 or mode=="Fruit" and CONFIG.FruitSlot or CONFIG.SwordSlot
    local prefix="Slot "..slot.." ("..mode.."): "
    if focusOk and focused then return nil,prefix.."finish typing before equipping."end
    if now<slotWaitUntil then return nil,prefix.."waiting for selection…"end
    if now-slotLastKey>=1 then
        slotLastKey=now
        local sent,source=pressFirstSlot(mode)
        if sent then
            slotWaitUntil=now+.15
            local selected=findWeapon(character,mode)
            if selected and selected.Parent==character then return selected end
            return nil,prefix.."key sent via "..source.."; waiting for weapon…"
        end
    end
    -- If virtual input is unavailable or ignored, equip only a unique recognized Melee.
    weapon=findWeapon(character,mode)
    if weapon and now-slotLastEquip>=1 then
        slotLastEquip=now
        pcall(function()humanoid:EquipTool(weapon)end)
        if weapon.Parent==character then return weapon end
    end
    return nil,prefix.."selection not confirmed. Inventory: "..inventorySummary(character)
end
function fruit.cast(weapon,target,now)
    if not target.model.Parent or target.humanoid.Health<=0 or weapon.Parent~=localPlayer.Character then fruit.release();return "Target changed"end
    local focusOk,focused=pcall(function()return UserInputService:GetFocusedTextBox()end)
    local menuOk,menu=pcall(function()return game:GetService("GuiService").MenuIsOpen end)
    if (focusOk and focused)or(menuOk and menu)then fruit.release();return "Finish typing / close Roblox menu"end
    if fruit.held or now-fruit.lastCast<1 then return "Fruit: waiting for next cast"end
    local keys={"Z","X","C","V"}
    local selected
    for _=1,4 do fruit.index=fruit.index%4+1;if CONFIG.FruitSkills[keys[fruit.index]]then selected=keys[fruit.index];break end end
    if not selected then fruit.target=nil;return "Fruit: select Z / X / C / V"end
    local camera=workspace.CurrentCamera
    local ok,point,visible=pcall(function()return camera:WorldToViewportPoint(target.part.Position)end)
    if not ok or not visible or point.Z<=0 then return "Fruit: target must be on screen for aiming"end
    initializeInput();releaseNativeClick()
    for _,backend in ipairs(slotInputBackends)do
        if pcall(backend.aim,Vector2.new(point.X,point.Y))then
            local key=Enum.KeyCode[selected]
            fruit.held={backend=backend,key=key,untilTime=now+.15,target=target.model}
            if pcall(backend.send,true,key)then fruit.lastCast=now;return weapon.Name.." · Fruit "..selected.." · HP "..math.ceil(target.humanoid.Health)end
            if not fruit.release()then return "Fruit: key release failed"end
        end
    end
    return "Fruit: aiming / key input unavailable"
end
inventorySummary=function(character)
    local names={}
    for _, container in ipairs({character, localPlayer:FindFirstChild("Backpack")}) do
        if container then for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") and #names<4 then table.insert(names, item.Name.." ["..tostring(item.ToolTip).."]") end
        end end
    end
    return #names>0 and table.concat(names, ", ") or "no tools in Character/Backpack"
end
local function nativeClickPosition()
    local camera=workspace.CurrentCamera
    if not camera then return nil end
    local viewport=camera.ViewportSize
    local function safe(point)
        if point.X<12 or point.X>viewport.X-12 or point.Y<40 or point.Y>viewport.Y-12 then return false end
        if window.Visible then
            local p,s=window.AbsolutePosition,window.AbsoluteSize
            if point.X>=p.X and point.X<=p.X+s.X and point.Y>=p.Y and point.Y<=p.Y+s.Y then return false end
        end
        local ok,widgets=pcall(function()return playerGui:GetGuiObjectsAtPosition(point.X,point.Y)end)
        if not ok then return false end
        for _,widget in ipairs(widgets)do
            if widget:IsA("GuiButton") or widget:IsA("TextBox") or widget.Active then return false end
        end
        return true
    end
    if nativeClickPoint and safe(nativeClickPoint)then return nativeClickPoint end
    for _,uv in ipairs({{.85,.55},{.65,.8},{.2,.5},{.5,.25},{.85,.8},{.15,.75}})do
        local point=Vector2.new(viewport.X*uv[1],viewport.Y*uv[2])
        if safe(point)then nativeClickPoint=point;return point end
    end
    nativeClickPoint=nil
end
local function nativeAttack(weapon,now,holdSeconds)
    if mouseHeldBackend then
        if now>=mouseHeldUntil then releaseNativeClick()end
        if mouseHeldBackend then return nil,"waiting for mouse release"end
    end
    local point=nativeClickPosition()
    if point then
        initializeInput()
        for _,backend in ipairs(slotInputBackends)do
            local ok=pcall(backend.mouse,true,point)
            if ok then
                mouseHeldBackend,mouseHeldPoint,mouseHeldUntil=backend,point,now+(holdSeconds or .04)
                return "M1 · "..backend.name
            end
            pcall(backend.mouse,false,point)
        end
    end
    weapon:Deactivate();weapon:Activate()
    return "Tool fallback"
end
function raidCombat.primeMelee(weapon,now)
    if raidCombat.meleeWeapon==weapon and now-(raidCombat.meleeAt or -math.huge)<.1 then return nil end
    raidCombat.meleeWeapon=weapon;raidCombat.meleeAt=now
    local ok,backend=pcall(nativeAttack,weapon,now,.015)
    return ok and backend or nil
end
local function attackTarget(weapon, target, requiredMob,mode,now)
    if requiredMob and Core.normalizeName(target.name)~=Core.normalizeName(requiredMob)then return nil end
    local focusOk,focused=pcall(function()return UserInputService:GetFocusedTextBox()end)
    local menuOk,menuOpen=pcall(function()return game:GetService("GuiService").MenuIsOpen end)
    if focusOk and focused or menuOk and menuOpen then return nil,"close text input/menu to attack"end
    if mode=="Native"then return nativeAttack(weapon,now)end
    local part=target.model:FindFirstChild("Head") or target.part
    local modules=ReplicatedStorage:FindFirstChild("Modules")
    local net=modules and modules:FindFirstChild("Net")
    local registerAttack=net and net:FindFirstChild("RE/RegisterAttack")
    local registerHit=net and net:FindFirstChild("RE/RegisterHit")
    if registerAttack and registerHit and registerAttack:IsA("RemoteEvent") and registerHit:IsA("RemoteEvent") then
        -- One nearby NPC only. Never include other players in the hit list.
        local ok=pcall(function()
            registerAttack:FireServer(ATTACK_INTERVAL)
            registerHit:FireServer(part, {{target.model, part}})
        end)
        if ok then return "Net"end
        if combatProbe then combatProbe.mode="Native"end
    end
    return nativeAttack(weapon,now)
end
function raidCombat.hits(list,root,markers,requiredMob)
    local hits,seen={},{}
    local enemies=workspace:FindFirstChild("Enemies")
    local playerCharacters={}
    for _,player in ipairs(Players:GetPlayers())do if player.Character then playerCharacters[player.Character]=true end end
    for _,candidate in ipairs(list)do
        local model=candidate.model
        if model.Parent==enemies and not seen[model] and not playerCharacters[model]
            and (not requiredMob or Core.normalizeName(model.Name)==Core.normalizeName(requiredMob))then
            local humanoid=model:FindFirstChildOfClass("Humanoid")
            local body=raidCombat.body(model)
            local part=raidCombat.hitPart(model)
            if humanoid and humanoid.Health>0 and body and part and (body.Position-root.Position).Magnitude<=(markers and CONFIG.RaidRadius or CONFIG.FarmRadius) then
                local owner,nearest=markers and 0 or raidIndex,CONFIG.RaidIslandRadius
                for index,marker in pairs(markers or {})do
                    if marker.Parent then
                        local distance=(body.Position-marker.Position).Magnitude
                        if distance<nearest then owner,nearest=index,distance end
                    end
                end
                if owner==raidIndex then seen[model]=true;table.insert(hits,{model,part})end
            end
        end
    end
    table.sort(hits,function(a,b)return (a[2].Position-root.Position).Magnitude<(b[2].Position-root.Position).Magnitude end)
    return hits
end
function raidCombat.attack(weapon,list,root,markers,mode,now,requiredMob,scopeCheck)
    local farm=markers==nil
    local function ready()
        local humanoid=localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
        return not disposed and (farm and state.farm or not farm and state.raid and raidRunning) and humanoid and humanoid.Health>0
            and (farm or not raidCombat.timer or raidCombat.timer()) and (not scopeCheck or scopeCheck())
            and root.Parent==localPlayer.Character and weapon.Parent==localPlayer.Character and weapon.Enabled~=false
    end
    if not ready()then releaseNativeClick();return nil,"Combat/weapon no longer ready"end
    local focusOk,focused=pcall(function()return UserInputService:GetFocusedTextBox()end)
    local menuOk,menu=pcall(function()return game:GetService("GuiService").MenuIsOpen end)
    if (focusOk and focused)or(menuOk and menu)then releaseNativeClick();return nil,"close text input/menu to attack"end
    local hits=raidCombat.hits(list,root,markers,requiredMob)
    if #hits==0 then return nil,"No current eligible nearby NPCs"end
    if mode=="Native"then return nativeAttack(weapon,now,.015)end
    local modules=ReplicatedStorage:FindFirstChild("Modules")
    local net=modules and modules:FindFirstChild("Net")
    local registerAttack=net and net:FindFirstChild("RE/RegisterAttack")
    local registerHit=net and net:FindFirstChild("RE/RegisterHit")
    if registerAttack and registerHit and registerAttack:IsA("RemoteEvent") and registerHit:IsA("RemoteEvent")then
        local meleePulse
        if farm and slotMode=="Melee"then
            meleePulse=raidCombat.primeMelee(weapon,now)
            if not ready()then releaseNativeClick();return nil,"Combat changed during Melee activation"end
        end
        local sent=false
        local ok=pcall(function()
            registerAttack:FireServer(RAID_ATTACK_INTERVAL)
            if not ready()then return end
            hits=raidCombat.hits(list,root,markers,requiredMob) -- moving, ragdolled, replaced or dead parts may have changed
            if #hits==0 then return end
            registerHit:FireServer(hits[1][2],hits);sent=true
        end)
        if ok then return sent and ("Net · "..#hits.." NPCs"..(meleePulse and " · M1"or "")) or nil,"Targets changed before hit"end
        if combatProbe then combatProbe.mode="Native"end
    end
    if not ready()then return nil,"Raid stopped"end
    return nativeAttack(weapon,now,.015)
end
local function widgetVisible(node)
    local current=node
    while current and current~=playerGui do
        if current.Name=="ViltrumModules" or current.Name=="ExperienceChat"
            or current.Name=="Chat" or current.Name=="BubbleChat" or current.Name=="PlayerList"then return false end
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("LayerCollector") and current.Enabled==false then return false end
        current=current.Parent
    end
    return current==playerGui
end
local function isTextWidget(node)
    return node:IsA("TextLabel") or node:IsA("TextButton")
end
local questLabel,questCounter,questDescriptors=nil,nil,{}
local questDiscoveryAt=-math.huge
local questGuiDirty=true
local function markQuestDirty(node)
    if not isTextWidget(node)then return end
    local current=node
    while current and current~=playerGui do
        if current.Name=="ViltrumModules" or current.Name=="ExperienceChat" or current.Name=="Chat"then return end
        current=current.Parent
    end
    questGuiDirty=true
end
connect(playerGui.DescendantAdded,markQuestDirty)
connect(playerGui.DescendantRemoving,markQuestDirty)
local function readObjective(label,counter)
    if not label or not counter or not label.Parent or not counter.Parent then return nil end
    if not widgetVisible(label) or not widgetVisible(counter)then return nil end
    local title=label.Text
    local count=tonumber(Core.normalizeName(title):match("^defeat%s+(%d+)%s+"))
    local done,total=Core.normalizeName(counter.Text):match("^(%d+)%s*/%s*(%d+)$")
    if count and tonumber(total)==count and tonumber(done)<=count then return title,tonumber(done)>=count end
end
local function questUI()
    local currentTitle,currentComplete=readObjective(questLabel,questCounter)
    if currentTitle then return true,currentTitle,currentComplete,"cached objective+counter"end
    for _,pair in ipairs(questDescriptors)do
        local title,complete=readObjective(pair[1],pair[2])
        if title then questLabel,questCounter=pair[1],pair[2];return true,title,complete,"cached objective+counter"end
    end
    local now=os.clock()
    if questGuiDirty or now-questDiscoveryAt>=1 then
        questGuiDirty=false;questDiscoveryAt=now;questDescriptors={}
    -- Read the real visible objective; Main.Quest can be a hidden legacy widget.
    for _,label in ipairs(playerGui:GetDescendants())do
        if isTextWidget(label) and widgetVisible(label)then
            local title=label.Text
            local count=tonumber(Core.normalizeName(title):match("^defeat%s+(%d+)%s+"))
            if count then
                local ancestor=label.Parent
                for _=1,3 do
                    if not ancestor or ancestor==playerGui or ancestor:IsA("LayerCollector")then break end
                    for _,counter in ipairs(ancestor:GetDescendants())do
                        if isTextWidget(counter) and widgetVisible(counter)then
                            local done,total=Core.normalizeName(counter.Text):match("^(%d+)%s*/%s*(%d+)$")
                            if tonumber(total)==count and tonumber(done)<=count then
                                questLabel,questCounter=label,counter
                                table.insert(questDescriptors,{label,counter})
                                return true,title,tonumber(done)>=count,"objective+counter"
                            end
                        end
                    end
                    ancestor=ancestor.Parent
                end
            end
        end
    end
    end
    local main=playerGui:FindFirstChild("Main")
    local quest=main and main:FindFirstChild("Quest")
    if not quest then return nil,nil,false,"panel missing"end
    if not widgetVisible(quest)then return false,nil,false,"legacy panel hidden"end
    local titleContainer=quest:FindFirstChild("QuestTitle", true)
    local title=titleContainer and (titleContainer:IsA("TextLabel") and titleContainer or titleContainer:FindFirstChild("Title", true))
    if title and isTextWidget(title) then return true,title.Text,false,"legacy title"end
    return true,nil,false,"legacy title missing"
end
local QUEST_NPC_NAMES = {Area1Quest="Area 1 Quest Giver", Area2Quest="Area 2 Quest Giver"}
local function questNpcPosition(quest)
    local folder=workspace:FindFirstChild("NPCs")
    if folder then
        for _, npc in ipairs(folder:GetChildren()) do
            local matches=npc.Name==QUEST_NPC_NAMES[quest[2]] or npc:GetAttribute("QuestId")==quest[2]
                or npc:GetAttribute("QuestName")==quest[2]
            if matches then
                local part=npc:IsA("BasePart") and npc or npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
                if part and part:IsA("BasePart") then return part.Position end
            end
        end
    end
    return Vector3.new(quest[5], quest[6], quest[7])
end
local function candidates(root)
    local list={}
    local folder=workspace:FindFirstChild("Enemies")
    if not folder then return nil end
    for _, mob in ipairs(folder:GetChildren()) do
        if mob:IsA("Model") then
            local humanoid=mob:FindFirstChildOfClass("Humanoid")
            local part=raidCombat.body(mob)
            if humanoid and part and part:IsA("BasePart") then
                table.insert(list, {model=mob, humanoid=humanoid, part=part, name=mob.Name,
                    health=humanoid.Health,maxHealth=humanoid.MaxHealth, distance=(part.Position-root.Position).Magnitude})
            end
        end
    end
    return list
end
local function spawnPoints(quest)
    if not quest then return {}, "none" end
    local origin=workspace:FindFirstChild("_WorldOrigin")
    local folder=origin and origin:FindFirstChild("EnemySpawns") or workspace:FindFirstChild("EnemySpawns")
    local points={}
    if folder then
        for _,part in ipairs(folder:GetDescendants())do
            if part:IsA("BasePart") and Core.normalizeName(part.Name)==Core.normalizeName(quest[4]) then
                table.insert(points,part.Position)
            end
        end
    end
    if #points>0 then return points,"live" end
    local fallback=FARM_AREAS[quest[2]..":"..quest[3]]
    if fallback then return {Vector3.new(fallback[1],fallback[2],fallback[3])},"reference" end
    return {},"none"
end
local function approachSpawn(root,quest,now)
    local points,source=spawnPoints(quest)
    if #points==0 then return false end
    local key=quest[2]..":"..quest[3]..":"..source
    if spawnRouteKey~=key then
        spawnRouteKey,spawnRoutePoints,spawnRouteIndex,spawnArrivedAt=key,points,1,nil
        local nearest=math.huge
        for i,p in ipairs(points)do
            local distance=(root.Position-p).Magnitude
            if distance<nearest then spawnRouteIndex,nearest=i,distance end
        end
    end
    local position=spawnRoutePoints[spawnRouteIndex]+Vector3.new(CONFIG.FarmSideOffset,FARM_HEIGHT,0)
    if (position-root.Position).Magnitude<=CONFIG.PositionTolerance then
        spawnArrivedAt=spawnArrivedAt or now
        if #spawnRoutePoints>1 and now-spawnArrivedAt>=CONFIG.SpawnWait then
            spawnRouteIndex=spawnRouteIndex%#spawnRoutePoints+1;spawnArrivedAt=nil
            position=spawnRoutePoints[spawnRouteIndex]+Vector3.new(CONFIG.FarmSideOffset,FARM_HEIGHT,0)
        end
    else spawnArrivedAt=nil end
    stopMovement();holdPosition(root,position,nil)
    status("Searching "..quest[4].." · spawn "..spawnRouteIndex.."/"..#spawnRoutePoints.." · "..source)
    return true
end
local function combatPosition(weapon,target,now,sideOffset)
    combatProbe=Core.updateFixedCombatProbe(combatProbe,weapon,target.model,target.health,now)
    local height=FARM_HEIGHT
    if combatProbe.progress then learnedHeights[weapon]={heightIndex=combatProbe.heightIndex,mode=combatProbe.mode}end
    return target.part.Position+Vector3.new(sideOffset or CONFIG.FarmSideOffset,height,0),height
end
local function farmStep()
    local character=localPlayer.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local root=character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health<=0 or not root then
        releaseNativeClick();combatProbe=nil;stopMovement();stopHover();status("Waiting for your character…");return
    end
    disableCollisions(character)
    ensureAura(character)
    if movingRoot and movingRoot~=root then stopMovement() end
    local now=os.clock()
    if CONFIG.WeaponType=="Fruit" and not fruit.skillsSelected()then
        releaseNativeClick();stopMovement();holdPosition(root,root.Position,nil);status("Fruit: select skills Z / X / C / V before farming.");return
    end
    local weapon,equipStatus
    if CONFIG.WeaponType~="Fruit"then weapon,equipStatus=prepareFirstSlot(character,humanoid,now)end
    if CONFIG.WeaponType~="Fruit" and not weapon then
        stopMovement();holdPosition(root,root.Position,nil)
        status(equipStatus);return
    end
    local sea=SEA_BY_PLACE[game.PlaceId]
    local data=localPlayer:FindFirstChild("Data")
    local level=data and data:FindFirstChild("Level")
    local visible,title,questComplete,questSource=questUI()
    if state.quests and visible==nil then stopFarm("Quest UI not found. This game build needs an adapter update."); return end
    if visible and questComplete then
        releaseNativeClick();fruit.target=nil
        stopMovement();holdPosition(root,root.Position,nil)
        status("Quest complete; waiting for the objective to disappear…");return
    end
    local bossQuest=visible and Core.isBossQuest(title,BOSS_NAMES)
    local quest=state.quests and Core.selectQuest(QUESTS[sea], level and level.Value, sea) or nil
    if visible and not bossQuest then
        quest=Core.activeQuest(QUESTS[sea],title)
        if not quest then
            stopFarm("Active quest is not recognized; keeping it. Title: "..tostring(title));return
        end
        questAttempts=0
    end
    if visible and bossQuest and not state.quests then
        status("Boss quest active. Enable Auto Quests to cancel it and choose a normal quest.");return
    end
    if not visible then bossAttempts=0 end
    if state.quests and not quest and not bossQuest then stopFarm("No eligible quest in the source snapshot for this sea/level."); return end
    local npc=quest and questNpcPosition(quest) or nil
    local list=candidates(root)
    if not list then stopFarm("workspace.Enemies not found. This game build needs an adapter update."); return end
    local target=Core.nearestTarget(list, quest and quest[4] or nil)
    local attackMode=fruit.mode(target)
    weapon,equipStatus=prepareFirstSlot(character,humanoid,now,attackMode)
    if not weapon then holdPosition(root,root.Position,nil);status(equipStatus);return end
    local farmPosition,height=nil,FARM_HEIGHT
    if target then
        if attackMode=="Fruit"then
            height=FARM_HEIGHT;farmPosition=target.part.Position+Vector3.new(CONFIG.FarmSideOffset,height,0)
        else farmPosition,height=combatPosition(weapon,target,now);fruit.height=height end
    end
    if state.quests and visible and title and Core.questMatches(title, quest[4]) then questAttempts=0 end
    local action=Core.decide({enabled=state.farm,alive=true,autoQuest=state.quests,quest=quest,
        questVisible=visible,questTitle=title,npcDistance=npc and (npc-root.Position).Magnitude or 0,
        questBoss=bossQuest,
        questRange=CONFIG.QuestRange,now=now,lastQuest=lastQuest,questCooldown=CONFIG.QuestCooldown,
        target=target,attackRange=CONFIG.FarmRadius,hasWeapon=weapon~=nil,
        positionDistance=nil,
        positionTolerance=CONFIG.PositionTolerance,
        lastAttack=lastAttack,attackCooldown=ATTACK_INTERVAL-1e-6})
    if action=="wrong_quest" or action=="unknown_quest" then
        stopFarm("Finish/cancel the current quest manually, then restart Auto Farm.")
    elseif action=="abandon_boss" then
        stopMovement();holdPosition(root,root.Position,nil)
        if questRequest then status("Waiting for boss quest cancellation…");return end
        if now-lastAbandon<CONFIG.QuestCooldown then status("Waiting for boss quest to disappear…");return end
        if bossAttempts>=3 then stopFarm("Boss quest cancellation was not confirmed after 3 attempts.");return end
        local remotes=ReplicatedStorage:FindFirstChild("Remotes")
        local remote=remotes and remotes:FindFirstChild("CommF_")
        if not remote or not remote:IsA("RemoteFunction")then stopFarm("AbandonQuest RemoteFunction not found.");return end
        lastAbandon=now;bossAttempts+=1;status("Cancelling boss quest…")
        local requestThread
        requestThread=task.defer(function()
            local ok,result=pcall(function()return remote:InvokeServer("AbandonQuest")end)
            if questRequest==requestThread then
                questRequest=nil
                if questTimer then task.cancel(questTimer);questTimer=nil end
                if state.farm and not ok then stopFarm("AbandonQuest failed: "..tostring(result))end
            end
        end)
        questRequest=requestThread
        questTimer=task.delay(8,function()
            questTimer=nil
            if questRequest==requestThread then stopFarm("AbandonQuest response timed out after 8 seconds.")end
        end)
    elseif action=="move_npc" then
        stopMovement()
        status("Quest NPC: "..quest[2]);holdPosition(root,npc+Vector3.new(0,2,0),nil)
    elseif action=="start_quest" then
        stopMovement()
        holdPosition(root,npc+Vector3.new(0,2,0),nil)
        if questRequest then status("Waiting for quest response…"); return end
        if questAttempts>=3 then
            stopFarm("Quest unconfirmed: "..quest[2].."/"..quest[3].." · UI="..questSource.." · Reply="..lastQuestReply)
            return
        end
        local remotes=ReplicatedStorage:FindFirstChild("Remotes")
        local remote=remotes and remotes:FindFirstChild("CommF_")
        if not remote or not remote:IsA("RemoteFunction") then stopFarm("StartQuest RemoteFunction not found."); return end
        lastQuest=now; questAttempts+=1; status("Requesting quest: "..quest[4])
        local requestThread
        -- defer allows the thread handle to be set before the callback runs.
        requestThread=task.defer(function()
            local ok, result=pcall(function() return remote:InvokeServer("StartQuest", quest[2], quest[3]) end)
            if questRequest==requestThread then
                questRequest=nil
                local kind=type(result)
                lastQuestReply=(kind=="number" or kind=="boolean" or kind=="nil") and tostring(result)
                    or kind=="string" and result:sub(1,60):gsub("%c"," ") or kind
                if questTimer then task.cancel(questTimer); questTimer=nil end
                if state.farm and not ok then stopFarm("StartQuest failed: "..tostring(result)) end
            end
        end)
        questRequest=requestThread
        questTimer=task.delay(8, function()
            questTimer=nil
            if questRequest==requestThread then stopFarm("StartQuest response timed out after 8 seconds.") end
        end)
    elseif action=="wait_quest" then
        stopMovement();holdPosition(root,npc+Vector3.new(0,2,0),nil)
        status("Waiting for quest confirmation…")
    elseif action=="wait_mob" then
        releaseNativeClick()
        hoverMob=nil
        watchedMob=nil
        if not approachSpawn(root,quest,now)then
            stopMovement();status("No live mob/spawn position: "..(quest and quest[4] or "nearest live enemy"))
        end
    elseif action=="move_mob" then
        spawnRouteKey=nil
        stopMovement()
        status("Approaching: "..target.name)
        holdPosition(root, farmPosition, target.model)
    elseif action=="no_weapon" then
        stopMovement();holdPosition(root,root.Position,nil)
        status("Waiting for "..CONFIG.WeaponType..". Inventory: "..inventorySummary(character))
    elseif action=="attack" or action=="wait_attack" then
        spawnRouteKey=nil
        stopMovement()
        holdPosition(root, farmPosition, target.model)
        if watchedMob~=target.model then
            watchedMob, watchedHealth, lastDamageAt, attackCount=target.model, target.health, now, 0
        elseif target.health<watchedHealth then lastDamageAt=now; watchedHealth=target.health end
        local progress=attackCount>=4 and now-lastDamageAt>CONFIG.NoDamageTimeout and " · HP unchanged; continuing" or ""
        if action~="attack"then status("Attacking: "..target.name.." · HP "..math.ceil(target.health)..progress)end
        if action=="attack" then
            -- Re-read the objective at the effect boundary, including with Auto Quests off.
            local active,activeTitle=questUI()
            local activeRow=active and Core.activeQuest(QUESTS[sea],activeTitle)or nil
            if active and (Core.isBossQuest(activeTitle,BOSS_NAMES) or not activeRow
                or Core.normalizeName(target.name)~=Core.normalizeName(activeRow[4]))then
                releaseNativeClick();status("Quest target changed; updating target without attacking.");return
            end
            if weapon.Parent~=character or weapon.Enabled==false then
                status("Waiting for "..CONFIG.WeaponType.." to be equipped/ready: "..weapon.Name);return
            end
            local facing=Vector3.new(target.part.Position.X,root.Position.Y,target.part.Position.Z)
            if (facing-root.Position).Magnitude>.01 then root.CFrame=CFrame.lookAt(root.Position,facing) end
            lastAttack=now
            if attackMode=="Fruit"then status(fruit.cast(weapon,target,now));return end
            local requiredMob=quest and quest[4]
            local function scopeReady()
                local visible,currentTitle,complete=questUI()
                if complete then return false end
                if visible then
                    local row=Core.activeQuest(QUESTS[sea],currentTitle)
                    return row~=nil and not Core.isBossQuest(currentTitle,BOSS_NAMES)
                        and requiredMob~=nil and Core.normalizeName(row[4])==Core.normalizeName(requiredMob)
                end
                return not state.quests
            end
            local backend,reason=raidCombat.attack(weapon,list,root,nil,combatProbe.mode,now,requiredMob,scopeReady)
            if not backend then status(reason or "Target mismatch; no hit sent.");return end
            attackCount+=1;Core.noteCombatAttempt(combatProbe,now)
            status(weapon.Name.." · "..backend.." · "..target.name.." · HP "..math.ceil(target.health).." · Height "..height..progress)
        end
    end
end
local raidActive
do
    local hud={labels={},dirty=true,scannedAt=-math.huge}
    local function remainingTime(node)
        if not isTextWidget(node)then return nil end
        local value=node.Text:gsub("<[^>]*>",""):lower():gsub("%s+"," "):match("^%s*(.-)%s*$")
        local minutes,seconds=value:match("^time left%s*:%s*(%d+)%s*:%s*(%d%d)$")
        minutes,seconds=tonumber(minutes),tonumber(seconds)
        if not minutes or minutes>60 or not seconds or seconds>=60 then return nil end
        return minutes*60+seconds
    end
    local function readLabels()
        local expired=false
        for _,label in ipairs(hud.labels)do
            if label.Parent and widgetVisible(label)then
                local seconds=remainingTime(label)
                if seconds and seconds>0 then return true,"HUD Time Left"end
                if seconds==0 then expired=true end
            end
        end
        return false,expired
    end
    local function invalidate(node)
        if isTextWidget(node)then hud.dirty=true end
    end
    connect(playerGui.DescendantAdded,invalidate)
    connect(playerGui.DescendantRemoving,invalidate)
    raidActive=function()
        local active,expired=readLabels()
        if active then return true,expired end
        local now=os.clock()
        if hud.dirty or now-hud.scannedAt>=1 then
            hud.dirty=false;hud.scannedAt=now;hud.labels={}
            for _,label in ipairs(playerGui:GetDescendants())do
                -- Cache hidden timers too, so showing the same widget needs no rediscovery.
                if remainingTime(label)~=nil then table.insert(hud.labels,label)end
            end
            active,expired=readLabels()
            if active then return true,expired end
        end
        if expired then return false,"raid timer reached 00:00"end
        local main=playerGui:FindFirstChild("Main")
        local timer=main and main:FindFirstChild("Timer")
        if timer and timer:IsA("GuiObject") and widgetVisible(timer)then
            local seconds=remainingTime(timer)
            if seconds==0 then return false,"raid timer reached 00:00"end
            return true,"legacy Main.Timer"
        end
        return false,"no visible raid timer (Time Left / Main.Timer)"
    end
end
raidCombat.timer=raidActive
local function raidMarkers(root,now)
    if now-raidMarkersAt<.25 then return raidCachedMarkers end
    raidMarkersAt=now;raidCachedMarkers={}
    local origin=workspace:FindFirstChild("_WorldOrigin")
    local locations=origin and origin:FindFirstChild("Locations")
    if locations then
        for _,part in ipairs(locations:GetChildren())do
            local index=part:IsA("BasePart") and tonumber(part.Name:match("^Island ([1-5])$"))
            if index and (part.Position-root.Position).Magnitude<=3000 then
                local current=raidCachedMarkers[index]
                if not current or (part.Position-root.Position).Magnitude<(current.Position-root.Position).Magnitude then
                    raidCachedMarkers[index]=part
                end
            end
        end
    end
    return raidCachedMarkers
end
local function raidStep()
    local active,timerSource=raidActive()
    if not active then
        if raidRunning then
            deactivateWeapon();cancelAuraRequest();auraRequestedCharacter=nil
        end
        dodge.reset();raidRunning=false
        releaseNativeClick();stopMovement();stopHover();restoreCollisions()
        raidIndex,raidMarker,raidEmptyAt=0,nil,nil;combatProbe=nil;raidMarkersAt=-math.huge
        if raidIslandLabel.Text~="Waiting"then raidIslandLabel.Text="Waiting"end
        status("Waiting for a started raid · "..timerSource);return
    end
    local character=localPlayer.Character
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    local root=character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health<=0 or not root then
        dodge.reset();raidRunning=false
        releaseNativeClick();combatProbe=nil;stopMovement();stopHover();restoreCollisions()
        status("Auto Raid: waiting for your character…");return
    end
    local now=os.clock()
    local markers=raidMarkers(root,now)
    if raidIndex==0 then
        local nearest=math.huge
        for index,part in pairs(markers)do
            if part.Parent and (part.Position-root.Position).Magnitude<nearest then
                raidIndex,raidMarker,nearest=index,part,(part.Position-root.Position).Magnitude
            end
        end
    else raidMarker=markers[raidIndex]end
    if not raidMarker or not raidMarker.Parent then
        dodge.reset();raidRunning=false
        releaseNativeClick();stopMovement();stopHover();restoreCollisions();raidEmptyAt=nil
        status("Auto Raid: timer found · waiting for island "..(raidIndex>0 and tostring(raidIndex)or "markers").." in _WorldOrigin.Locations.");return
    end
    if raidIslandLabel.Text~=tostring(raidIndex).." / 5"then raidIslandLabel.Text=tostring(raidIndex).." / 5"end
    raidRunning=true;disableCollisions(character);ensureAura(character)
    if CONFIG.WeaponType=="Fruit" and not fruit.skillsSelected()then
        releaseNativeClick();holdPosition(root,root.Position,nil);status("Fruit: select skills Z / X / C / V before farming.");return
    end
    local weapon,equipStatus
    if CONFIG.WeaponType~="Fruit"then weapon,equipStatus=prepareFirstSlot(character,humanoid,now)end
    if CONFIG.WeaponType~="Fruit" and not weapon then releaseNativeClick();holdPosition(root,root.Position,nil);status(equipStatus);return end
    local list=candidates(root)
    if not list then stopRaid("Auto Raid: workspace.Enemies not found.");return end
    local nearby,scout={},{}
    local playerCharacters={}
    for _,player in ipairs(Players:GetPlayers())do if player.Character then playerCharacters[player.Character]=true end end
    for _,candidate in ipairs(list)do
        if not playerCharacters[candidate.model] and candidate.health>0 then
            -- Assign each NPC to its nearest published raid island, excluding world enemies.
            local owner,nearest=0,CONFIG.RaidIslandRadius
            for index,part in pairs(markers)do
                if part.Parent then
                    local distance=(candidate.part.Position-part.Position).Magnitude
                    if distance<nearest then owner,nearest=index,distance end
                end
            end
            if owner==raidIndex then
                table.insert(scout,candidate)
                if candidate.distance<=CONFIG.RaidRadius then table.insert(nearby,candidate)end
            end
        end
    end
    local evading,reason=dodge.step(humanoid,root,scout,now)
    if evading then status("Auto Raid: side dodge · "..reason);return end
    local target=Core.nearestTarget(nearby,nil)
    local attackMode=fruit.mode(target)
    weapon,equipStatus=prepareFirstSlot(character,humanoid,now,attackMode)
    if not weapon then dodge.reset();releaseNativeClick();holdPosition(root,root.Position,nil);status(equipStatus);return end
    if not target then
        releaseNativeClick();combatProbe=nil
        local distant=Core.nearestTarget(scout,nil)
        if distant then
            raidEmptyAt=nil;holdPosition(root,distant.part.Position+Vector3.new(CONFIG.RaidSideOffset,CONFIG.RaidHeight,0),nil)
            status("Auto Raid: approaching NPC · island "..raidIndex);return
        end
        local position=raidMarker.Position+Vector3.new(0,CONFIG.RaidHeight,0)
        holdPosition(root,position,nil)
        if (root.Position-position).Magnitude>CONFIG.PositionTolerance then raidEmptyAt=nil;status("Auto Raid: flying to island "..raidIndex);return end
        raidEmptyAt=raidEmptyAt or now
        local nextMarker=markers[raidIndex+1]
        if now-raidEmptyAt>=CONFIG.RaidClearWait and nextMarker and nextMarker.Parent then
            raidIndex+=1;raidMarker=nextMarker;raidEmptyAt=nil
            holdPosition(root,nextMarker.Position+Vector3.new(0,CONFIG.RaidHeight,0),nil)
            status("Auto Raid: flying to island "..raidIndex)
        else status("Auto Raid: island "..raidIndex.." clear · waiting for "..(raidIndex==5 and "raid completion"or "next island"))end
        return
    end
    raidEmptyAt=nil
    local height=CONFIG.RaidHeight
    local position=target.part.Position+Vector3.new(CONFIG.RaidSideOffset,height,0)
    if attackMode~="Fruit"then
        combatProbe=Core.updateFixedCombatProbe(combatProbe,weapon,target.model,target.health,now)
    end
    holdPosition(root,position,target.model)
    if now-lastAttack<RAID_ATTACK_INTERVAL-1e-6 then return end
    if not raidActive()or not state.raid or weapon.Parent~=character or weapon.Enabled==false then releaseNativeClick();return end
    local facing=Vector3.new(target.part.Position.X,root.Position.Y,target.part.Position.Z)
    if (facing-root.Position).Magnitude>.01 then root.CFrame=CFrame.lookAt(root.Position,facing)end
    lastAttack=now
    if attackMode=="Fruit"then status("Auto Raid: "..fruit.cast(weapon,target,now));return end
    local backend,reason=raidCombat.attack(weapon,scout,root,markers,combatProbe.mode,now)
    if backend then
        Core.noteCombatAttempt(combatProbe,now)
        status("Auto Raid: "..target.name.." · HP "..math.ceil(target.health).." · "..backend.." · Height "..height)
    else status(reason or "Auto Raid: attack unavailable.")end
end
worker=task.spawn(function()
    while not disposed do
        task.wait(state.raid and RAID_ATTACK_INTERVAL or CONFIG.WorkerInterval)
        if teleport.flight then
            local ok,message=pcall(teleport.tick)
            if not ok then teleport.cancel("Flight error: "..tostring(message))end
        elseif state.farm then
            local ok, errorMessage=pcall(farmStep)
            if not ok then stopFarm("Auto Farm error: "..tostring(errorMessage)) end
        elseif state.raid then
            local ok,errorMessage=pcall(raidStep)
            if not ok then stopRaid("Auto Raid error: "..tostring(errorMessage))end
        end
    end
end)
local function statsStep()
    local data=localPlayer:FindFirstChild("Data")
    local points=data and data:FindFirstChild("Points")
    if not points or type(points.Value)~="number" then statsStatus("Waiting for Data.Points…");return end
    local pointsText=tostring(points.Value)
    if statsPointsLabel.Text~=pointsText then statsPointsLabel.Text=pointsText end
    local now=os.clock()
    if statsJob then return end
    if statsSchedule.pending then
        local request=statsSchedule.pending
        if points.Value~=request.points or (request.stat and request.stat.Value~=request.statValue)then statsSchedule.pending=nil
        elseif now-request.at>=2 then stopStats("Points did not update; paused to avoid repeated requests.");return
        else return end
    end
    if now-statsLastTick<.2-1e-6 then return end
    if points.Value<=0 then statsStatus("No available points.");return end
    local item,rule
    for offset=1,#STAT_RULES do
        local index=(statsSchedule.index+offset-1)%#STAT_RULES+1
        local candidate=STAT_RULES[index]
        if candidate.amount>0 and now-(statsSchedule.last[index]or -math.huge)>=1-1e-6 then
            statsSchedule.index=index;statsSchedule.last[index]=now;rule=candidate
            item={name=candidate.remote,amount=math.min(candidate.amount,math.floor(points.Value))};break
        end
    end
    if not item or item.amount<=0 then return end
    statsLastTick=now
    local remotes=ReplicatedStorage:FindFirstChild("Remotes")
    local remote=remotes and remotes:FindFirstChild("CommF_")
    if not remote or not remote:IsA("RemoteFunction")then stopStats("AddPoint RemoteFunction not found.");return end
    local jobThread
    jobThread=task.defer(function()
        if disposed or not state.stats or statsJob~=jobThread then return end
        item.amount=math.min(rule.amount,math.floor(points.Value))
        if item.amount<=0 then
            statsJob=nil
            if statsTimer then task.cancel(statsTimer);statsTimer=nil end
            return
        end
        local stat=data:FindFirstChild(rule.remote)
        statsSchedule.pending={points=points.Value,stat=stat,statValue=stat and stat.Value,at=os.clock()}
        local ok,result=pcall(function()return remote:InvokeServer("AddPoint",item.name,item.amount)end)
        if not ok then stopStats("AddPoint failed: "..tostring(result));return end
        if statsJob==jobThread then
            statsSchedule.pending.at=os.clock()
            statsJob=nil
            if statsTimer then task.cancel(statsTimer);statsTimer=nil end
            statsStatus(item.name..": +"..item.amount.." requested. Waiting for updated points.")
        end
    end)
    statsJob=jobThread
    statsTimer=task.delay(8,function()
        statsTimer=nil
        if statsJob==jobThread then stopStats("AddPoint response timed out after 8 seconds.")end
    end)
end
statsWorker=task.spawn(function()
    while not disposed do
        task.wait(.1)
        if state.stats then
            local ok,message=pcall(statsStep)
            if not ok then stopStats("Auto Stats error: "..tostring(message))end
        end
    end
end)
local function cleanup()
    if disposed then return end
    disposed=true
    menuTransition+=1
    if menuHideTask then task.cancel(menuHideTask);menuHideTask=nil end
    teleport.cancel()
    speedHack.restore()
    if fruitEsp.set then fruitEsp.set(false)end
    if fruitPrice.set then fruitPrice.set(false)end
    stopFarm()
    stopRaid()
    stopStats()
    if teleport.clearUI then teleport.clearUI()end
    if worker then task.cancel(worker) end
    if statsWorker then task.cancel(statsWorker)end
    for _,tween in pairs(uiTweens)do tween:Cancel()end
    table.clear(uiTweens)
    if cameraConnection then cameraConnection:Disconnect() end
    for _, c in ipairs(connections) do c:Disconnect() end
    for _, tag in pairs(tags) do tag.gui:Destroy() end
    table.clear(tags)
    gui:Destroy()
end
connect(shutdown.Event, cleanup)
connect(close.Activated, cleanup)
connect(gui.Destroying, cleanup)
connect(localPlayer.CharacterRemoving, function()
    speedHack.restore()
    teleport.cancel()
    dodge.reset()
    fruit.target=nil
    releaseNativeClick();combatProbe=nil;raidRunning=false
    stopMovement(); stopHover(); restoreCollisions();cancelAuraRequest();auraRequestedCharacter=nil;deactivateWeapon(); watchedMob=nil
end)
