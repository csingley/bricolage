# shellcheck shell=bash
# Lock the screen with gtklock. `-d` detaches once locked; the pgrep guard avoids
# stacking lockers when both the `lock` and `before-sleep` events fire.
# PATH: gdk-pixbuf (glycin) execs `bwrap` via PATH; swayidle's service PATH lacks
# it, GTK aborts, sway goes red. LC_MESSAGES makes gtklock's translation lookup
# (the "Hello PIN:" label) work even if the service env has no LANG.
#
# Requires (outside Nix):
#   distro gtklock
#   base  procps - pgrep
/usr/bin/pgrep -x gtklock || PATH=/usr/bin:/bin LC_MESSAGES=en_US.UTF-8 /usr/bin/gtklock -d
