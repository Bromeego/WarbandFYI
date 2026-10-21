-- Collection hunt lockouts and slash routing.
--   lua tests/CollectionHuntsTest.lua

local script = arg and arg[0] or "tests/CollectionHuntsTest.lua"
local root = script:match("^(.*)[/\\][Tt]ests[/\\]") or "."

local function loadAddon(path, wbf)
    local chunk, err = loadfile(root .. "/" .. path)
    if not chunk then
        error(err)
    end
    chunk("WarbandFYI", wbf)
end

local now = 1700000000
function time()
    return now
end

local WBF = {}
local db = {}
local failures = 0
local said = {}

function print(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[index] = tostring(select(index, ...))
    end
    said[#said + 1] = table.concat(parts, " ")
end

local function report(line)
    io.write(line .. "\n")
end

local function check(name, condition, detail)
    if condition then
        report("PASS  " .. name)
        return
    end
    failures = failures + 1
    report("FAIL  " .. name .. (detail and ("  " .. tostring(detail)) or ""))
end

WBF.Database = {
    Get = function()
        return db
    end,
}
WBF.Characters = {
    GetGuid = function()
        return "A"
    end,
    Get = function()
        return { guid = "A", name = "Mira", realm = "Area 52", classFile = "HUNTER" }
    end,
    List = function()
        return { { guid = "A", name = "Mira", realm = "Area 52" } }
    end,
}
WBF.UI = {}

loadAddon("Utils/Format.lua", WBF)
loadAddon("Tracking/CollectionSources.lua", WBF)
loadAddon("Tracking/CollectionHunts.lua", WBF)

local function reset()
    db = {}
    said = {}
end

local function lockout(instanceKey, saves, bosses)
    db.collectionHunts.lockouts = {
        A = {
            [instanceKey] = {
                checkedAt = now,
                verified = true,
                expiresAt = now + 3600,
                bosses = bosses or {},
                saves = saves,
            },
        },
    }
end

local function save(difficultyID, bossKey)
    return {
        difficultyID = difficultyID,
        expiresAt = now + 3600,
        bosses = { [bossKey] = true },
    }
end

reset()
local jikun = WBF.CollectionHunts.AddTarget("95059", "jikun")
check("jikun item becomes a hunt", type(jikun) == "string")
lockout("throneofthunder", { save(7, "jikun") })
check("raid finder ji-kun is still available", WBF.CollectionHunts.Status(jikun, "A") == "available")
lockout("throneofthunder", { save(17, "jikun") })
check("modern raid finder ji-kun is still available", WBF.CollectionHunts.Status(jikun, "A") == "available")
lockout("throneofthunder", { save(7, "jikun"), save(3, "jikun") })
check("normal ji-kun lockout is done", WBF.CollectionHunts.Status(jikun, "A") == "done")
lockout("throneofthunder", nil, { jikun = true })
check("combined legacy ji-kun snapshot stays unverified", WBF.CollectionHunts.Status(jikun, "A") == "unknown")

reset()
local invincible = WBF.CollectionHunts.AddTarget("50818", "invincible")
check("invincible item becomes a hunt", type(invincible) == "string")
lockout("icecrowncitadel", { save(4, "thelichking") })
check("25 normal lich king is not a heroic clear", WBF.CollectionHunts.Status(invincible, "A") == "unknown")
lockout("icecrowncitadel", { save(6, "thelichking") })
check("25 heroic lich king is done", WBF.CollectionHunts.Status(invincible, "A") == "done")

reset()
check("hunter is not a hunt command", WBF.CollectionHunts.Slash("hunter") == false)
check("hunter prints nothing", #said == 0)
check("hunt list is handled", WBF.CollectionHunts.Slash("hunt list") == true)
check("exact hunt is handled", WBF.CollectionHunts.Slash("hunt") == true)
check("hunts is handled", WBF.CollectionHunts.Slash("hunts") == true)

if failures > 0 then
    report(failures .. " failed")
    os.exit(1)
end
report("all passed")
