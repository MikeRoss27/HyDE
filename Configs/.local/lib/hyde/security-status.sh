#!/usr/bin/env bash
# @name: security-status
# @short: Read-only login, lock, firmware and dual-boot security report

set -uo pipefail

ok() { printf '\033[32m[OK]\033[0m   %s\n' "$1"; }
warn() { printf '\033[33m[INFO]\033[0m %s\n' "$1"; }
bad() { printf '\033[31m[À VOIR]\033[0m %s\n' "$1"; }

printf '%s\n' '== Connexion et verrouillage =='
if systemctl is-active --quiet sddm.service; then
    ok 'SDDM est actif'
else
    bad 'SDDM n’est pas actif'
fi

if grep -Eq '^[[:space:]]*auth.*system-login' /etc/pam.d/sddm 2>/dev/null \
        && grep -Eq 'pam_(unix|faillock)\.so' /etc/pam.d/system-auth 2>/dev/null; then
    ok 'SDDM utilise PAM avec mot de passe et protection faillock'
else
    bad 'Chaîne PAM de SDDM à contrôler'
fi

if grep -Eq '^[[:space:]]*auth[[:space:]].*[[:space:]]include[[:space:]]+login' /etc/pam.d/hyprlock 2>/dev/null; then
    ok 'Hyprlock utilise la chaîne PAM du login'
else
    bad 'Configuration PAM de Hyprlock à contrôler'
fi

if pgrep -u "$(id -u)" -x hypridle >/dev/null; then
    ok 'Hypridle est actif (verrouillage et veille automatiques)'
else
    bad 'Hypridle n’est pas actif dans cette session'
fi

if grep -RiqE '^[[:space:]]*\[Autologin\]' /etc/sddm.conf.d 2>/dev/null; then
    bad 'Une configuration d’autologin SDDM semble présente'
else
    ok 'Aucun autologin SDDM détecté'
fi

printf '\n%s\n' '== Firmware et système =='
boot_status=$(bootctl status 2>&1 || true)
if grep -qi 'Secure Boot: enabled' <<<"$boot_status"; then
    ok 'Secure Boot est activé'
else
    bad 'Secure Boot non confirmé'
fi

if [[ -e /sys/class/tpm/tpm0 ]]; then ok 'TPM 2.0 détecté'; else warn 'TPM non détecté'; fi
if systemctl is-active --quiet firewalld.service; then ok 'Firewalld est actif'; else bad 'Firewalld est inactif'; fi

if [[ -r /sys/module/apparmor/parameters/enabled ]] \
        && grep -qx 'Y' /sys/module/apparmor/parameters/enabled; then
    ok 'AppArmor est activé dans le noyau'
else
    warn 'AppArmor est installé mais non activé dans le noyau'
fi

if lsblk -rno TYPE,FSTYPE,MOUNTPOINTS 2>/dev/null | grep -Eq '^crypt[[:space:]]'; then
    ok 'Un volume chiffré ouvert est détecté'
else
    warn 'Aucun volume LUKS ouvert détecté pour la racine'
fi

printf '\n%s\n' '== Dual boot — contrôle non destructif =='
efi_output=$(efibootmgr 2>/dev/null || true)
if grep -qi 'Windows Boot Manager' <<<"$efi_output"; then
    ok 'Windows Boot Manager est toujours enregistré dans l’UEFI'
else
    bad 'Entrée Windows Boot Manager non détectée'
fi

if findmnt -rn /boot >/dev/null 2>&1 && [[ -d /boot/EFI/Microsoft ]]; then
    ok 'EFI Microsoft est présente sur la partition EFI partagée'
else
    bad 'EFI Microsoft non visible sous /boot/EFI/Microsoft'
fi

if findmnt -rn -o SOURCE / | grep -q 'nvme0n1p5'; then
    ok 'Linux démarre depuis sa partition racine dédiée'
else
    warn "Racine Linux actuelle : $(findmnt -rn -o SOURCE / 2>/dev/null || printf inconnue)"
fi

printf '\nAucune modification n’a été effectuée. Windows, l’EFI et les partitions n’ont pas été touchés.\n'
