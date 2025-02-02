-- Pull in the wezterm API
local wezterm = require 'wezterm'
-- This will hold the configuration.
local config = wezterm.config_builder()
-- Others
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "NONE"
-- and finally, return the configuration to wezterm
return config
