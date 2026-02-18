local projectRoot = "/Users/grigorymordokhovich/Documents/Develop/Voice input"
local scriptPath = projectRoot .. "/scripts/ptt_whisper.sh"

local isRecording = false
local pttWatcher = nil

local function runShell(args, callback)
  hs.task
    .new("/bin/zsh", function(exitCode, stdOut, stdErr)
      callback(exitCode, stdOut, stdErr)
      return true
    end, args)
    :start()
end

local function startRecording()
  if isRecording then
    return
  end

  isRecording = true
  hs.alert.show("Recording...", 0.3)
  runShell({ "-lc", string.format("%q start", scriptPath) }, function(_, _, _)
    return
  end)
end

local function stopRecordingAndPaste()
  if not isRecording then
    return
  end

  isRecording = false
  hs.alert.show("Transcribing...", 0.4)
  runShell({ "-lc", string.format("%q stop", scriptPath) }, function(exitCode, stdOut, stdErr)
    if exitCode ~= 0 then
      hs.alert.show("STT error", 1)
      if stdErr and #stdErr > 0 then
        print(stdErr)
      end
      return
    end

    local text = (stdOut or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
      hs.alert.show("No speech detected", 0.8)
      return
    end

    hs.pasteboard.setContents(text)
    hs.eventtap.keyStroke({ "cmd" }, "v", 0)
    hs.alert.show("Pasted", 0.5)
  end)
end

local function updateShiftFnState(flags)
  local shiftFnHeld = flags.shift and flags.fn
  if shiftFnHeld and not isRecording then
    startRecording()
    return
  end
  if (not shiftFnHeld) and isRecording then
    stopRecordingAndPaste()
  end
end

if pttWatcher then
  pttWatcher:stop()
end

pttWatcher = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(event)
  updateShiftFnState(event:getFlags())
  return false
end)
pttWatcher:start()

hs.alert.show("PTT ready: hold Shift+Fn", 1.2)
