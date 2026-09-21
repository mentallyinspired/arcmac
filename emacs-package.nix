# The Emacs build and package set shared by Home Manager and startup checks.
{ pkgs, emacs-overlay }:
let
  emacs31 = emacs-overlay.packages.${pkgs.stdenv.hostPlatform.system}.emacs-unstable-pgtk;
in
(pkgs.emacsPackagesFor emacs31).emacsWithPackages (
  epkgs: with epkgs; [
    evil
    evil-collection # evil keys in dired/ibuffer/agenda/magit/notmuch etc.
    undo-fu-session # persistent undo across restarts (works with undo-redo)
    doom-themes # doom-nord: matches the kitty/eww Nord palette + old Doom look
    magit # daily-driver git UI; built-in vc is a real downgrade here
    hl-todo # TODO/FIXME highlighting in code
    diff-hl # vc gutter marks (Doom's vc-gutter)
    org-journal # yearly journal files; capture templates target it
    org-download # paste/drag images into org (assets dir)
    visual-fill-column # centered 140-col org buffers
    org-ql # my-org-ql dynamic block (dashboard.org depends on it)
    org-modern # org headline/list/block/TODO styling; nothing built-in does it
    nerd-icons # agenda category icons (fonts already installed)
    consult # ripgrep/register UIs; dep of consult-recoll
    consult-recoll # recoll full-text search over ~/org
    flyspell-correct # correction UI with a visible Save; ispell-word hides it
    nix-ts-mode # nix has no built-in major mode
    zig-ts-mode # zig has no built-in major mode
    markdown-mode # no built-in markdown mode either
    treesit-grammars.with-all-grammars
    # notmuch mail UI: the elisp is built from the consumer's nixpkgs — the
    # same source as a notmuch CLI installed from that nixpkgs, so UI and
    # index can never drift apart. Deliberately NOT epkgs.notmuch — that is
    # a MELPA git snapshot whose version can diverge from the installed CLI.
    # Harmless on machines without a mail setup: the config only loads it
    # on demand.
    pkgs.notmuch.emacs
  ]
)
