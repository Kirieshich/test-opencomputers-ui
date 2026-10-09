-- installer.lua
-- STARGATE Command Interface Installer
-- Usage: installer.lua

local component = require("component")
local serialization = require("serialization")
local filesystem = require("filesystem")
local shell = require("shell")
local term = require("term")
local internet = nil
local HasInternet = component.isAvailable("internet")
if HasInternet then internet = require("internet") end

-- ============================================================
-- НАСТРОЙКИ РЕПОЗИТОРИЯ — ОТРЕДАКТИРУЙ ПОД СЕБЯ!
-- ============================================================
local GITHUB_USER   = "Kirieshich"
local GITHUB_REPO   = "test-opencomputers-ui"
local GITHUB_BRANCH = "main"

local BranchURL = "https://raw.githubusercontent.com/" ..
                  GITHUB_USER .. "/" .. GITHUB_REPO .. "/" ..
                  GITHUB_BRANCH

local InstallDir = "/stargate"
local ReleaseVersionsFile = InstallDir .. "/releaseVersions.ff"
local ReleaseVersions = nil

local args, opts = shell.parse(...)

local function onlineCheck()
    if not HasInternet then
        io.stderr:write("ERROR: No Internet Card installed.\n")
        os.exit(false)
    end
end

local function createInstallDirectory()
    if not filesystem.isDirectory(InstallDir) then
        print("Creating " .. InstallDir .. " directory...")
        local success, msg = filesystem.makeDirectory(InstallDir)
        if success == nil then
            io.stderr:write("Failed to create " .. InstallDir .. ": " .. msg .. "\n")
            os.exit(false)
        end
    end
end

local function checkForExistingInstall()
    if filesystem.exists(InstallDir .. "/stargate.lua") then
        print([[
+---------------------------------------------+
| An existing STARGATE installation was found.|
| Would you like to reinstall?                |
+---------------------------------------------+]])
        term.setCursorBlink(true)
        io.write(" Yes/No: ")
        local userInput = io.read("*l")
        if (userInput:lower()):sub(1, 1) ~= "y" then
            print("Cancelling installation.")
            os.exit(true)
        end
    end
end

local function downloadFile(fileName, savePath)
    savePath = savePath or fileName
    print("Downloading: " .. fileName)
    local response = internet.request(BranchURL .. "/" .. fileName)
    local isGood, err = pcall(function()
        local file, ferr = io.open(savePath, "w")
        if file == nil then error(ferr) end
        for chunk in response do
            file:write(chunk)
        end
        file:close()
    end)
    if not isGood then
        io.stderr:write("Failed to download " .. fileName .. "\n")
        io.stderr:write(tostring(err) .. "\n")
        os.exit(false)
    end
end

local function downloadManifestedFiles(program)
    for _, path in ipairs(program.manifest) do
        downloadFile(path, InstallDir .. "/" .. path)
    end
end

local function downloadNeededFiles()
    print("Downloading files, please wait...")
    downloadFile("releaseVersions.ff", ReleaseVersionsFile)
    local file = io.open(ReleaseVersionsFile, "r")
    ReleaseVersions = serialization.unserialize(file:read("*a"))
    file:close()

    downloadManifestedFiles(ReleaseVersions.program)

    local vfile = io.open(InstallDir .. "/installedVersions.ff", "w")
    vfile:write(serialization.serialize(ReleaseVersions.program))
    vfile:close()
end

local function createSystemShortcut()
    local shortcut = [[
shell = require("shell")
filesystem = require("filesystem")

local args, opts = shell.parse(...)

if filesystem.exists("/stargate/stargate.lua") then
    local options = "-"
    for k, v in pairs(opts) do options = options .. tostring(k) end
    shell.execute("/stargate/stargate.lua " .. options)
else
    io.stderr:write("STARGATE is not installed correctly.\n")
end
]]
    local file = io.open("/bin/stargate.lua", "w")
    file:write(shortcut)
    file:close()
end

onlineCheck()
createInstallDirectory()
checkForExistingInstall()
downloadNeededFiles()
createSystemShortcut()

print("")
print("Changes:")
if ReleaseVersions and ReleaseVersions.program and ReleaseVersions.program.note then
    for _, line in ipairs(ReleaseVersions.program.note) do
        print("  - " .. line)
    end
end
print("")
print("Installation complete!")
print("Use the 'stargate' command to launch.")