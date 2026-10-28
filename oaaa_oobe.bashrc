
if ! [ -e ~/.oaaa-firstboot ]; then
  choose() {
    gum choose --header.foreground="" --selected.foreground="" --cursor.foreground="" --no-show-help --header=""
  }
  sleep 10
  while true; do
    choices="Set up your user\nShell\nRoot Shell\nManual Setup\n"
    if mountpoint -q /oaaa 2>/dev/null; then
      choices="${choices}Load OAAAT\nReboot to OAAAT\n"
    fi
    if ! curl -sS -o /dev/null --max-time 3 http://connectivitycheck.gstatic.com/generate_204 >/dev/null 2>&1; then
      choices="${choices}Configure Internet\n"
    fi
    choices="${choices}Reboot\nShutdown\n"
    choice="$(printf "$choices"|choose)"
    if [ "$choice" = "Set up your user" ]; then
      clear
      echo "Welcome to oaaa! - OOBE - User - Username"
      printf "Choose a username: "
      read NEW
      [ -z "$NEW" ] && { echo "Choosing default: user"; NEW=user; }
      clear
      echo "Welcome to oaaa! - OOBE - User - Password"
      echo "Please choose a password for your user account:"
      sudo passwd oobe
      clear
      echo "Welcome to oaaa! - OOBE - User - Admin Password"
      echo "Please choose a password for the admin (root) account:"
      sudo passwd
      if ! curl -sS -o /dev/null --max-time 3 http://connectivitycheck.gstatic.com/generate_204 >/dev/null 2>&1; then
        clear
        echo "Welcome to oaaa! - OOBE - Networking"
        read -r -p "Would you like to connect to/configure the internet? [Y/n] " response
        if ! [[ "$response" =~ ^([Nn][oO]|[Nn])$ ]]; then
          nmtui
        fi
      fi
      clear
      echo "Welcome to oaaa! - OOBE - Configuring"
      echo "_______________________________________________________________________________"
      echo "[fancy user setup happening... please wait! This will take less than a minute.]"
      echo "[after the user setup, the system will reboot.________________________________]"
      sudo systemctl enable plasmalogin
      sudo chsh -s /usr/bin/zsh oobe
      sudo rm -rf /etc/systemd/system/getty@tty1.service.d
      touch ~/.oaaa-firstboot
      sudo mv /home/oobe "/home/$NEW"
      sudo sed -i "s|oobe|$NEW|g" /etc/passwd /etc/shadow /etc/group /etc/gshadow
      sudo systemctl reboot 2>/dev/null >/dev/null
      sleep infinity
    elif [ "$choice" = "Shell" ]; then
      break
    elif [ "$choice" = "Root Shell" ]; then
      sudo su
    elif [ "$choice" = "Manual Setup" ]; then
      echo "Are you sure? This will rename your account to 'user', disable the OOBE, and drop you into a root shell."
      if [ "$(printf 'Cancel\nYes\n'|choose)" = "Yes" ]; then
        sudo rm -rf /etc/systemd/system/getty@tty1.service.d
        touch ~/.oaaa-firstboot
        sudo mv /home/oobe /home/user
        sudo sed -i "s|oobe|user|g" /etc/passwd /etc/shadow /etc/group /etc/gshadow
        exec sudo su
      fi
    elif [ "$choice" = "Load OAAAT" ]; then
      sudo /oaaa/oaaat
    elif [ "$choice" = "Reboot to OAAAT" ]; then
      sudo /oaaa/boot-to-oaaat
    elif [ "$choice" = "Configure Internet" ]; then
      nmtui
    elif [ "$choice" = "Reboot" ]; then
      sudo reboot
    elif [ "$choice" = "Shutdown" ]; then
      sudo shutdown now
    fi
  done
fi