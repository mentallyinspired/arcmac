# arcmac

Built-ins-first vanilla Emacs 31, packaged as a Nix flake.

- `config.org` — literate config, tangled to `init.el` + `early-init.el`
  (both committed; the `tangle` flake check enforces they stay in sync).
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

  # Identity is NOT hardcoded in the repo — it lands in the generated
  # ~/.config/arcmac-local.el, which config.org loads at init.
  identity = {
    fullName = "Ada Lovelace";
    email = "ada@example.org";
  };

  # Per-machine font size in pixels (default 16 ≈ 12pt):
  # fontSize = 18;

  # On WSL: ties the daemon to default.target (no compositor-managed
  # graphical-session.target) and mirrors the launchers into
  # ~/.local/share/applications so WSLg exports them to the Start Menu.
  # wsl.enable = true;

  # daemon.target defaults to graphical-session.target (right under niri
  # and other compositors that import the display env into systemd);
  # on headless machines that are not WSL use default.target:
  # daemon.target = "default.target";

  # Optional: the full notmuch mail stack (mbsync + msmtp + afew,
  # 5-minute sync timer, trash flow) — see mail.nix. Off by default;
  # accounts and secrets are per-machine options:
  # mail.enable = true;
  # mail.server = "mail.example.org";
  # mail.accounts.personal = { address = "ada@example.org"; primary = true; };
  # mail.passwordCommands.personal = "cat /run/secrets/mail-personal";
  # (accounts without an entry read ~/.mail-secrets/<name>)
};
```

Without nix, write `~/.config/arcmac-local.el` by hand — see the Identity
section at the top of `config.org`.

**Fresh non-NixOS machines:** the `nixConfig` substituter below is a
restricted setting — nix silently ignores it for non-trusted users, and
the first switch then builds the Emacs 31 pretest from source (hours).
Before the first switch, add to `/etc/nix/nix.conf`:

```
extra-substituters = https://nix-community.cachix.org
extra-trusted-public-keys = nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=
```

(NixOS consumers should set the same via their system config.)

The config is **not** read from the nix store: `~/.config/arcmac` IS a
clone of this repo, so edits (and tangling) apply on the next Emacs start
without a rebuild, and are pushed/pulled between machines with plain git.
The module's activation step clones the repo there on first switch if the
directory is missing (over SSH — needs a GitHub key; otherwise it prints
the manual clone command and carries on).

## Runtime paths

- State (history, bookmarks, undo, backups, …): `~/.local/state/arcmac/`
- Native-comp cache: `~/.cache/arcmac/eln-cache/`
- The repo's `.gitignore` catches the few artifacts Emacs still drops
  into the config dir itself (`auto-save-list/`, `eshell/`, …).

## Editing workflow

Edit `config.org`, tangle (`C-c C-v t` inside Emacs, or the command in the
file header), commit `config.org` together with both `.el` files.
`nix flake check` runs the tangle check and `nixfmt` formatting check.

## License

[MIT](LICENSE)
