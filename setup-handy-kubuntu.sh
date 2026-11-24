#!/usr/bin/env bash
# Set up Handy (offline push-to-talk dictation) on Kubuntu.
# Run as your normal user (not with sudo); it asks for sudo when needed.
set -euo pipefail

VER="0.10.2"
DEB="Handy_${VER}_amd64.deb"
SHA="b0068b6b8971a7842a0362d7adefda7a491a208605067ee3bf1711758200a5b4"
URL="https://github.com/cjpais/Handy/releases/download/v${VER}/${DEB}"

[ "$(id -u)" -ne 0 ] || { echo "Run this as your normal user, not root."; exit 1; }
[ "$(uname -m)" = "x86_64" ] || { echo "This script is for x86_64; see the Handy releases page for ARM."; exit 1; }

SESSION="${XDG_SESSION_TYPE:-unknown}"
echo "==> Session type: $SESSION"

echo "==> Downloading Handy $VER"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
curl -fL --retry 3 -o "$WORK/$DEB" "$URL"
echo "$SHA  $WORK/$DEB" | sha256sum -c -

echo "==> Installing Handy and its runtime library"
sudo apt-get update
sudo apt-get install -y "$WORK/$DEB" libgtk-layer-shell0

if [ "$SESSION" = "x11" ]; then
  echo "==> X11: installing xdotool for typing into other apps"
  sudo apt-get install -y xdotool
else
  echo "==> Wayland: setting up ydotool (wtype does not work on KDE)"
  sudo apt-get install -y ydotool
  if dpkg -s wtype >/dev/null 2>&1; then
    echo "    Removing wtype so Handy uses ydotool instead"
    sudo apt-get remove -y wtype
  fi
  if ! command -v ydotoold >/dev/null 2>&1; then
    echo "!!  ydotoold (the ydotool daemon) is not in this distro's package."
    echo "    Handy can still paste via the clipboard: Settings > Advanced >"
    echo "    Paste Method > 'Clipboard (CTRL+Shift+V)'. Continuing."
  else
    # Let members of the 'input' group use /dev/uinput, which ydotool needs.
    echo 'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' \
      | sudo tee /etc/udev/rules.d/80-uinput.rules >/dev/null
    echo uinput | sudo tee /etc/modules-load.d/uinput.conf >/dev/null
    sudo modprobe uinput
    sudo udevadm control --reload-rules
    sudo udevadm trigger --name-match=uinput || true
    NEED_RELOGIN=0
    if ! id -nG "$USER" | grep -qw input; then
      sudo usermod -aG input "$USER"
      NEED_RELOGIN=1
    fi

    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/ydotoold.service" <<EOF
[Unit]
Description=ydotool daemon

[Service]
ExecStart=$(command -v ydotoold)
Restart=on-failure

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable ydotoold.service
    if [ "$NEED_RELOGIN" -eq 0 ]; then
      systemctl --user restart ydotoold.service || true
    fi
  fi
fi

cat <<'EOF'

==> Done installing. Next steps:
 1. If you were just added to the 'input' group, log out and back in first.
 2. Start Handy from the app menu, grant the microphone, and let it download
    a model (Parakeet V3 is a good default).
 3. Set a global shortcut in KDE (Wayland needs this):
    System Settings > Shortcuts > Add New > Command (or Custom Shortcuts),
    command:  handy --toggle-transcription   key: e.g. Meta+H
 4. Test: open Kate or Claude, press the shortcut, speak, press it again.
    If no text appears, set Handy > Settings > Advanced > Paste Method to
    "Clipboard (CTRL+Shift+V)" and try again.
EOF
