# vhs tape for docs/demo.gif — the README's above-the-fold demo.
# Regenerate from the repo root:  vhs docs/demo.tape
# (needs `vhs`, which renders OSC 11 background changes since it drives a real
# xterm.js — verified; a plain asciinema/agg pipeline does not.)
#
# The demo pins its families via PWDTINTII_OVERRIDES_FILE so the recording is
# deterministic (hash-derived families would depend on the temp path). ZDOTDIR
# points at a nonexistent dir so the recorded zsh starts rc-less — the real
# ~/.zshrc would inject a prompt theme and its own pwdtintii source.

Output docs/demo.gif

Env ZDOTDIR "/tmp/pt-demo-zdot-none"
Set Shell zsh
Set Width 900
Set Height 420
Set FontSize 16
Set Padding 20
Set TypingSpeed 50ms

Hide
Type "export DEMO=/tmp/pt-demo && rm -rf $DEMO && mkdir -p $DEMO/webapp/.git $DEMO/api/.git $DEMO/dotfiles/.git"
Enter
Type "printf 'webapp\tblue\napi\tpink\ndotfiles\tgreen\npt-demo\tcharcoal\n' > $DEMO/ov.tsv"
Enter
Type "export PWDTINTII_OVERRIDES_FILE=$DEMO/ov.tsv PWDTINTII_SHADES_DIR=$DEMO/shades"
Enter
Type "source ./pwdtintii.plugin.zsh && source ./examples/aliases.zsh"
Enter
Type "setopt interactivecomments && export HOME=$DEMO && PS1='%B%~%b $ ' && cd && clear"
Enter
Show

Sleep 1s
Type "# every repo gets its own terminal background"
Enter
Sleep 800ms
Type "cd ~/webapp"
Enter
Sleep 1800ms
Type "cd ~/api"
Enter
Sleep 1800ms
Type "cd ~/dotfiles"
Enter
Sleep 1800ms
Type "pt list | head -3"
Enter
Sleep 3s
