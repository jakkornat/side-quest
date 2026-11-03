#!/usr/bin/env lua

-- Standard Lua only: no LuaRocks packages or global environment changes.
local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function command(arguments)
    local parts = {}
    for index, value in ipairs(arguments) do
        parts[index] = quote(value)
    end
    return table.concat(parts, " ")
end

local function succeeded(result)
    -- Lua 5.1 returns a numeric status; Lua 5.2+ returns true on success.
    return result == true or result == 0
end

local function run(arguments)
    local invocation = command(arguments)
    if not succeeded(os.execute(invocation)) then
        error("Command failed: " .. invocation, 0)
    end
end

local function capture(invocation)
    local process, message = io.popen(invocation, "r")
    if not process then
        error("Unable to run command: " .. tostring(message), 0)
    end
    local output = process:read("*a")
    if not succeeded(process:close()) then
        error("Command failed: " .. invocation, 0)
    end
    return output:gsub("[\r\n]+$", "")
end

local scriptDirectory = arg[0]:match("^(.*)/[^/]+$") or "."
local root = capture("cd " .. quote(scriptDirectory .. "/..") .. " && /bin/pwd -P")
local buildDirectory = root .. "/.build"
local app = root .. "/dist/Side Quest.app"

local function swiftBuildArguments()
    return {
        "/usr/bin/env",
        "CLANG_MODULE_CACHE_PATH=" .. buildDirectory .. "/ModuleCache",
        "SWIFTPM_MODULECACHE_OVERRIDE=" .. buildDirectory .. "/ModuleCache",
        "swift", "build",
        "--package-path", root,
        "--arch", "arm64",
        "-c", "release",
        "-debug-info-format", "none",
        "--disable-sandbox",
        "--scratch-path", buildDirectory,
        "--cache-path", buildDirectory .. "/cache",
        "--config-path", buildDirectory .. "/config",
        "--security-path", buildDirectory .. "/security",
    }
end

local binPathArguments = swiftBuildArguments()
binPathArguments[#binPathArguments + 1] = "--show-bin-path"
local binPath = capture(command(binPathArguments))
if binPath == "" then
    error("Swift did not return the build output directory.", 0)
end

-- SwiftPM can leave removed resources in an incremental build's bundle.
-- Recreate it so private audio from older builds cannot reach the release.
run({"rm", "-rf", binPath .. "/SideQuest_SideQuest.bundle"})
run(swiftBuildArguments())

-- Replacing the whole generated app also removes obsolete resources and signatures.
run({"rm", "-rf", app})
run({"mkdir", "-p", app .. "/Contents/MacOS", app .. "/Contents/Resources"})
run({"cp", binPath .. "/SideQuest", app .. "/Contents/MacOS/SideQuest"})
run({"cp", root .. "/Resources/Info.plist", app .. "/Contents/Info.plist"})
run({"cp", root .. "/LICENSE", app .. "/Contents/Resources/LICENSE"})

local iconPath = root .. "/Resources/AppIcon.icns"
local icon = io.open(iconPath, "rb")
if icon then
    icon:close()
    run({"cp", iconPath, app .. "/Contents/Resources/AppIcon.icns"})
end

run({"ditto", binPath .. "/SideQuest_SideQuest.bundle", app .. "/Contents/Resources/SideQuest_SideQuest.bundle"})
run({"codesign", "--force", "--sign", "-", app})
print("Done: " .. app)
