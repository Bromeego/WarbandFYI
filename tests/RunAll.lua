-- Runs every regression test in its own Lua process.
-- Run from the repo root:
--   lua tests/RunAll.lua

local TESTS = {
    "BackupChainTest",
    "CharacterDiscoveryTest",
    "CollectionHuntsLayoutTest",
    "CollectionHuntsTest",
    "ContextFyiTest",
    "EventThrottleTest",
    "FyiQueueTest",
    "GoldTrackerTest",
    "HousingDecorTest",
    "LifetimeRetentionTest",
    "MonthHistoryGapTest",
    "MonthHistoryTest",
    "NotebookFyiTest",
    "NotebookPetsTest",
    "NotebookSheetTest",
    "NotebookSmartTest",
    "NotebookTest",
    "PetSessionProgressTest",
    "ProfessionPetTest",
    "QuestClassificationTest",
    "RenownIdentityTest",
    "ResourceClassificationTest",
    "TimeBoundaryTest",
    "WarbandCurrencyTest",
    "WorldActivityTest",
}

local lua = arg and arg[-1] or "lua"
local windows = package.config:sub(1, 1) == "\\"
local quiet = windows and " > NUL 2>&1" or " > /dev/null 2>&1"
local failed = {}

-- cmd /c strips the first and last quote of a command that holds more than
-- one quoted part, which breaks a path such as "Program Files (x86)". One
-- outer pair of quotes absorbs that.
local function shell(command)
    if windows then
        return '"' .. command .. '"'
    end
    return command
end

for index = 1, #TESTS do
    local name = TESTS[index]
    local result = os.execute(shell('"' .. lua .. '" tests/' .. name .. ".lua" .. quiet))
    local ok = result == 0 or result == true
    print((ok and "ok    " or "FAIL  ") .. name)
    if not ok then
        failed[#failed + 1] = name
    end
end

if #failed > 0 then
    print(#failed .. " of " .. #TESTS .. " test files failed: " .. table.concat(failed, ", "))
    os.exit(1)
end
print("All " .. #TESTS .. " test files passed")
