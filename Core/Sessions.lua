local _, WBF = ...

WBF.Sessions = {}

local GAP_SPLIT_SECONDS = 120

local function MarkSummaryDirty()
    if WBF.Aggregator and WBF.Aggregator.MarkDirty then
        WBF.Aggregator.MarkDirty()
    end
end

local function Timeout()
    local seconds = WarbandFYI_DB.config.sessionTimeoutSeconds
    if type(seconds) ~= "number" or seconds < 60 then
        return 3600
    end
    return seconds
end

function WBF.Sessions.Find(sessionId)
    local sessions = WarbandFYI_DB.sessions
    for index = 1, #sessions do
        if sessions[index].id == sessionId then
            return sessions[index]
        end
    end
    return nil
end

function WBF.Sessions.GetActive()
    local session = WBF.Sessions.Find(WarbandFYI_DB.activeSessionId)
    if session and not session.endedAt then
        return session
    end
    return nil
end

function WBF.Sessions.GetActiveId()
    local session = WBF.Sessions.GetActive()
    return session and session.id or nil
end

function WBF.Sessions.GetLastCompleted()
    local sessions = WarbandFYI_DB.sessions
    local best = nil
    for index = 1, #sessions do
        local session = sessions[index]
        if session.endedAt and (not best or session.endedAt > best.endedAt) then
            best = session
        end
    end
    return best
end

function WBF.Sessions.CloseOpenSegments(session, at)
    local segments = session.segments
    if not segments then
        return
    end
    for index = 1, #segments do
        local segment = segments[index]
        if not segment.endedAt then
            segment.endedAt = at or segment.startedAt
            if segment.endedAt < segment.startedAt then
                segment.endedAt = segment.startedAt
            end
        end
    end
end

function WBF.Sessions.Close(session, at)
    if not session or session.endedAt then
        return
    end
    local endedAt = at or session.lastActivityAt or WBF.Time.Now()
    WBF.Sessions.CloseOpenSegments(session, endedAt)
    session.endedAt = endedAt
    session.lastActivityAt = endedAt
    if WarbandFYI_DB.activeSessionId == session.id then
        WarbandFYI_DB.activeSessionId = nil
    end
    MarkSummaryDirty()
    WBF.Debug.Log("Session", session.id, "closed")
end

local function Start(now)
    local session = {
        id = WBF.Database.AllocSessionId(),
        startedAt = now,
        endedAt = nil,
        lastActivityAt = now,
        segments = {},
        -- Empty, not nil: this session tracks gold from here on. Nil is older
        -- data, which GoldTracker rebuilds from per-character snapshots.
        goldByCharacter = {},
        goldLedger = {},
    }
    local sessions = WarbandFYI_DB.sessions
    sessions[#sessions + 1] = session
    WarbandFYI_DB.activeSessionId = session.id
    WBF.Debug.Log("Session", session.id, "started")
    if WBF.Database and WBF.Database.Prune then
        WBF.Database.Prune(false)
    end
    if WBF.GoldTracker and WBF.GoldTracker.Reconcile then
        WBF.GoldTracker.Reconcile()
    end
    MarkSummaryDirty()
    return session
end

function WBF.Sessions.BeginSegment(session, guid, now)
    if not session or not guid then
        return
    end
    session.segments = session.segments or {}
    local segments = session.segments
    local last = segments[#segments]
    if last and not last.endedAt and last.guid == guid then
        return
    end
    if last and not last.endedAt then
        WBF.Sessions.CloseOpenSegments(session, now)
    end
    segments[#segments + 1] = {
        guid = guid,
        startedAt = now,
        endedAt = nil,
    }
end

function WBF.Sessions.HandleLogin()
    local guid = WBF.Characters.GetGuid()
    local now = WBF.Time.Now()
    local session = WBF.Sessions.GetActive()
    local previousActivity = session and (session.lastActivityAt or session.startedAt) or nil

    if session and previousActivity and (now - previousActivity) <= Timeout() then
        WBF.Sessions.CloseOpenSegments(session, previousActivity)
        WBF.Sessions.BeginSegment(session, guid, now)
        session.lastActivityAt = now
        MarkSummaryDirty()
        WBF.Debug.Log("Session", session.id, "resumed")
        return session
    end

    if session then
        WBF.Sessions.Close(session, previousActivity)
    end

    session = Start(now)
    WBF.Sessions.BeginSegment(session, guid, now)
    return session
end

function WBF.Sessions.HandleLogout()
    local session = WBF.Sessions.GetActive()
    if not session then
        return
    end
    local now = WBF.Time.Now()
    WBF.Sessions.CloseOpenSegments(session, now)
    session.lastActivityAt = now
end

function WBF.Sessions.Touch()
    local guid = WBF.Characters.GetGuid()
    if not guid then
        return WBF.Sessions.GetActive()
    end

    local now = WBF.Time.Now()
    local session = WBF.Sessions.GetActive()
    local lastAt = session and (session.lastActivityAt or session.startedAt) or nil
    if not session or not lastAt or (now - lastAt) > Timeout() then
        if session then
            WBF.Sessions.Close(session, lastAt)
        end
        session = Start(now)
        WBF.Sessions.BeginSegment(session, guid, now)
        return session
    end

    if (now - lastAt) > GAP_SPLIT_SECONDS then
        WBF.Sessions.CloseOpenSegments(session, lastAt)
        WBF.Sessions.BeginSegment(session, guid, now)
    end
    session.lastActivityAt = now
    return session
end

-- UnitIsAFK can return a secret boolean. Unknown stays false so an unreadable
-- flag does not freeze the open session.
function WBF.Sessions.PlayerIsAFK()
    if not UnitIsAFK then
        return false
    end
    return WBF.Format.AsBoolean(UnitIsAFK("player")) and true or false
end

function WBF.Sessions.CloseIfTimedOut()
    local session = WBF.Sessions.GetActive()
    if not session then
        return
    end
    local now = WBF.Time.Now()
    local lastAt = session.lastActivityAt or session.startedAt
    if not lastAt or (now - lastAt) > Timeout() then
        WBF.Sessions.Close(session, lastAt)
    end
end

-- Open segments count through "now" while you are at the keyboard, and freeze
-- at the last real activity while AFK so idle time is not played time.
function WBF.Sessions.SegmentEnd(session, segment)
    if segment.endedAt then
        return segment.endedAt
    end
    if session.endedAt then
        return session.endedAt
    end
    if WBF.Sessions.PlayerIsAFK() then
        return session.lastActivityAt or segment.startedAt
    end
    return WBF.Time.Now()
end
