# Opt-in short aliases for pwdtintii (bash variant). Source AFTER the plugin:
#   source ~/path/to/pwdtintii/pwdtintii.plugin.bash
#   source ~/path/to/pwdtintii/examples/aliases.bash

# `pt` is the entry point: bare `pt` opens the fzf action menu, `pt <cmd>`
# dispatches (pick / list / auto / reload / preview / contrast / help).
alias pt='pwdtintii'
alias ptpick='pwdtintii_pick'
alias ptlist='pwdtintii_list'
alias ptreload='pwdtintii_reload'

alias ptpreview='"${_pwdtintii_self}/scripts/preview.sh"'
alias ptcontrast='"${_pwdtintii_self}/scripts/contrast-check.sh"'
