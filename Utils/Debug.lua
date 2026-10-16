local _, WBF = ...

WBF.Debug = {}

function WBF.Debug.Enabled()
    local db = WarbandFYI_DB
    return db and db.config and db.config.debug == true
end

function WBF.Debug.Log(...)
    if not WBF.Debug.Enabled() then
        return
    end
    print("|cffd4af37WarbandFYI|r", ...)
end
