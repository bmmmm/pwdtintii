# Opt-in short aliases for pwdtintii (bash variant). Source AFTER the plugin:
#   source ~/path/to/pwdtintii/pwdtintii.plugin.bash
#   source ~/path/to/pwdtintii/examples/aliases.bash

# `pt` is the entry point: bare `pt` opens the fzf action menu, `pt <cmd>`
# dispatches (pick / view / list / auto / off / reload / contrast / doctor / help).
alias pt='pwdtintii'
alias ptpick='pwdtintii_pick'
alias ptlist='pwdtintii_list'
alias ptreload='pwdtintii_reload'

# ptview goes through the dispatcher so it carries the family header + tint restore
alias ptview='pwdtintii view'
alias ptcontrast='"${_pwdtintii_self}/scripts/contrast-check.sh"'
