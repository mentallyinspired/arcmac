# Home Manager module — the flake's homeManagerModules.default.
#
# Wrapped as a function over the flake's own inputs so consumers get the
# prebuilt Emacs 31 pretest without wiring emacs-overlay themselves.
{ emacs-overlay }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.arcmac;

  # Emacs 31 pretest (pgtk, prebuilt via emacs-overlay — see flake.nix) plus
  # the few external packages nix provides. Everything else in the config is
  # built-in; extend this list deliberately, not by default.
  emacs31 = emacs-overlay.packages.${pkgs.stdenv.hostPlatform.system}.emacs-unstable-pgtk;
  arcmacEmacs = (pkgs.emacsPackagesFor emacs31).emacsWithPackages (
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
      nerd-icons # agenda category icons (fonts already installed)
      consult # ripgrep/register UIs; dep of consult-recoll
      consult-recoll # recoll full-text search over ~/org
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
  );

  # The config lives in ~/.config/arcmac, not a place Emacs looks by itself,
  # so both entry points pin --init-directory. That also keeps any install in
  # a default location (say a dormant Doom in ~/.config/emacs) from booting
  # by accident.
  emacsWrapped = pkgs.writeShellScriptBin "emacs" ''
    exec ${arcmacEmacs}/bin/emacs --init-directory "$HOME/.config/arcmac" "$@"
  '';

  # emacsclient from the same build as the daemon.
  emacsclientWrapped = pkgs.writeShellScriptBin "emacsclient" ''
    exec ${arcmacEmacs}/bin/emacsclient "$@"
  '';
in
{
  options.programs.arcmac = {
    enable = lib.mkEnableOption "arcmac, a built-ins-first Emacs 31 setup";

    daemon = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run the Emacs daemon as a systemd user service.";
      };

      target = lib.mkOption {
        type = lib.types.str;
        default = "graphical-session.target";
        example = "default.target";
        description = ''
          systemd user target the daemon is tied to. Compositors that import
          WAYLAND_DISPLAY/DISPLAY into the systemd user environment before
          graphical-session.target (niri does) need the default: with
          default.target the daemon starts env-less and browse-url silently
          fails to hand off to the browser. On WSL or headless machines use
          default.target.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      emacsWrapped
      emacsclientWrapped
    ]
    # Editor dependencies the config expects on PATH (or as fonts).
    ++ (with pkgs; [
      # Fonts
      fontconfig
      nerd-fonts.fira-code
      nerd-fonts.overpass
      nerd-fonts.roboto-mono
      nerd-fonts.meslo-lg
      nerd-fonts.mononoki
      nerd-fonts.caskaydia-cove
      nerd-fonts.ubuntu

      # Spell checking
      (hunspell.withDicts (
        dicts: with dicts; [
          sv_SE
          en_US-large
        ]
      ))
      languagetool

      # Emacs dependencies
      graphviz
      wl-clipboard
      wl-clipboard-x11

      # Syntax
      html-tidy
      editorconfig-core-c
    ]);

    fonts.fontconfig.enable = true;

    programs.pandoc.enable = true;

    # EDITOR must block until the edit is done; emacsclient without -n does.
    # -t keeps git-from-terminal edits in the terminal instead of a hidden
    # GUI frame. (If some tool ever chokes on the flag, plain "emacsclient"
    # is the fallback.)
    home.sessionVariables.EDITOR = "emacsclient -t";

    # ~/.config/arcmac IS a clone of this repo — live-editable, no store
    # copy, no symlink indirection. Bootstrap it on fresh machines; never
    # touch an existing one. SSH remote so config edits can be pushed back;
    # on a machine without a key yet the switch still succeeds and leaves a
    # manual-clone hint.
    home.activation.arcmacClone = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -e "${config.home.homeDirectory}/.config/arcmac" ]; then
        ${pkgs.git}/bin/git clone git@github.com:mentallyinspired/arcmac.git \
          "${config.home.homeDirectory}/.config/arcmac" ||
          echo "arcmac: clone failed (no SSH key?) — run: git clone git@github.com:mentallyinspired/arcmac.git ~/.config/arcmac"
      fi
    '';

    # GUI client entry: a new frame on the daemon.
    xdg.desktopEntries.emacsclient = {
      name = "Emacs (Client)";
      exec = "${emacsclientWrapped}/bin/emacsclient -c %F";
      terminal = false;
      icon = "emacs";
      categories = [
        "Development"
        "TextEditor"
      ];
    };

    xdg.desktopEntries.emacs = {
      name = "Emacs";
      exec = "${emacsWrapped}/bin/emacs %F";
      terminal = false;
      icon = "emacs";
      categories = [
        "Development"
        "TextEditor"
      ];
    };

    systemd.user.services.emacs = lib.mkIf cfg.daemon.enable {
      Unit = {
        Description = "Emacs daemon (arcmac)";
        After = [ cfg.daemon.target ];
        PartOf = [ cfg.daemon.target ];
      };
      Service = {
        # notify matches home-manager's services.emacs with --fg-daemon;
        # fall back to Type = "simple" if startup ever times out.
        Type = "notify";
        ExecStart = "${emacsWrapped}/bin/emacs --fg-daemon";
        Restart = "on-failure";
      };
      Install.WantedBy = [ cfg.daemon.target ];
    };
  };
}
