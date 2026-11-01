]]

-- ⚠️ IMPORTANT: Put this code at the VERY TOP of your Main Script (before obfuscating) ⚠️

local ProtectionConfig = {
    -- 🔴 CRITICAL: This MUST exactly match the 'Secret' value in your Key System's Config!
    -- If your Key System has: Secret = "Test"
    -- Then this must also be: SecretKey = "Test"
    SecretKey = "Test",
    
    -- The name of your Hub (shown in the kick message if they try to bypass)
    HubName = "MelxMacro"
}

-- Anti-Bypass Logic: Checks if the Key System successfully set the global variable
if not _G[ProtectionConfig.SecretKey] then
    local player = game:GetService("Players").LocalPlayer
    if player then
        player:Kick("\n🛡️ Unauthorized Execution 🛡️\n\nPlease use the official Key System to run " .. ProtectionConfig.HubName)
    end
    return -- Stops the rest of the script from loading!
end



#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

DllCall("Winmm\timeBeginPeriod", "UInt", 1)

; ============================================
; BLOX FRUIT SORU AUTO-KEY
; ============================================

; --- GLOBALS ---
global mem := 0
global baseAddr := 0
global dataModel := 0
global workspace := 0
global players := 0
global localPlayer := 0
global character := 0
global humanoid := 0
global keysPressed := 0
global isRunning := false
global lastPos := {x: 0.0, y: 0.0, z: 0.0}
global soruDistThreshold := 20.0
global soruCooldown := 0
global lastKnownPos := {x: 0.0, y: 0.0, z: 0.0}
global posInitialized := false

; --- CONFIG ---
global configKey := "z"

; ============================================
; OFFSETS (UPDATED)
; ============================================

class Offsets {
    static FakeDataModelPtr := 0x8d06600  ;[cite: 2]
    static RealDataModel := 0x1f8         ;[cite: 2]
    static ChildrenStart := 0x70          ;[cite: 2]
    static ChildrenEnd := 0x8             ;[cite: 2]
    static NameContainer := 0x68          ;[cite: 2]
    static Name := 0x0                    ;[cite: 2]
    static ClassDescriptor := 0x18        ;[cite: 2]
    static ClassName := 0x8               ;[cite: 2]
    static Parent := 0x60                 ;[cite: 2]
    static Workspace := 0x148             ;[cite: 2]
    static CurrentCamera := 0x4a0         ;[cite: 2]
    static LocalPlayer := 0x118           ;[cite: 2]
    static ModelInstance := 0x2a0         ;[cite: 2]
    static HumanoidRootPart := 0x460      ;[cite: 2]
    static Primitive := 0x178             ;[cite: 2]
    static PrimitivePosition := 0xd4      ;[cite: 2]
    static AssemblyLinearVelocity := 0xe0 ;[cite: 2]
}

; ============================================
; LOG HELPERS
; ============================================

AddLog(msg) {
    global debugLog
    try {
        current := debugLog.Value
        if (current != "")
            current .= "`r`n"
        current .= msg
        debugLog.Value := current
    }
}

ClearDebug() {
    global debugLog
    try debugLog.Value := ""
}

; ============================================
; AUTO-OFFSET UPDATER
; ============================================

_JsonGetInt(json, section, key) {
    secPos := InStr(json, '"' section '"')
    if !secPos
        return 0
    searchArea := SubStr(json, secPos, 3000)
    if RegExMatch(searchArea, '"' key '"\s*:\s*(\d+)', &m)
        return Integer(m[1])
    return 0
}

AutoUpdateOffsets() {
    global Offsets
    try {
        AddLog("Fetching offsets from imtheo.lol...")

        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.Open("GET", "https://offsets.imtheo.lol/offsets.json", false)
        whr.SetRequestHeader("User-Agent", "Mozilla/5.0")
        whr.Send()

        if whr.Status != 200 {
            AddLog("Offset fetch HTTP " whr.Status " - using hardcoded")
            return
        }

        j := whr.ResponseText
        _Get(val, fallback) => (val > 0) ? val : fallback

        Offsets.FakeDataModelPtr := _Get(_JsonGetInt(j, "FakeDataModel", "Pointer"), Offsets.FakeDataModelPtr)
        Offsets.RealDataModel := _Get(_JsonGetInt(j, "FakeDataModel", "RealDataModel"), Offsets.RealDataModel)
        Offsets.ChildrenStart := _Get(_JsonGetInt(j, "Instance", "ChildrenStart"), Offsets.ChildrenStart)
        Offsets.ChildrenEnd := _Get(_JsonGetInt(j, "Instance", "ChildrenEnd"), Offsets.ChildrenEnd)
        Offsets.NameContainer := _Get(_JsonGetInt(j, "Instance", "NameContainer"), Offsets.NameContainer)
        Offsets.Name := _Get(_JsonGetInt(j, "Instance", "Name"), Offsets.Name)
        Offsets.ClassDescriptor := _Get(_JsonGetInt(j, "Instance", "ClassDescriptor"), Offsets.ClassDescriptor)
        Offsets.ClassName := _Get(_JsonGetInt(j, "Instance", "ClassName"), Offsets.ClassName)
        Offsets.Workspace := _Get(_JsonGetInt(j, "DataModel", "Workspace"), Offsets.Workspace)
        Offsets.CurrentCamera := _Get(_JsonGetInt(j, "Workspace", "CurrentCamera"), Offsets.CurrentCamera)
        Offsets.LocalPlayer := _Get(_JsonGetInt(j, "Player", "LocalPlayer"), Offsets.LocalPlayer)
        Offsets.ModelInstance := _Get(_JsonGetInt(j, "Player", "ModelInstance"), Offsets.ModelInstance)
        Offsets.HumanoidRootPart := _Get(_JsonGetInt(j, "Humanoid", "HumanoidRootPart"), Offsets.HumanoidRootPart)
        Offsets.Primitive := _Get(_JsonGetInt(j, "BasePart", "Primitive"), Offsets.Primitive)
        Offsets.PrimitivePosition := _Get(_JsonGetInt(j, "Primitive", "Position"), Offsets.PrimitivePosition)
        Offsets.AssemblyLinearVelocity := _Get(_JsonGetInt(j, "Primitive", "AssemblyLinearVelocity"), Offsets.AssemblyLinearVelocity)

        AddLog("Offsets updated OK")
    } catch as e {
        AddLog("Offset fetch error: " e.Message)
    }
}

; ============================================
; MEMORY CLASS
; ============================================

class Memory {
    __New(procName) {
        this.pid := ProcessExist(procName)
        if !this.pid
            throw Error("Process not found: " procName)
        this.h := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", 0, "UInt", this.pid, "Ptr")
        if !this.h
            throw Error("OpenProcess failed")
        this.baseAddr := this.GetModuleBase()
    }

    GetModuleBase() {
        snap := DllCall("CreateToolhelp32Snapshot", "UInt", 0x8, "UInt", this.pid, "Ptr")
        if snap = -1
            return 0
        me32 := Buffer(1080, 0)
        NumPut("UInt", 1080, me32, 0)
        if !DllCall("Module32FirstW", "Ptr", snap, "Ptr", me32) {
            DllCall("CloseHandle", "Ptr", snap)
            return 0
        }
        base := NumGet(me32, 0x18, "Ptr")
        DllCall("CloseHandle", "Ptr", snap)
        return base
    }

    Read(addr, type := "UInt64") {
        if addr <= 0
            return 0
        size := (type = "Float" || type = "UInt" || type = "Int") ? 4 : 8
        buf := Buffer(size, 0)
        DllCall("ntdll\NtReadVirtualMemory", "Ptr", this.h, "Ptr", addr, "Ptr", buf, "UPtr", size, "UPtr*", 0, "UInt")
        return NumGet(buf, 0, type)
    }

    ReadString(addr) {
        len := this.Read(addr + 0x10, "Int")
        if len <= 0 || len > 10000
            return ""
        if len >= 16
            addr := this.Read(addr, "UInt64")
        if addr <= 0
            return ""
        buf := Buffer(len + 1, 0)
        DllCall("ntdll\NtReadVirtualMemory", "Ptr", this.h, "Ptr", addr, "Ptr", buf, "Ptr", len, "Ptr", 0)
        return StrGet(buf, "UTF-8")
    }

    Close() {
        if this.h
            DllCall("CloseHandle", "Ptr", this.h)
        this.h := 0
    }
}

; ============================================
; INSTANCE HELPERS
; ============================================

GetChildren(inst) {
    global mem
    if !inst
        return []
    out := []
    ptr := mem.Read(inst + Offsets.ChildrenStart, "UInt64")
    if !ptr
        return out
    start := mem.Read(ptr, "UInt64")
    endPtr := mem.Read(ptr + Offsets.ChildrenEnd, "UInt64")
    if !start || !endPtr
        return out
    cur := start
    loop 1000 {
        if cur >= endPtr
            break
        child := mem.Read(cur, "UInt64")
        if child && child != inst
            out.Push(child)
        cur += 0x10
    }
    return out
}

FindChild(inst, name) {
    global mem
    for child in GetChildren(inst)
        if GetName(child) = name
            return child
    return 0
}

FindChildOfClass(inst, className) {
    global mem
    for child in GetChildren(inst)
        if GetClassName(child) = className
            return child
    return 0
}

GetName(inst) {
    global mem
    if !inst
        return ""
    nameContainer := mem.Read(inst + Offsets.NameContainer, "UInt64")
    if !nameContainer
        return ""
    return mem.ReadString(nameContainer + Offsets.Name)
}

GetClassName(inst) {
    global mem
    if !inst
        return ""
    desc := mem.Read(inst + Offsets.ClassDescriptor, "UInt64")
    if !desc
        return ""
    classNamePtr := mem.Read(desc + Offsets.ClassName, "UInt64")
    return classNamePtr ? mem.ReadString(classNamePtr) : ""
}

; ============================================
; GUI (MODERN NEON DARK THEME + STYLISH INPUTS)
; ============================================

mainGui := Gui("-MaximizeBox +AlwaysOnTop", "MelxSoruMacro")
mainGui.BackColor := "0x181818"

mainGui.SetFont("s13 Bold c0x00E5FF", "Segoe UI")
mainGui.Add("Text", "x15 y15 w375 Center", "⚡ MelxSoruMacro ⚡")

mainGui.SetFont("s9 Bold c0x00FFCC", "Segoe UI")
mainGui.Add("Text", "x20 y52", "⚙️  KEY & DISTANCE SETTINGS")

mainGui.SetFont("s9 c0xE0E0E0", "Segoe UI")
mainGui.Add("Text", "x30 y80", "⌨️ Auto Key Selected:")
ddKey := mainGui.Add("DropDownList", "x180 y76 w90 vConfigKey Background0x222222 c0xFFFFFF", ["z", "x", "c", "v"])
ddKey.Text := "z"

mainGui.Add("Text", "x30 y115", "🎯 Min Distance (studs):")
edDistThreshold := mainGui.Add("Edit", "x180 y111 w90 vSoruDistThreshold Number Background0x222222 c0x00FFFF", "20")

btnStart := mainGui.Add("Button", "x20 y155 w170 h38", "▶ START (F1)")
btnStart.SetFont("s10 Bold c0x006633", "Segoe UI")
btnStart.OnEvent("Click", StartLoop)

btnStop := mainGui.Add("Button", "x205 y155 w170 h38", "■ STOP (F2)")
btnStop.SetFont("s10 Bold c0x660000", "Segoe UI")
btnStop.OnEvent("Click", StopLoop)

mainGui.SetFont("s10 Bold c0x00FF88", "Segoe UI")
mainGui.Add("Text", "x20 y205 w355 vStatusText Center", "🟢 Status: IDLE")

mainGui.SetFont("s9 Bold c0x00FFCC", "Segoe UI")
mainGui.Add("Text", "x20 y235", "💻 SYSTEM LOGS CONSOLE")

mainGui.SetFont("s9 c0x00FF66", "Consolas")
global debugLog := mainGui.Add("Edit", "x20 y255 w355 h110 vDebugLog ReadOnly -VScroll Background0x0D0D0D c0x00FF66", "")

mainGui.Show("w395 h385")

F1::StartLoop()
F2::StopLoop()
XButton2::CycleKeyAndReattach()

; ============================================
; KEY SWITCHING + TOOLTIP + INITIALIZATION
; ============================================

CycleKeyAndReattach(*) {
    global configKey, ddKey
    keys := ["z", "x", "c", "v"]
    idx := 1
    for i, k in keys {
        if (k = configKey) {
            idx := Mod(i, keys.Length) + 1
            break
        }
    }
    configKey := keys[idx]
    ddKey.Text := configKey
    AddLog("Key changed to: " configKey)
    ShowKeyTooltip()
    InitRoblox()
}

ShowKeyTooltip() {
    global configKey
    MouseGetPos &mx, &my
    ToolTip("Key: " StrUpper(configKey) "`nApplying: " StrUpper(configKey), mx + 20, my + 20, 20)
    SetTimer(HideTooltip, -1500)
}

HideTooltip() {
    ToolTip(,, , 20)
}

; ============================================
; CORE LOGIC
; ============================================

CheckSoru() {
    global isRunning, lastKnownPos, posInitialized, soruDistThreshold, soruCooldown, configKey, keysPressed

    if (!isRunning)
        return

    rDown := GetKeyState("R", "P")

    RefreshCharacter()
    curPos := ReadPosition()
    if (curPos.x = 0 && curPos.y = 0 && curPos.z = 0)
        return

    if (!posInitialized) {
        lastKnownPos := curPos
        posInitialized := true
        return
    }

    dist := Distance3D(lastKnownPos, curPos)

    if (dist > soruDistThreshold && rDown && A_TickCount > soruCooldown) {
        soruCooldown := A_TickCount + 500
        Loop 5 {
            SendInput "{" configKey "}"
        }
        keysPressed += 5
        UpdateStatus("SORU → " configKey " x5 | Dist: " Round(dist) " | Total: " keysPressed)
    }

    lastKnownPos := curPos
}

UpdateStatus(msg) {
    global mainGui
    try mainGui["StatusText"].Value := "🟢 Status: " msg
}

InitRoblox() {
    global mem, baseAddr, dataModel, workspace, players, localPlayer, character, humanoid

    ClearDebug()
    AddLog("=== INIT ROBLOX ===")

    try {
        if mem
            mem.Close()
        mem := Memory("RobloxPlayerBeta.exe")
        AddLog("PID: " mem.pid)
    } catch as e {
        AddLog("ERROR: " e.Message)
        return false
    }

    baseAddr := mem.baseAddr
    if !baseAddr {
        AddLog("ERROR: baseAddr = 0")
        return false
    }

    fakeDM := mem.Read(baseAddr + Offsets.FakeDataModelPtr, "UInt64")
    if !fakeDM {
        AddLog("ERROR: FakeDM = 0")
        return false
    }

    dataModel := mem.Read(fakeDM + Offsets.RealDataModel, "UInt64")
    if !dataModel {
        AddLog("ERROR: DataModel = 0")
        return false
    }

    workspace := mem.Read(dataModel + Offsets.Workspace, "UInt64")
    if !workspace {
        AddLog("ERROR: Workspace = 0")
        return false
    }

    players := FindChild(dataModel, "Players")
    if !players {
        AddLog("ERROR: Players = 0")
        return false
    }

    localPlayer := mem.Read(players + Offsets.LocalPlayer, "UInt64")
    if !localPlayer {
        AddLog("ERROR: LocalPlayer = 0")
        return false
    }

    AddLog("=== INIT SUCCESS ===")
    return true
}

RefreshCharacter() {
    global mem, localPlayer, character, humanoid

    if !localPlayer
        return false

    character := mem.Read(localPlayer + Offsets.ModelInstance, "UInt64")
    if !character
        return false

    humanoid := FindChildOfClass(character, "Humanoid")
    return true
}

ReadPosition() {
    global mem, character

    if !character
        return {x: 0.0, y: 0.0, z: 0.0}

    hrp := FindChild(character, "HumanoidRootPart")
    if !hrp
        return {x: 0.0, y: 0.0, z: 0.0}

    prim := mem.Read(hrp + Offsets.Primitive, "UInt64")
    if !prim
        return {x: 0.0, y: 0.0, z: 0.0}

    posAddr := prim + Offsets.PrimitivePosition
    return {
        x: mem.Read(posAddr, "Float"),
        y: mem.Read(posAddr + 4, "Float"),
        z: mem.Read(posAddr + 8, "Float")
    }
}

Distance3D(a, b) {
    dx := a.x - b.x
    dy := a.y - b.y
    dz := a.z - b.z
    return Sqrt(dx * dx + dy * dy + dz * dz)
}

StartLoop(*) {
    global isRunning, configKey, soruDistThreshold, ddKey, edDistThreshold, posInitialized

    configKey := ddKey.Text
    soruDistThreshold := Float(edDistThreshold.Text)

    UpdateStatus("Fetching latest offsets...")
    AutoUpdateOffsets()

    UpdateStatus("Connecting to Roblox...")
    if (!InitRoblox()) {
        UpdateStatus("ERROR: Init failed - check debug log")
        return
    }

    try {
        RefreshCharacter()
        isRunning := true
        posInitialized := false
        SetTimer(CheckSoru, 1)
        UpdateStatus("RUNNING | Key: " configKey " | Dist: " soruDistThreshold)
    } catch as e {
        UpdateStatus("ERROR: " e.Message)
    }
}

StopLoop(*) {
    global isRunning
    isRunning := false
    SetTimer(CheckSoru, 0)
    UpdateStatus("STOPPED")
}

OnExit(ExitFunc)

ExitFunc(ExitReason, ExitCode) {
    global mem
    if mem && mem.h
        DllCall("CloseHandle", "Ptr", mem.h)
    DllCall("Winmm\timeEndPeriod", "UInt", 1)
}
