#!/usr/bin/env bash
# ==============================================================================
#  🌸 RETRO SAKURA / MINIMAL PIXEL - INSTALLATION SCRIPT
#  Target OS: Arch Linux (MangoWM + Quickshell Lite + Alacritty)
# ==============================================================================

set -euo pipefail

# --- Color Scheme & Typography ---
BOLD='\033[1m'
DIM='\033[2m'
SAKURA='\033[38;2;243;166;184m' # #f3a6b8
BORDER='\033[38;2;46;37;56m'    # #2e2538
WHITE='\033[38;2;255;255;255m'
GREEN='\033[38;2;152;195;121m'
YELLOW='\033[38;2;229;192;123m'
RED='\033[38;2;224;108;117m'
RESET='\033[0m'

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_MODULES=("mango" "quickshell" "alacritty" "bin")

banner() {
    cat << "EOF"

  🌸  ██████╗ ███████╗████████╗██████╗  ██████╗ 
      ██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔═══██╗
      ██████╔╝█████╗     ██║   ██████╔╝██║   ██║
      ██╔══██╗██╔══╝     ██║   ██╔══██╗██║   ██║
      ██║  ██║███████╗   ██║   ██║  ██║╚██████╔╝
      ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ 
        S A K U R A   /   M I N I M A L   P I X E L
           M a n g o W M   +   Q u i c k s h e l l
EOF
}

info()    { echo -e "${SAKURA}[+]${RESET} ${BOLD}${WHITE}$1${RESET}"; }
success() { echo -e "${GREEN}[✓]${RESET} ${WHITE}$1${RESET}"; }
warn()    { echo -e "${YELLOW}[!]${RESET} ${YELLOW}$1${RESET}"; }
err()     { echo -e "${RED}[✗]${RESET} ${RED}$1${RESET}" >&2; }
substep() { echo -e "    ${BORDER}↳${RESET} ${DIM}$1${RESET}"; }

# --- Check 1: Distribution & Package Manager ---
check_prerequisites() {
    info "Проверка системных требований..."

    if ! command -v pacman &>/dev/null; then
        err "Менеджер пакетов pacman не найден! Скрипт рассчитан на Arch Linux."
        exit 1
    fi
    success "Arch Linux (pacman) обнаружен."
}

# --- Check 2: Install Mandatory Packages ---
install_dependencies() {
    local packages=(
        base-devel
        git
        cmake
        ninja
        alacritty
        yazi
        ffmpegthumbnailer
        p7zip
        jq
        poppler
        fd
        ripgrep
        fzf
        zoxide
        imagemagick
        swww
        stow
        polkit-kde-agent
        grim
        slurp
        wl-clipboard
        cliphist
        brightnessctl
        playerctl
        pipewire
        wireplumber
        pipewire-pulse
        pipewire-alsa
        xdg-desktop-portal-wlr
        xdg-desktop-portal-gtk
        ttf-font-awesome
        python
        python-pillow
        wf-recorder
        swaylock
        tesseract
        tesseract-data-eng
        tesseract-data-rus
        networkmanager
        qt6-base
        qt6-declarative
        qt6-svg
        qt6-shadertools
        jemalloc
        cpptrace
        cli11
        vulkan-headers
        spirv-tools
    )

    info "Установка системных зависимостей через pacman..."
    substep "Пакеты: ${packages[*]}"

    local SUDO=""
    if [[ $EUID -ne 0 ]]; then
        if command -v sudo &>/dev/null; then
            SUDO="sudo"
        else
            err "Для установки пакетов требуются права root или установленный sudo."
            exit 1
        fi
    fi

    $SUDO pacman -S --needed --noconfirm "${packages[@]}"
    success "Все системные пакеты успешно установлены."
}

# --- Check 3: Install Mango Compositor ---
install_mango() {
    info "Проверка и установка композитора Mango..."

    if command -v mango &>/dev/null || command -v mangowm &>/dev/null; then
        success "Композитор Mango уже установлен."
        return 0
    fi

    local SUDO=""
    if [[ $EUID -ne 0 ]]; then
        SUDO="sudo"
    fi

    # 1. Пробуем установить напрямую через pacman (официальный репозиторий Arch)
    substep "Попытка установки mangowm через pacman..."
    if $SUDO pacman -S --needed --noconfirm mangowm 2>/dev/null; then
        success "Mango установлен через pacman."
        return 0
    fi

    # 2. Пробуем установить через AUR-хелпер (paru / yay)
    if command -v paru &>/dev/null; then
        substep "Установка mangowm-git через paru..."
        if paru -S --needed --noconfirm mangowm-git || paru -S --needed --noconfirm mangowm; then
            success "Mango установлен через paru."
            return 0
        fi
    elif command -v yay &>/dev/null; then
        substep "Установка mangowm-git через yay..."
        if yay -S --needed --noconfirm mangowm-git || yay -S --needed --noconfirm mangowm; then
            success "Mango установлен через yay."
            return 0
        fi
    fi

    # 3. Если AUR-хелперов нет или пакет не найден, собираем напрямую из официального репозитория
    substep "Сборка Mango из официального репозитория (mangowm/mango)..."
    $SUDO pacman -S --needed --noconfirm base-devel wayland wayland-protocols wlroots scenefx libxkbcommon pixman pkgconf git meson ninja

    local tmpdir
    tmpdir="$(mktemp -d)"
    git clone --depth 1 https://github.com/mangowm/mango.git "$tmpdir/mango"
    cd "$tmpdir/mango"
    meson setup build -Dprefix=/usr
    ninja -C build
    $SUDO ninja -C build install
    cd "$DOTFILES_DIR"
    rm -rf "$tmpdir"

    success "Композитор Mango успешно собран и установлен в систему."
}

# --- Check 4: Install Quickshell ---
install_quickshell() {
    info "Проверка и установка Quickshell..."

    if command -v quickshell &>/dev/null; then
        success "Quickshell уже установлен."
        return 0
    fi

    local SUDO=""
    if [[ $EUID -ne 0 ]]; then
        SUDO="sudo"
    fi

    # 1. Попытка установить через pacman (если подключен сторонний репозиторий, например chaotic-aur)
    substep "Попытка установки quickshell через pacman..."
    if $SUDO pacman -S --needed --noconfirm quickshell 2>/dev/null || $SUDO pacman -S --needed --noconfirm quickshell-git 2>/dev/null; then
        success "Quickshell установлен через pacman."
        return 0
    fi

    # 2. Попытка через AUR-хелперы (paru / yay)
    if command -v paru &>/dev/null; then
        substep "Установка quickshell-git через paru..."
        if paru -S --needed --noconfirm quickshell-git || paru -S --needed --noconfirm quickshell; then
            success "Quickshell установлен через paru."
            return 0
        fi
    elif command -v yay &>/dev/null; then
        substep "Установка quickshell-git через yay..."
        if yay -S --needed --noconfirm quickshell-git || yay -S --needed --noconfirm quickshell; then
            success "Quickshell установлен через yay."
            return 0
        fi
    fi

    # 3. Автоматическая сборка из официального репозитория
    substep "Сборка Quickshell из официального репозитория (outfoxxed/quickshell)..."
    local tmpdir
    tmpdir="$(mktemp -d)"

    if git clone --depth 1 https://git.outfoxxed.me/quickshell/quickshell.git "$tmpdir/quickshell" 2>/dev/null || \
       git clone --depth 1 https://github.com/outfoxxed/quickshell.git "$tmpdir/quickshell"; then
        cd "$tmpdir/quickshell"
        cmake -GNinja -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr -DINSTALL_QML_PREFIX=lib/qt6/qml
        ninja -C build
        $SUDO ninja -C build install
        cd "$DOTFILES_DIR"
        rm -rf "$tmpdir"
        if command -v quickshell &>/dev/null; then
            success "Quickshell успешно собран и установлен в систему."
            return 0
        fi
    fi

    # 4. Резервная попытка сборки через makepkg из AUR
    if [[ $EUID -ne 0 ]]; then
        substep "Попытка сборки quickshell-git через makepkg из AUR..."
        local aurtmp
        aurtmp="$(mktemp -d)"
        if git clone --depth 1 https://aur.archlinux.org/quickshell-git.git "$aurtmp/quickshell-git"; then
            cd "$aurtmp/quickshell-git"
            makepkg -si --noconfirm || true
            cd "$DOTFILES_DIR"
            rm -rf "$aurtmp"
        fi
    fi

    if command -v quickshell &>/dev/null; then
        success "Quickshell успешно установлен в систему."
        return 0
    else
        err "Не удалось установить Quickshell автоматически. Установите quickshell-git вручную из AUR:"
        err "  yay -S quickshell-git  (или git clone https://aur.archlinux.org/quickshell-git.git && cd quickshell-git && makepkg -si)"
        exit 1
    fi
}

# --- Check 5: Create User Directories ---
create_directories() {
    info "Создание рабочих директорий в \$HOME..."

    local dirs=(
        "$HOME/.config"
        "$HOME/.local/bin"
        "$HOME/.local/state"
        "$HOME/.cache/qs-lite"
        "$HOME/.local/share/fonts"
        "$HOME/Pictures/Screenshots"
        "$HOME/Pictures/Wallpapers"
        "$HOME/Videos/Recordings"
    )

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            substep "Создано: $dir"
        else
            substep "Существует: $dir"
        fi
    done
    success "Директории подготовлены."
}

# --- Check 6: Safe Stow Deployment ---
deploy_stow() {
    info "Развёртывание конфигураций через GNU Stow..."

    local backup_time
    backup_time="$(date +%Y%m%d_%H%M%S)"

    for mod in "${CONFIG_MODULES[@]}"; do
        local target="$HOME/.config/$mod"
        if [[ "$mod" == "bin" ]]; then
            # bin module targets .local/bin directly or files inside it
            continue
        fi
        if [[ "$mod" == "quickshell" && -d "$HOME/.config/quickshell/lite" && ! -L "$HOME/.config/quickshell/lite" ]]; then
            warn "Найден старый каталог $HOME/.config/quickshell/lite. Создаю резервную копию..."
            mv "$HOME/.config/quickshell/lite" "$HOME/.config/quickshell/lite.backup_${backup_time}"
            substep "Резервная копия: $HOME/.config/quickshell/lite.backup_${backup_time}"
        fi
        if [[ "$mod" == "quickshell" && -f "$HOME/.config/quickshell/shell.qml" && ! -L "$HOME/.config/quickshell/shell.qml" ]]; then
            warn "Найден локальный файл $HOME/.config/quickshell/shell.qml (не симлинк). Создаю резервную копию..."
            mv "$HOME/.config/quickshell/shell.qml" "$HOME/.config/quickshell/shell.qml.backup_${backup_time}"
            substep "Резервная копия: $HOME/.config/quickshell/shell.qml.backup_${backup_time}"
        fi
        if [[ -e "$target" && ! -L "$target" ]]; then
            warn "Найден существующий каталог/файл $target. Создаю резервную копию..."
            mv "$target" "${target}.backup_${backup_time}"
            substep "Резервная копия: ${target}.backup_${backup_time}"
        fi
    done

    # Вызов stow из корня репозитория
    cd "$DOTFILES_DIR"
    stow -v -R -t "$HOME" "${CONFIG_MODULES[@]}"

    success "Конфигурации успешно слинкованы в $HOME"
}

# --- Step 7: Post-Install Instructions ---
show_instructions() {
    cat << EOF

${SAKURA}${BOLD}==============================================================================
               РАЗВЁРТЫВАНИЕ УСПЕШНО ЗАВЕРШЕНО!
==============================================================================${RESET}

${BOLD}1. PATH ДЛЯ СКРИПТОВ:${RESET}
   Убедитесь, что ${WHITE}~/.local/bin${RESET} добавлен в ваш PATH (в ~/.bashrc или ~/.zshrc):
   ${SAKURA}export PATH="\$HOME/.local/bin:\$PATH"${RESET}

${BOLD}2. ШРИФТЫ (FONTS):${RESET}
   • Конфигурация использует основной шрифт: ${SAKURA}Kibernetyk Mono${RESET}
     (с системными иконками Font Awesome).
   • Чтобы установить Kibernetyk Mono, поместите файлы .ttf / .otf в:
     ${WHITE}~/.local/share/fonts/${RESET}
     и обновите кэш шрифтов командой:
     ${SAKURA}fc-cache -fv${RESET}

${BOLD}3. ЗВУК И МУЛЬТИМЕДИА:${RESET}
   Убедитесь, что пользовательские сервисы PipeWire активны:
   ${SAKURA}systemctl --user enable --now pipewire wireplumber${RESET}

${BOLD}4. ОБОИ (SWWW & QUICKSHELL):${RESET}
   Поместите желаемые обои в ${WHITE}~/Pictures/Wallpapers/${RESET}
   Для установки обоев и автоматической адаптации темы интерфейса используйте:
   ${SAKURA}wallpick ~/Pictures/Wallpapers/ваши_обои.png${RESET}
   (или нажмите ${SAKURA}SUPER + W${RESET} для графического выбора обоев)

${BOLD}5. ЗАПУСК:${RESET}
   Запустите сессию из виртуальной консоли (TTY):
   ${SAKURA}mango${RESET}

${SAKURA}==============================================================================${RESET}
EOF
}

main() {
    banner
    check_prerequisites
    install_dependencies
    install_mango
    install_quickshell
    create_directories
    deploy_stow
    show_instructions
}

main "$@"
