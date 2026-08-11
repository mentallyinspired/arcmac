# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```sh
# After editing config.org, ALWAYS retangle and commit all three files together:
emacs --batch --quick --eval "(require 'ob-tangle)" \
  --eval '(org-babel-tangle-file "config.org")'

nix flake check   # tangle-drift check + nixfmt formatting check
nix fmt           # apply canonical formatting to the .nix files
```

There is no build step to "run" the config: this checkout IS the live config
(see below) — restart Emacs (`systemctl --user restart emacs`) to pick up
changes.

## Architecture

**The checkout is the config.** This repo is cloned AT `~/.config/arcmac` and
Emacs runs it directly via wrappers that pin `--init-directory` there — no nix
store copy, no symlink. Edits apply on the next Emacs start without any
rebuild. Runtime state is redirected out of the checkout
(`~/.local/state/arcmac`, eln-cache in `~/.cache/arcmac`); `.gitignore` is a
safety net for the few artifacts Emacs still drops here. Consumers pick up
*module* changes only after committing, pushing, and running
`nix flake update arcmac` in the consuming repo — elisp changes need none of
that.

**Literate config.** `config.org` tangles to BOTH `init.el` and
`early-init.el` via per-block `:tangle` headers. Edit only `config.org`; the
`tangle` flake check fails if the committed `.el` files drift.

**Philosophy (owner's explicit rule):** built-in first, extend deliberately.
Every external package in `module.nix` carries a one-line justification — if a
line can't justify itself, it doesn't get added. Don't add packages, an
`extraConfig` escape hatch, or completion frameworks (vertico/corfu were
deliberately rejected in favor of the stock *Completions* buffer).

**Nothing personal is hardcoded.** Identity, mail accounts, and font size are
Home Manager options (`programs.arcmac.identity`, `.mail.accounts`,
`.fontSize`) rendered into a generated `~/.config/arcmac-local.el`, which
init.el loads (non-nix users write that file by hand). The elisp derives all
account-specific behavior — notmuch hello sections, saved searches with jump
keys, Fcc routing, sent-push — from the `nd/mail-accounts` triples
`(NAME ADDRESS KEY)` in that file. Keep it that way: no names, addresses, or
machine paths in tracked files. Machine differences that are *detectable*
(missing language servers) are handled at runtime in config.org, not via
options. Nix-side WSL differences are the exception — evaluation cannot
detect WSL without reading /proc, so `programs.arcmac.wsl.enable` states it.

**module.nix is a function over the flake's inputs** (`{ emacs-overlay }:`
wrapper) so consumers get the prebuilt Emacs 31 pretest without wiring the
overlay themselves. emacs-overlay deliberately has NO `nixpkgs.follows`: its
`packages` output matches what nix-community.cachix.org has prebuilt — adding
follows would silently rebuild Emacs from source. The `nixConfig` substituter
is a restricted setting (ignored for non-trusted users); fresh non-NixOS
machines must add the cache to `/etc/nix/nix.conf` first (see README).

**Bootstrap ordering matters.** The activation script clones this repo (HTTPS,
SSH push-url) and is ordered `entryBetween ["reloadSystemd"] ["writeBoundary"]`
— sd-switch starts the daemon during the same activation, and the clone must
exist first. Preserve that ordering on any activation change.

**mail.nix** is the full notmuch pipeline (mbsync + msmtp + afew accounts,
trash flow via pre/post-new hooks, 5-minute sync timer, aliases), off by
default behind `programs.arcmac.mail.enable`. Secrets never live here:
`passwordCommands` per account, defaulting to `~/.mail-secrets/<name>`.
Assertions enforce exactly one `primary` account and unique inbox jump keys.

## Consumers

- `~/niri-noah` (NixOS, both machines) — wired via `home-manager.sharedModules`
- `~/dotfiles` (standalone HM on Ubuntu/WSL) — module in the
  homeConfiguration's module list, `wsl.enable = true`
