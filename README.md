# retro-dotfiles

Personal dotfiles for an Arch Linux Wayland desktop based on **MangoWM** and **Quickshell**, managed with **GNU Stow**.

## Stack

- [MangoWM](https://github.com/mangowm/mango) — Wayland compositor
- [Quickshell](https://git.outfoxxed.me/outfoxxed/quickshell) — Desktop shell

## Structure

```text
retro-dotfiles/
├── mango/          # MangoWM configuration
├── quickshell/     # Quickshell configuration
├── alacritty/      # Terminal
├── gtk/            # GTK themes
├── zsh/            # Shell configuration
├── starship/       # Prompt
├── bin/            # Custom utilities
└── install.sh      # Installation script
```

## Installation

```bash
git clone <repository-url> ~/retro-dotfiles
cd ~/retro-dotfiles
chmod +x install.sh
./install.sh
```

Alternatively, install dependencies and MangoWM/Quickshell manually, then deploy configurations using Stow:

```bash
stow -v -R -t "$HOME" mango quickshell alacritty bin zsh starship gtk
```

## Updating

```bash
cd ~/retro-dotfiles
git pull
```

Reload MangoWM with `Super + R` or `mmsg reload`.

## Keybindings

Interactive keybinding reference: `Super + /` or `Super + F1`.

## Launch

Start MangoWM from a TTY:

```bash
mango
```
