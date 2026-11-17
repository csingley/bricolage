# shellcheck shell=bash
# Lock the screen with gtklock. `-d` detaches once locked; the pgrep guard avoids
# stacking lockers when both the `lock` and `before-sleep` events fire.
# PATH: gdk-pixbuf (glycin) execs `bwrap` via PATH; swayidle's service PATH lacks
# it, GTK aborts, sway goes red. LC_MESSAGES makes gtklock's translation lookup
# (the "Hello PIN:" label) work even if the service env has no LANG.
#
# Usage: lock [before-sleep|after-resume]
#   (none)        lock now, unless gtklock is already up
#   before-sleep  lock, and note that the machine went to sleep locked
#   after-resume  if it did, and gtklock is gone, lock again. gtklock (4.0.0) can crash as the
#                 machine enters sleep (a GTK assertion in its revealer, then a segfault); sway
#                 keeps the session locked with no locker, which shows as a bright red screen
#                 that takes no input. sway accepts a new locker over a dead one, so starting
#                 gtklock again brings the lock screen back.
#
# Requires (outside Nix):
#   distro gtklock
#   base  procps - pgrep
marker="${XDG_RUNTIME_DIR:-/tmp}/bricolage-locked-for-sleep"

lock() {
  /usr/bin/pgrep -x gtklock >/dev/null || PATH=/usr/bin:/bin LC_MESSAGES=en_US.UTF-8 /usr/bin/gtklock -d
}

case "${1-}" in
  before-sleep)
    : >"$marker"
    lock
    ;;
  after-resume)
    [ -e "$marker" ] || exit 0
    rm -f "$marker"
    # The outputs are still coming back and a dying gtklock may not be gone yet: look, start, and
    # look again, a few times. A locker that survives a second is a good one.
    for _ in 1 2 3 4 5; do
      /usr/bin/sleep 1
      lock || true
      /usr/bin/sleep 1
      /usr/bin/pgrep -x gtklock >/dev/null && exit 0
    done
    exit 1
    ;;
  *) lock ;;
esac
