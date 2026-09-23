# arcmac

Built-ins-first vanilla Emacs 31, packaged as a Nix flake.

- `config.org` — literate config, tangled to `init.el` + `early-init.el`
  (both committed; the `tangle` flake check enforces they stay in sync).
- `emacs-package.nix` — Emacs build and package set shared by the module
  and the startup check.
- `module.nix` — Home Manager module: Emacs 31 pretest (pgtk, prebuilt via
  emacs-overlay) with the few external packages nix provides, `emacs` /
  `emacsclient` wrappers pinned to this config via `--init-directory`, the
  daemon as a systemd user service, fonts, spell checking, desktop entries,
  and `EDITOR=emacsclient -t`.

Philosophy: built-in first, extend deliberately. Every external package is
listed with a one-line justification in `emacs-package.nix` — if a line can't
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

Use `C-v` or `C-Shift-v` to paste into input prompts, including URL fields.
`SPC m l l` inserts a normal link; `SPC m l i` downloads a URL as an attachment
and inserts its attachment link.

`SPC f D` deletes the current file and closes its buffer after confirmation.
The prompt identifies the file and any unsaved edits; deletion respects
Emacs' `delete-by-moving-to-trash` setting.

Edit `config.org`, tangle (`C-c C-v t` inside Emacs, or the command in the
file header), commit `config.org` together with both `.el` files.
`nix flake check` runs the tangle check, `nixfmt` formatting check, Org
workflow tests, and a full startup check using the module's Emacs package.
Mail sync checks use fake mail commands to test ordering, failures and
concurrent calls without contacting a server.
The startup check launches a separate daemon with temporary config, state
and notes, exercises Org and code hooks, and exits. It does not restart
your running Emacs. To run it with the installed Emacs and dependencies:

```sh
bash tests/startup-check.sh
```

To run the Org workflow regression tests locally, including the
project-meeting query test using the installed `org-ql`, run:

```sh
emacs --batch --quick -l tests/org-workflow-test.el -f ert-run-tests-batch-and-exit
```

## Org work views

`SPC n d` opens today's commitments and available actions, `SPC n n`
the NEXT list, `SPC n p` the project portfolio, and `SPC n r` the weekly
review. `SPC m M` shows a project's journal meetings from either Org or
an agenda entry. The corresponding agenda keys are `D`, `N`, `P`, `R`
and `W` (waiting); existing domain overview keys are retained.

Agenda jumps and task links expand the path to the target, showing sibling
headings and the task's notes while keeping drawers folded. The cursor stays
on the target. Files with `#+startup: overview` still open in overview normally.

The project portfolio lists every project's NEXT tasks indented beneath it,
including future-scheduled tasks and tasks in held or finished projects.
Archived and commented tasks stay hidden. Nested projects list their own
tasks once. Task rows support the usual agenda navigation and editing;
refresh with `g r` after changes to rebuild the list.

`SPC m b` opens a reusable, project-only buffer from Org or an agenda
entry. It shares edits with the original file but keeps its own folding
and cursor position. `SPC b d` closes the view; the source file stays open.
`SPC m U` updates the containing project's `Nuläge` and `Återuppta`, with
the current text prefilled. It refreshes `Uppdaterad` when the summary
changes and adds missing fields to older projects.
`SPC b i` groups buffers into tasks/projects, journals, notes, reference,
code/config and utilities. Agenda views use the current window, and `q`
restores the previous window layout. Automatic saving applies only to
local Org files inside `org-directory`, including edits through person
and project views. Code and Org files elsewhere need explicit saving.

Inbox capture opens directly for writing; add tags during review.
Capture templates open in a temporary panel at the bottom, keeping existing
windows visible. `C-c C-c` saves and `C-c C-k` cancels; both restore the layout.
New note captures require a title and choose a free filename (`name.org`,
`name-2.org`, etc.), preserving existing notes and unsaved file buffers.

`SPC m w` sets a task to `WAIT`, asking for a contact (or an unregistered
name) and a follow-up date. The `WAITING_FOR` property stores the person;
`SCHEDULED` stores the follow-up. Existing choices are prefilled, and
cancelling leaves the task unchanged. Waiting and weekly review views
show the owner and date, or indicate missing information. Both this and
project-summary updates work from Org, focused views and agenda entries.

Domain tags inherit from `gtd/*.org`; `project`, `focus`, `meeting` and
`unprocessed` are local entry tags. Meeting capture (`SPC n j m`) asks
only for a title and starts under Notes, with separate Agenda, Notes,
Decisions and Actions headings. It adds the ID, timestamp and
`meeting:unprocessed` tags automatically.

Use `SPC m E` (`nd/org-meeting-details`) anywhere inside a meeting or
on its agenda entry to edit Attendees, Organisation, Projects or Tags.
The selectors start with the current choices: press Enter to keep them,
add comma-separated choices, or delete the input to clear the field.
Attendees accept directory names/aliases and unregistered guests;
organisation and project choices retain ID links. Editing details keeps
the meeting's review status. Remove `unprocessed` with `SPC m q` after
clarifying decisions and assigning or filing actions.

Use `SPC m r` (or `C-c C-w`) for ordinary refiling without adding links.
Use `SPC m R` to refile with meeting links, in Org or the agenda. The
task gets a `Backlink:` to its enclosing `:meeting:` entry, and a linked
heading replaces it at its original position and outline level. This also
works from the agenda and for multiple selected tasks. Moving the whole
Actions section leaves a linked Actions heading in its place; moving the
whole meeting keeps it intact. Existing task backlinks are reused, and
other references in the meeting are preserved. IDs keep links working
through later refiles. The replacement heading has no TODO state or
duplicate ID property; follow its link to see the current task.
Copying, navigation and cancelled refiles do not add links. `SPC m a`
remains the prose-to-inbox command with its existing meeting backlink.

Follow file links and ID backlinks with `C-c C-o` in the current window;
use `C-c &` to return from an ID backlink.

The detailed working guide lives in `~/org/notes/org-work-system.org`.

## Contacts

`SPC n c d` opens the contact directory, `SPC n c f` a focused person
view, `SPC n c o` contacts in an organisation and its child units,
`SPC n c h` the person's references in saved notes and archives, and
`SPC n c r` contact details needing review.

Contact capture asks only for a name (with confirmation for duplicate
names). Use `SPC n c e` from a person view or contact link to edit one
field: Context, Organisation, Position, Email, Mobile or Aliases. Existing
values are prefilled; clear the input to remove a value.

In the directory, `RET` opens a person, `e` edits details, `h` opens history, `/` filters
context, `o` selects a unit, `a` clears filters and `g` refreshes.
Use `C-s` to search names, aliases or organisation names. Person views
share edits with `ref/people.org`. History matches exact ID links;
save recent edits before searching.

Headings supply display names; `ALIASES` supports alternative names in
selection, and `ORG_UNIT` links to `ref/organizations.org`.
Organization selectors search the full path and aliases, so typing a unit
name finds it even when another organization's name starts with that text.
Meeting capture removes duplicate selections of the same person and keeps
unknown guests as text. Conflicting names or employers remain in
`CONTACT_REVIEW` until confirmed. Refresh dashboard tables with `C-u C-c C-x C-u`.

## Search

`SPC n /` searches `org-directory` with ripgrep, which the module installs.
`SPC n R` searches a Recoll document index if configured. For Recoll, add
`pkgs.recoll` to `home.packages`, choose indexed folders in `recoll.conf`
and run `recollindex`. The command checks the executable and index before
opening search and offers setup guidance if either is unavailable.
Custom `RECOLL_CONFDIR` settings are respected.

## Mail sync

With `mail.enable = true`, the module installs `mail-sync`. The shell,
Emacs `gR` and the five-minute `mbsync.timer` share its fetch/index/push
pipeline and lock. A concurrent manual request reports “already running”;
after sending, Emacs queues a sync to include the new Sent copy. Errors
remain visible in `*notmuch-sync*` or `journalctl --user -u mbsync`.
Sent-folder matching treats account addresses literally, including `+`.

Without Nix, install the executable `scripts/mail-sync.sh` as `mail-sync`
on PATH alongside mbsync, notmuch and flock.

After pulling module changes, update the `arcmac` input and rebuild the
consuming Home Manager/NixOS configuration to install the command and
dependencies. Restart Emacs to load the updated Lisp; open a new shell
to drop the previous `mail-sync` alias.

## License

[MIT](LICENSE)
