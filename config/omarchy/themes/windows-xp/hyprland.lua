-- Windows XP look and feel settings for Hyprland
local active_border_color = "rgb(245dd7)"
local inactive_border_color = "rgb(7ba4e5)"

hl.config({
  general = {
    gaps_in = 0,       -- No inner gaps
    gaps_out = 0,      -- No outer gaps
    border_size = 3,   -- Thicker classic window borders
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },
  decoration = {
    rounding = 4,      -- Slightly rounded window corners
    shadow = {
      enabled = false, -- No modern drop shadows
    },
    blur = {
      enabled = false, -- No modern translucent blur
    },
  },
})
