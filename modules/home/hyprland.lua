-- Hyprland (0.55, Lua config) with the Noctalia shell.
-- Based on Hyprland 0.55.4's example/hyprland.lua and Noctalia's Hyprland guide.
-- Home Manager appends this file to the generated ~/.config/hypr/hyprland.lua.

------------------------------------------------------------------ monitors
-- Laptop panel at native scale; anything plugged in gets its preferred mode and an
-- automatic scale. Tune per screen with hyprctl, then copy the result here.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1 })

------------------------------------------------------------------ programs
local terminal    = "ghostty"
local fileManager = "nautilus"
local ipc         = "noctalia msg "
local screenshots = "$HOME/Pictures/Screenshots"

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

------------------------------------------------------------------ autostart
hl.on("hyprland.start", function()
    hl.exec_cmd("hyprlock")                          -- the disk passphrase got us here; lock until the user password
    hl.exec_cmd("noctalia")                          -- bar, launcher, notifications, control centre
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("mkdir -p " .. screenshots)
    -- First login only: finish setup (GitHub sign-in, private config) in a terminal.
    -- `test`, not `[ ... ]`: Hyprland reads a leading [...] in exec as window rules.
    hl.exec_cmd("test -e \"$HOME/.local/state/nixos-setup/done\" || " .. terminal .. " --title='Finish setup' -e nixos-finish-setup")
end)

------------------------------------------------------------------ look
hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 10,
        border_size = 2,
        col = {
            active_border   = { colors = {"rgba(7cc0f5ee)", "rgba(9b8cf0ee)"}, angle = 45 },
            inactive_border = "rgba(3a3f4baa)",
        },
        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding       = 20,
        rounding_power = 2,
        active_opacity   = 1.0,
        inactive_opacity = 1.0,
        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },
        blur = {
            enabled  = true,
            size     = 3,
            passes   = 2,
            vibrancy = 0.1696,
        },
    },
    animations = {
        enabled = true,
    },
    dwindle = {
        preserve_split = true,
    },
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
    },
    input = {
        kb_layout    = "gb",
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = {
            natural_scroll = false,
        },
    },
})

hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1},  {0.32, 1} } })
hl.curve("linear",       { type = "bezier", points = { {0, 0},     {1, 1}    } })
hl.curve("almostLinear", { type = "bezier", points = { {0.5, 0.5}, {0.75, 1} } })
hl.curve("quick",        { type = "bezier", points = { {0.15, 0},  {0.1, 1}  } })
hl.curve("easy",         { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })

hl.animation({ leaf = "global",     enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",     enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",    enabled = true, speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn",  enabled = true, speed = 4.1,  spring = "easy",   style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fade",       enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",     enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

------------------------------------------------------------------ keys
local mainMod = "SUPER"

-- Apps and the shell
hl.bind(mainMod .. " + T",      hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E",      hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + Space",  hl.dsp.exec_cmd(ipc .. "panel-toggle launcher"))
hl.bind(mainMod .. " + S",      hl.dsp.exec_cmd(ipc .. "panel-toggle control-center"))
hl.bind(mainMod .. " + comma",  hl.dsp.exec_cmd(ipc .. "settings-toggle"))
hl.bind("ALT + Tab",            hl.dsp.exec_cmd(ipc .. "window-switcher"))
hl.bind(mainMod .. " + L",      hl.dsp.exec_cmd("hyprlock"))

-- Windows
hl.bind(mainMod .. " + Q",      hl.dsp.window.close())
hl.bind(mainMod .. " + V",      hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + F",      hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mainMod .. " + P",      hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J",      hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + left",   hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right",  hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",     hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",   hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Workspaces 1-10 (0 is 10)
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end
hl.bind(mainMod .. " + grave",         hl.dsp.workspace.toggle_special("scratch"))
hl.bind(mainMod .. " + SHIFT + grave", hl.dsp.window.move({ workspace = "special:scratch" }))
hl.bind(mainMod .. " + mouse_down",    hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",      hl.dsp.focus({ workspace = "e-1" }))

-- Screenshots go to a host folder; move them into an env with the copy command.
hl.bind("Print",         hl.dsp.exec_cmd("sh -c 'f=" .. screenshots .. "/$(date +%Y-%m-%d_%H-%M-%S).png; grim -g \"$(slurp)\" \"$f\" && wl-copy < \"$f\"'"))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("sh -c 'f=" .. screenshots .. "/$(date +%Y-%m-%d_%H-%M-%S).png; grim \"$f\" && wl-copy < \"$f\"'"))

-- Media and brightness keys through Noctalia, so its on-screen display shows them
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd(ipc .. "volume-up"),       { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd(ipc .. "volume-down"),     { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd(ipc .. "volume-mute"),     { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(ipc .. "brightness-up"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(ipc .. "brightness-down"), { locked = true, repeating = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- Lid: with power or a screen attached, logind doesn't suspend; turn the panel off
-- while the lid is shut and back on when it opens.
hl.bind("switch:on:Lid Switch",  function() hl.monitor({ output = "eDP-1", disabled = true }) end, { locked = true })
hl.bind("switch:off:Lid Switch", function() hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = 1 }) end, { locked = true })

------------------------------------------------------------------ rules
hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})
