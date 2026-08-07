# arcmac

Built-ins-first vanilla Emacs 31, packaged as a Nix flake.

- `config/config.org` — literate config, tangled to `init.el` +
  `early-init.el` (both committed; the `tangle` flake check enforces they
  stay in sync).
- `module.nix` — Home Manager module: Emacs 31 pretest (pgtk, prebuilt via
  emacs-overlay) with the few external packages nix provides, `emacs` /
  `emacsclient` wrappers pinned to this config via `--init-directory`, the
  daemon as a systemd user service, fonts, spell checking, desktop entries,
  and `EDITOR=emacsclient -t`.

Philosophy: built-in first, extend deliberately. Every external package is
listed with a one-line justification in `module.nix` — if a line can't
justify itself, it doesn't get added.

## Usage

```nix
# flake input
inputs.arcmac.url = "github:mentallyinspired/arcmac";

# NixOS + Home Manager module:
#   home-manager.sharedModules = [ arcmac.homeManagerModules.default ];
# standalone Home Manager:
#   modules = [ arcmac.homeManagerModules.default ... ];

programs.arcmac = {
  enable = true;
  checkoutDir = "dev/arcmac"; # clone of this repo, relative to $HOME
  # daemon.target defaults to graphical-session.target (right under niri
  # and other compositors that import the display env into systemd);
  # on WSL / headless machines use default.target:
  # daemon.target = "default.target";
};
```

The config is **not** read from the nix store: `~/.config/arcmac` is an
out-of-store symlink to `<checkoutDir>/config`, so edits (and tangling)
apply on the next Emacs start without a rebuild. Clone this repo to
`checkoutDir` on every machine that enables the module.

## Runtime paths

- State (history, bookmarks, undo, backups, …): `~/.local/state/arcmac/`
- Native-comp cache: `~/.cache/arcmac/eln-cache/`
- The checkout's `config/.gitignore` catches the few artifacts Emacs still
  drops next to the config.

## Editing workflow

Edit `config.org`, tangle (`C-c C-v t` inside Emacs, or the command in the
file header), commit `config.org` together with both `.el` files.
`nix flake check` runs the tangle check and `nixfmt` formatting check.

## License

[MIT](LICENSE)
