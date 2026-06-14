# Opt-in short aliases for pwdtintii. Source AFTER the plugin:
#   source ~/path/to/pwdtintii/pwdtintii.plugin.zsh
#   source ~/path/to/pwdtintii/examples/aliases.zsh
#
# If any of these names collide with your own setup, edit before sourcing.

# `pt` is the entry point: bare `pt` opens the fzf action menu, `pt <cmd>`
# dispatches (pick / list / auto / off / reload / preview / contrast / doctor / help).
alias pt='pwdtintii'
alias ptpick='pwdtintii_pick'
alias ptlist='pwdtintii_list'
alias ptreload='pwdtintii_reload'

# Run the preview script from wherever the plugin lives
alias ptpreview='"${_pwdtintii_self}/scripts/preview.sh"'
alias ptcontrast='"${_pwdtintii_self}/scripts/contrast-check.sh"'
