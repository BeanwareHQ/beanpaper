local wallpaper = "rasirpiss_day.png"

require("beanpaper").Apply {
    -- ipc = true,
    -- splash = false,
    prefix = "/home/ezntek/Pictures/wallpapers",
    monitors = {
        -- { "output name", wallpaper, contain = true, tile = false, useprefix = true }
        { "LVDS-1",   wallpaper },
        { "HDMI-A-1", wallpaper },
        { "VGA-1",    wallpaper }
    }
}
