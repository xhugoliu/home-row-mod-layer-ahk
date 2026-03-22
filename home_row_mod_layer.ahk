#NoEnv
#SingleInstance Force
#UseHook On
SendMode Input
SetBatchLines, -1
#MaxThreadsPerHotkey 1

global g_TapHoldMs := 180
global g_ChordMs := 50
global g_LayerOn := false
global g_SpaceUsed := false
global g_SpaceDownTick := 0
global g_ModTapState := {}
global g_ModChords := {f: {partner: "j", output: "F20"}, j: {partner: "f", output: "F20"}}
global g_HomeRowMods := {s: "LWin", l: "RWin", d: "LShift", k: "RShift", f: "LCtrl", j: "RCtrl", g: "LAlt", h: "RAlt"}
global g_LayerNav := {y: "Home", u: "PgDn", i: "PgUp", o: "End", h: "Left", j: "Down", k: "Up", l: "Right"}
global g_ChordState := {e: {isDown: false, downTick: 0, suppressed: false}, r: {isDown: false, downTick: 0, suppressed: false}}
global g_PhysicalKeys := ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"
, "1", "2", "3", "4", "5", "6", "7", "8", "9", "0"
, "-", "=", "[", "]", "\", ";", "'", ",", ".", "/", "`"
, "Space", "Tab", "Enter", "Backspace", "Escape", "Delete", "Home", "End", "PgUp", "PgDn", "Up", "Down", "Left", "Right"
, "LShift", "RShift", "LCtrl", "RCtrl", "LAlt", "RAlt", "LWin", "RWin"]
global g_KeyDown := {}
global g_KeyOutputState := {}

for tapKey, modKey in g_HomeRowMods
    InitModTap(tapKey, modKey)

for _, keyName in g_PhysicalKeys {
    g_KeyDown[keyName] := false
    g_KeyOutputState[keyName] := {mode: "none"}
    Hotkey, % "$*" keyName, __PhysDown
    Hotkey, % "$*" keyName " up", __PhysUp
}

__PhysDown:
    HandlePhysDown(NormalizeHotkey(A_ThisHotkey))
return

__PhysUp:
    HandlePhysUp(NormalizeHotkey(A_ThisHotkey))
return

__ModTapTimer:
    ProcessModTapTimers()
return

InitModTap(tapKey, modKey) {
    global g_ModTapState
    g_ModTapState[tapKey] := { modKey: modKey, isDown: false, asMod: false, downTick: 0, suppressed: false }
}

NormalizeHotkey(hotkey) {
    hotkey := RegExReplace(hotkey, "^\$\*")
return RegExReplace(hotkey, " up$")
}

HandlePhysDown(key) {
    global g_KeyDown, g_KeyOutputState, g_HomeRowMods, g_ChordState, g_LayerOn, g_LayerNav, g_SpaceUsed

    repeat := g_KeyDown[key]
    if (!repeat) {
        g_KeyDown[key] := true
        g_KeyOutputState[key] := {mode: "none"}
        if (g_LayerOn && key != "Space")
            g_SpaceUsed := true
    }

    if (key = "Space") {
        if (!repeat)
            SpaceDown()
        return
    }

    if (g_LayerOn && g_LayerNav.HasKey(key)) {
        LayerSend(g_LayerNav[key])
        return
    }

    if (g_HomeRowMods.HasKey(key)) {
        if (!repeat)
            ModTapDown(key)
        return
    }

    if (g_ChordState.HasKey(key)) {
        if (!repeat)
            ChordDown(key)
        return
    }

    if (repeat) {
        RepeatForwardKey(key)
        return
    }

    ResolveInterruptedTaps(key)
    SendForwardDown(key)
}

HandlePhysUp(key) {
    global g_KeyDown, g_HomeRowMods, g_ChordState

    g_KeyDown[key] := false

    if (key = "Space") {
        SpaceUp()
        return
    }

    if (g_HomeRowMods.HasKey(key)) {
        ModTapUp(key)
        return
    }

    if (g_ChordState.HasKey(key)) {
        ChordUp(key)
        return
    }

    SendForwardUp(key)
}

RepeatForwardKey(key) {
    SendInput, {Blind}{%key%}
}

SendForwardDown(key) {
    global g_KeyOutputState
    keyDown := key . " down"
    g_KeyOutputState[key] := {mode: "key", action: key}
    SendInput, {Blind}{%keyDown%}
}

SendForwardUp(key) {
    global g_KeyOutputState
    state := g_KeyOutputState[key]

    if (!IsObject(state) || state.mode != "key") {
        g_KeyOutputState[key] := {mode: "none"}
        return
    }

    keyUp := state.action . " up"
    SendInput, {Blind}{%keyUp%}
    g_KeyOutputState[key] := {mode: "none"}
}

SpaceDown() {
    global g_LayerOn, g_SpaceUsed, g_SpaceDownTick
    ResolveInterruptedTaps("Space")
    g_SpaceDownTick := A_TickCount
    g_SpaceUsed := false
    g_LayerOn := true
}

SpaceUp() {
    global g_LayerOn, g_SpaceUsed, g_SpaceDownTick, g_TapHoldMs
    g_LayerOn := false

    if (!g_SpaceUsed && (A_TickCount - g_SpaceDownTick < g_TapHoldMs))
        SendInput, {Space}
}

ModTapDown(tapKey) {
    global g_ModTapState
    ResolveInterruptedTaps(tapKey)
    state := g_ModTapState[tapKey]

    ; Ignore key-repeat while the physical key is already down.
    if (state.isDown)
        return

    state.isDown := true
    state.asMod := false
    state.downTick := A_TickCount
    state.suppressed := false

    TryModChord(tapKey)

    SetTimer, __ModTapTimer, 10
}

ProcessModTapTimers() {
    global g_ModTapState, g_TapHoldMs
    now := A_TickCount

    for _, state in g_ModTapState {
        if (state.isDown && !state.asMod && !state.suppressed && (now - state.downTick >= g_TapHoldMs)) {
            state.asMod := true
            modDown := state.modKey . " down"
            SendInput, {%modDown%}
        }
    }

    StopModTapTimerIfIdle()
}

ModTapUp(tapKey) {
    global g_ModTapState
    state := g_ModTapState[tapKey]

    if (!state.isDown)
        return

    state.isDown := false

    if (state.suppressed) {
        state.suppressed := false
    } else if (state.asMod) {
        modUp := state.modKey . " up"
        SendInput, {%modUp%}
        state.asMod := false
    } else {
        SendInput, {Blind}{%tapKey%}
    }

    state.downTick := 0

    StopModTapTimerIfIdle()
}

HasPendingModTap() {
    global g_ModTapState
    for _, state in g_ModTapState {
        if (state.isDown && !state.asMod && !state.suppressed)
            return true
    }
return false
}

ResolveInterruptedTaps(currentKey) {
    ResolveInterruptedModTaps(currentKey)
    ResolveInterruptedChordTaps(currentKey)
}

ResolveInterruptedModTaps(currentKey) {
    global g_ModTapState

    for tapKey, state in g_ModTapState {
        if (state.isDown && !state.asMod && !state.suppressed && !CanWaitForModChord(tapKey, state, currentKey)) {
            state.suppressed := true
            SendInput, {Blind}{%tapKey%}
        }
    }

    StopModTapTimerIfIdle()
}

CanWaitForModChord(tapKey, state, currentKey) {
    global g_ModChords, g_ChordMs
return (g_ModChords.HasKey(tapKey)
&& (g_ModChords[tapKey].partner = currentKey)
&& (A_TickCount - state.downTick <= g_ChordMs))
}

ResolveInterruptedChordTaps(currentKey) {
    global g_ChordState

    for chordKey, state in g_ChordState {
        if (state.isDown && !state.suppressed && !CanWaitForChord(chordKey, state, currentKey)) {
            state.suppressed := true
            SendInput, {Blind}{%chordKey%}
        }
    }
}

CanWaitForChord(chordKey, state, currentKey) {
    global g_ChordMs
otherKey := (chordKey = "e") ? "r" : "e"
return (currentKey = otherKey) && (A_TickCount - state.downTick <= g_ChordMs)
}

TryModChord(tapKey) {
    global g_ModTapState, g_ModChords, g_ChordMs

    if (!g_ModChords.HasKey(tapKey))
        return

    state := g_ModTapState[tapKey]
    chord := g_ModChords[tapKey]
    otherState := g_ModTapState[chord.partner]

    if (otherState.isDown && !otherState.asMod && !otherState.suppressed && (Abs(state.downTick - otherState.downTick) <= g_ChordMs)) {
        state.suppressed := true
        otherState.suppressed := true
        chordOutput := chord.output
        SendInput, {Blind}{%chordOutput%}
    }
}

StopModTapTimerIfIdle() {
    if (!HasPendingModTap())
        SetTimer, __ModTapTimer, Off
}

ChordDown(chordKey) {
    global g_ChordState, g_ChordMs
    ResolveInterruptedTaps(chordKey)
    state := g_ChordState[chordKey]

    if (state.isDown)
        return

    state.isDown := true
    state.downTick := A_TickCount
    state.suppressed := false

otherKey := (chordKey = "e") ? "r" : "e"
    otherState := g_ChordState[otherKey]

    if (otherState.isDown && !otherState.suppressed && (Abs(state.downTick - otherState.downTick) <= g_ChordMs)) {
        state.suppressed := true
        otherState.suppressed := true
        SendInput, {Blind}{Tab}
    }
}

ChordUp(chordKey) {
    global g_ChordState
    state := g_ChordState[chordKey]

    if (!state.isDown)
        return

    state.isDown := false

    if (!state.suppressed)
        SendInput, {Blind}{%chordKey%}

    state.suppressed := false
    state.downTick := 0
}

GetTapKey(hotkey) {
return SubStr(hotkey, 3, 1)
}

GetHotkeyName(hotkey) {
return RegExReplace(hotkey, "^[~$*]+")
}

LayerSend(navKey) {
    global g_SpaceUsed
    g_SpaceUsed := true
    SendInput, {Blind}{%navKey%}
}
