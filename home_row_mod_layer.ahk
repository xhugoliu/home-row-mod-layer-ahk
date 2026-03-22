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

for tapKey, modKey in g_HomeRowMods {
    InitModTap(tapKey, modKey)
    Hotkey, % "$*" tapKey, __HomeRowDown
    Hotkey, % "$*" tapKey " up", __HomeRowUp
}

for chordKey, state in g_ChordState {
    Hotkey, % "$*" chordKey, __ChordDown
    Hotkey, % "$*" chordKey " up", __ChordUp
}

; Space: tap = Space, hold = nav layer
$*Space::SpaceDown()
$*Space up::SpaceUp()

; Layer mappings while Space is held
#If (g_LayerOn)
    $*y::
$*u::
$*i::
$*o::
$*h::
$*j::
$*k::
$*l::
    LayerSend(g_LayerNav[GetTapKey(A_ThisHotkey)])
return
#If

__HomeRowDown:
    ModTapDown(GetTapKey(A_ThisHotkey))
return

__HomeRowUp:
    ModTapUp(GetTapKey(A_ThisHotkey))
return

__ChordDown:
    ChordDown(GetTapKey(A_ThisHotkey))
return

__ChordUp:
    ChordUp(GetTapKey(A_ThisHotkey))
return

__ModTapTimer:
    ProcessModTapTimers()
return

InitModTap(tapKey, modKey) {
    global g_ModTapState
    g_ModTapState[tapKey] := { modKey: modKey, isDown: false, asMod: false, downTick: 0, suppressed: false }
}

SpaceDown() {
    global g_LayerOn, g_SpaceUsed, g_SpaceDownTick
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

LayerSend(navKey) {
    global g_SpaceUsed
    g_SpaceUsed := true
    SendInput, {Blind}{%navKey%}
}
