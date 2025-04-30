local wallpaper = "trees.png"

require("beanpaper").Apply {
    -- ipc = true,
    -- splash = false,
    prefix = "~/Pictures",
    monitors = {
        -- { "output name", wallpaper, contain = true, tile = false, useprefix = true }
        { "LVDS-1",   wallpaper },
        { "HDMI-A-1", wallpaper },
        { "VGA-1",    wallpaper }
    }
}
