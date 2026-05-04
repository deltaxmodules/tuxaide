#!/usr/bin/env bash
R="\033[0m"; GR="\033[32m"; RD="\033[31m"; YL="\033[33m"; BOLD="\033[1m"
echo ""
echo -e "${RD}${BOLD}  🐧  TuxAide — Uninstall${R}"
echo ""
read -rp "  Are you sure? This removes TuxAide completely. [y/N] " a
[[ "$a" =~ ^[yYsS]$ ]] || { echo "  Cancelled."; exit 0; }
for rc in ~/.bashrc ~/.zshrc ~/.profile; do
    [[ -f "$rc" ]] || continue
    grep -v "TuxAide" "$rc" > /tmp/_tux_rc && mv /tmp/_tux_rc "$rc"
    echo -e "  ${GR}✓${R} Removed from $rc"
done
rm -f ~/.local/bin/tuxaide ~/.local/bin/tuxaide-index ~/.local/bin/tuxaide-uninstall
rm -rf ~/.config/tuxaide
echo -e "  ${GR}✓${R} Files removed"
echo ""
echo -e "  ${YL}Note: Ollama and models were NOT removed.${R}"
echo -e "  ${YL}To remove: sudo systemctl stop ollama && sudo rm \$(which ollama)${R}"
echo ""
echo -e "  ${GR}${BOLD}Done. Restart your terminal.${R}"
echo ""
