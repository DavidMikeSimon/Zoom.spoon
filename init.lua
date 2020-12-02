--[[

 Known issues:
 * Mute is not detected properly during a Zoom Webinar
 * toggleMute() will stop working if the user changes state via the Zoom client

]]

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Unofficial Zoom Spoon"
obj.version = "1.0"
obj.author = "Joel Franusic"
obj.license = "MIT"
obj.homepage = "https://github.com/jpf/Zoom.spoon"

obj.callbackFunction = nil

function unpack (t, i)
  i = i or 1
  if t[i] ~= nil then
    return t[i], unpack(t, i + 1)
  end
end

-- via: https://github.com/kyleconroy/lua-state-machine/
local machine = dofile(hs.spoons.resourcePath("statemachine.lua"))

local sysWatcher = hs.application.watcher.new(function (appName, eventType, appObject)
  if (appObject ~= nil and appObject:title() == "zoom.us") then
    if (eventType == hs.application.watcher.launched) then
      hs.printf("watcher detected zoom launch")
      startZoomWatcher(appObject)
    elseif (eventType == hs.application.watcher.terminated) then
      hs.printf("watcher detected zoom terminate")
      endZoomWatcher()
    end
  end
end)

local zoomWatcher = nil

local zoomState = machine.create({
  initial = 'closed',
  events = {
    { name = 'start',        from = 'closed',  to = 'running' },
    { name = 'startMeeting', from = 'running', to = 'meeting' },
    { name = 'endMeeting',   from = 'meeting', to = 'running' },
    { name = 'stop',         from = 'meeting', to = 'closed' },
    { name = 'stop',         from = 'running', to = 'closed' },
  },
  callbacks = {
    onstatechange = function(self, event, from, to)
      obj:_notifyChange("zoom", from, to)
    end,
  }
})

local micState = machine.create({
  initial = 'off',
  events = {
    { name = 'unmuted',      from = 'off',     to = 'unmuted' },
    { name = 'unmuted',      from = 'muted',   to = 'unmuted' },
    { name = 'muted',        from = 'off',     to = 'muted' },
    { name = 'muted',        from = 'unmuted', to = 'muted' },
    { name = 'stop',         from = 'muted',   to = 'off' },
    { name = 'stop',         from = 'unmuted', to = 'off' },
  },
  callbacks = {
    onstatechange = function(self, event, from, to)
      obj:_notifyChange("mic", from, to)
    end,
  }
})

local checkStatusesDebouncer = hs.timer.delayed.new(1, function()
  obj:_checkZoomMeetingStatus()
  obj:_checkMicStatus()
end)

function startZoomWatcher(appObject)
  if (zoomWatcher ~= nil) then
    return
  end

  zoomWatcher = appObject:newWatcher(function (element, event, watcher, userData)
    local eventName = tostring(event)

    if(eventName == "AXTitleChanged" or eventName == "AXWindowCreated" or eventName == "AXUIElementDestroyed") then
      checkStatusesDebouncer:start()
    end
  end, { name = "zoom.us" })
  zoomWatcher:start({
    hs.uielement.watcher.windowCreated,
    hs.uielement.watcher.titleChanged,
    hs.uielement.watcher.elementDestroyed
  })

  zoomState:start()
  obj:_checkZoomMeetingStatus()
  obj:_checkMicStatus()
end

function endZoomWatcher()
  if (zoomWatcher ~= nil) then
    zoomWatcher:stop()
    zoomState:stop()
    zoomWatcher = nil
  end
end

function obj:start()
  hs.printf("Starting Zoom spoon")
  local zoomAppAlreadyRunning = hs.application.get("zoom.us")
  if (zoomAppAlreadyRunning ~= nil) then
    hs.printf("Zoom app already running, starting watcher")
    startZoomWatcher(zoomAppAlreadyRunning)
  end
  sysWatcher:start()
end

function obj:stop()
  sysWatcher:stop()
end

function _findZoomMenuItem(tbl)
  local app = hs.application.get("zoom.us")
  if (app ~= nil) then
    return app:findMenuItem(tbl) ~= nil
  end
end

function _selectZoomMenuItem(tbl)
  local app = hs.application.get("zoom.us")
  if (app ~= nil) then
    return app:selectMenuItem(tbl)
  end
end

function obj:_notifyChange(subject, fromState, toState)
  if (self.callbackFunction) then
    self.callbackFunction(subject, fromState, toState)
  end
end

function obj:_checkZoomMeetingStatus()
  if _findZoomMenuItem({"Meeting", "Invite"}) then
    zoomState:startMeeting()
  else
    zoomState:endMeeting()
  end
end

function obj:_checkMicStatus()
  if _findZoomMenuItem({"Meeting", "Unmute Audio"}) then
    hs.printf("CHECK: MUTED")
    micState:muted()
  elseif _findZoomMenuItem({"Meeting", "Mute Audio"}) then
    hs.printf("CHECK: UNMUTED")
    micState:unmuted()
  else
    micState:stop()
  end
end

--- Zoom:toggleMute()
--- Method
--- Toggles between the 'muted' and 'unmuted states'
function obj:toggleMute()
  obj:_checkMicStatus()
  if micState:is('muted') then
    self:unmute()
  elseif micState:is('unmuted') then
    self:mute()
  else
    return nil
  end
end

--- Zoom:mute()
--- Method
--- Mutes the audio in Zoom, if Zoom is currently unmuted
function obj:mute()
  self:_checkMicStatus()
  if micState:is('unmuted') then
    _selectZoomMenuItem({"Meeting", "Mute Audio"})
    checkStatusesDebouncer:start()
  end
end

--- Zoom:unmute()
--- Method
--- Unmutes the audio in Zoom, if Zoom is currently muted
function obj:unmute()
  self:_checkMicStatus()
  if micState:is('muted') then
    _selectZoomMenuItem({"Meeting", "Unmute Audio"})
    checkStatusesDebouncer:start()
  end
end

function obj:inMeeting()
  return zoomState:is('meeting')
end

--- Zoom:setStatusCallback(func)
--- Method
--- Registers a function to be called whenever Zoom's state changes
---
--- Parameters:
--- * func - A function in the form "function(event)" where "event" is a string describing the state change event
function obj:setStatusCallback(func)
  self.callbackFunction = func
end

return obj
