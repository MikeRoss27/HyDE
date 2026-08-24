#!/usr/bin/env bash
# @name: control-center
# @short: Unified settings launcher for the HyDE workstation

set -uo pipefail

rofi_menu() {
    local prompt=$1
    shift
    printf '%s\n' "$@" | rofi -dmenu -i -p "$prompt" \
        -theme clipboard \
        -theme-str 'window { width: 620px; } listview { lines: 12; }'
}

launch() {
    setsid "$@" >/dev/null 2>&1 &
}

display_menu() {
    local choice
    choice=$(rofi_menu "Écrans" \
        "󰍹 Résumé des écrans actifs" \
        "󰏫 Modifier placement, résolution et échelle" \
        "󰑐 Recharger la configuration Hyprland") || return 0

    case "$choice" in
        *"Résumé des écrans actifs")
            launch kitty --title "Écrans Hyprland" --hold sh -lc \
                'hyprctl monitors all; printf "\nAppuie sur Entrée pour fermer…"; read -r _'
            ;;
        *"Modifier placement, résolution et échelle")
            if command -v code >/dev/null 2>&1; then
                launch code --reuse-window "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
            else
                launch xdg-open "${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland.lua"
            fi
            ;;
        *"Recharger la configuration Hyprland")
            hyprctl reload config-only >/dev/null
            notify-send "Écrans" "Configuration Hyprland rechargée"
            ;;
    esac
}

login_menu() {
    local choice
    choice=$(rofi_menu "Connexion et utilisateurs" \
        "󰍹 État de l’écran de connexion (SDDM)" \
        "󰒓 Applications par défaut") || return 0

    case "$choice" in
        *"État de l’écran de connexion"*)
            launch kitty --title "Écran de connexion" --hold sh -lc \
                'echo "Service actif :"; systemctl is-active sddm.service; echo; echo "Thème configuré :"; cat /etc/sddm.conf.d/10-theme.conf 2>/dev/null; echo; echo "Pour changer de thème : sudo installer/switch-sddm-theme.sh rainy-room|cyberpunk (depuis le dépôt)"; printf "\nAppuie sur Entrée pour fermer…"; read -r _'
            ;;
        *"Applications par défaut")
            if command -v code >/dev/null 2>&1; then
                launch code --reuse-window "${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
            else
                launch xdg-open "${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
            fi
            ;;
    esac
}

security_menu() {
    local choice
    choice=$(rofi_menu "Sécurité" \
        "󰒃 État de sécurité et du dual boot" \
        "󰿅 Pare-feu" \
        "󰋊 Sécurité du firmware") || return 0

    case "$choice" in
        *"État de sécurité et du dual boot")
            launch kitty --title "Sécurité du poste" --hold hyde-shell security-status
            ;;
        *"Pare-feu")
            launch kitty --title "Pare-feu (firewalld)" --hold sh -lc \
                'firewall-cmd --state; echo; firewall-cmd --list-all; printf "\nAppuie sur Entrée pour fermer…"; read -r _'
            ;;
        *"Sécurité du firmware")
            launch kitty --title "Sécurité du firmware" --hold fwupdmgr security
            ;;
    esac
}

power_menu() {
    local current choice profile
    current=$(powerprofilesctl get 2>/dev/null || printf inconnu)
    choice=$(rofi_menu "Profil actuel : $current" \
        "󰓅 Performance" \
        "󰾅 Équilibré" \
        "󰌪 Économie d’énergie") || return 0

    case "$choice" in
        *Performance) profile=performance ;;
        *Équilibré) profile=balanced ;;
        *"Économie d’énergie") profile=power-saver ;;
        *) return 0 ;;
    esac
    powerprofilesctl set "$profile" && notify-send "Alimentation" "Profil : $profile"
}

main_menu() {
    local choice
    choice=$(rofi_menu "Réglages" \
        "󰍹 Écrans" \
        "󰕾 Son" \
        "󰤨 Réseau" \
        " Bluetooth" \
        "󰌪 Alimentation" \
        "󰏘 Apparence et thèmes" \
        "󰸉 Fond d’écran" \
        "󰍜 Layout Waybar" \
        "󰌾 Connexion et utilisateurs" \
        "󰒃 Sécurité" \
        "󰋼 Informations système" \
        "󰏔 Mises à jour") || return 0

    case "$choice" in
        *Écrans) display_menu ;;
        *Son) launch pavucontrol ;;
        *Réseau) launch nm-connection-editor ;;
        *Bluetooth) launch blueman-manager ;;
        *Alimentation) power_menu ;;
        *"Apparence et thèmes") hyde-shell theme.select ;;
        *"Fond d’écran") hyde-shell wallpaper -GS ;;
        *"Layout Waybar") hyde-shell waybar.py --select-layout ;;
        *"Connexion et utilisateurs") login_menu ;;
        *Sécurité) security_menu ;;
        *"Informations système")
            launch kitty --title "Informations système" --hold fastfetch
            ;;
        *"Mises à jour")
            launch kitty --title "Mises à jour disponibles" --hold sh -lc \
                'checkupdates || echo "Aucune mise à jour (ou pacman-contrib absent)"; printf "\nAppuie sur Entrée pour fermer…"; read -r _'
            ;;
    esac
}

main_menu
