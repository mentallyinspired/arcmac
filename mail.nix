# Mail: mbsync + msmtp + notmuch + afew for the two danros.se accounts —
# moved here from niri-noah's modules/mail.nix so the notmuch UI in
# config.org works wherever this flake is consumed. Off by default: turning
# it on needs per-machine secrets, supplied via passwordCommands.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.arcmac.mail;

  # Both accounts live on the same server; only address and secret differ.
  mkAccount =
    {
      address,
      secret,
      primary ? false,
    }:
    {
      inherit address primary;
      userName = address;
      realName = "Noah Danros";
      imap = {
        host = "mail.danros.se";
        port = 993;
        tls.enable = true;
      };
      smtp = {
        host = "mail.danros.se";
        port = 465;
        tls.enable = true;
      };
      passwordCommand = cfg.passwordCommands.${secret};
      mbsync = {
        enable = true;
        create = "both";
        expunge = "both";
      };
      msmtp.enable = true;
      notmuch.enable = true;
    };
in
{
  options.programs.arcmac.mail = {
    enable = lib.mkEnableOption "the notmuch mail stack (mbsync + msmtp + afew)";

    passwordCommands = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        danros = "cat ${config.home.homeDirectory}/.mail-secrets/danros";
        septus = "cat ${config.home.homeDirectory}/.mail-secrets/septus";
      };
      description = ''
        Shell command per account that prints the IMAP/SMTP password.
        The default reads plain files from ~/.mail-secrets; hosts with a
        secrets manager override this (e.g. sops-nix's decrypted /run
        paths on the NixOS machines).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    accounts.email = {
      maildirBasePath = "Maildir";
      accounts = {
        danros = mkAccount {
          address = "noah@danros.se";
          secret = "danros";
          primary = true;
        };
        septus = mkAccount {
          address = "noah@septus.se";
          secret = "septus";
        };
      };
    };

    programs.mbsync.enable = true;

    # msmtp selects the account by envelope-from, so Emacs routes each From:
    # address to the right account without any elisp (see config.org: Mail).
    programs.msmtp.enable = true;

    programs.notmuch = {
      enable = true;
      new.tags = [ "new" ];
      # Before the mail scan: the trash flow. Emacs only *tags* mail (`d`
      # adds `trash`); move those files into the account's Trash maildir so
      # the move reaches the server on the next mbsync. `touch` restarts the
      # file's mtime — that is the 30-day purge clock below (for mail
      # trashed on other devices, mbsync's download time serves the same
      # role).
      hooks.preNew = ''
        for acct in danros septus; do
          dest="$HOME/Maildir/$acct/Trash/cur"
          ${pkgs.notmuch}/bin/notmuch search --output=files --format=text0 \
            -- "(tag:trash or tag:deleted) and path:$acct/** and not folder:$acct/Trash" |
            while IFS= read -r -d "" f; do
              # The DB can be stale here (pre-new runs before the rescan),
              # e.g. right after mail-empty-trash rm'd these same files —
              # skip paths that are already gone.
              [ -e "$f" ] || continue
              mv "$f" "$dest/" && touch "$dest/''${f##*/}"
            done
        done
        # Auto-purge: delete Trash files older than 30 days; expunge=both
        # then removes them from the server on the next mbsync.
        find "$HOME"/Maildir/*/Trash/cur "$HOME"/Maildir/*/Trash/new \
          -type f -mtime +30 -delete
      '';
      # After every `notmuch new`: tag anything landing in a Sent folder as
      # `sent` (device-independent — phone/Thunderbird file their sent
      # copies to the server Sent folder, which mbsync pulls down here) and
      # drop it from the `new` set so afew leaves it out of the inbox. Then
      # afew triages the rest.
      hooks.postNew = ''
        # Mark this batch so the notification at the end can find it — afew
        # strips `new`, so the marker is the only way to know what just
        # arrived.
        ${pkgs.notmuch}/bin/notmuch tag +notify -- tag:new
        ${pkgs.notmuch}/bin/notmuch tag +sent -inbox -new -- folder:/Sent/ and tag:new
        # Mail trashed on another device arrives as a rename into Trash
        # keeping its old tags (inbox/unread), which would leave it in the
        # inbox saved searches forever. Normalize: anything in a Trash
        # folder is trash only, and not `new` so afew skips it.
        ${pkgs.notmuch}/bin/notmuch tag +trash -inbox -unread -new \
          -- "folder:/Trash/ and (tag:inbox or tag:unread or tag:new or not tag:trash)"
        ${pkgs.afew}/bin/afew --tag --new
        # Desktop notification for whatever this batch left in the inbox
        # (mako on the niri machines; harmless no-op where no notification
        # daemon runs).
        count=$(${pkgs.notmuch}/bin/notmuch count "tag:notify and tag:inbox and tag:unread")
        if [ "$count" -gt 0 ]; then
          body=$(${pkgs.notmuch}/bin/notmuch search --sort=newest-first --limit=5 \
                   -- "tag:notify and tag:inbox and tag:unread" \
                 | ${pkgs.gnused}/bin/sed -E 's/^[^]]*\] //; s/ \([^)]*\)$//')
          ${pkgs.libnotify}/bin/notify-send -a Mail "New mail ($count)" "$body" || true
        fi
        ${pkgs.notmuch}/bin/notmuch tag -notify -- tag:notify
      '';
    };

    programs.afew = {
      enable = true;
      extraConfig = ''
        [SpamFilter]
        [KillThreadsFilter]
        [ListMailsFilter]
        [ArchiveSentMailsFilter]
        [InboxFilter]
      '';
    };

    # Poll the server every 5 minutes (systemd user timer mbsync.timer). The
    # postExec `notmuch new` runs the full tagging pipeline (hooks above:
    # trash sweep, 30-day purge, sent/trash normalization, afew triage).
    # Local changes made between runs — read flags, trash moves, purges —
    # reach the server on the following cycle, i.e. within 5 minutes.
    # Overlap with a manual mail-sync is harmless: mbsync locks per-channel
    # and the loser skips.
    services.mbsync = {
      enable = true;
      frequency = "*:0/5";
      postExec = "${pkgs.writeShellScript "mbsync-post" ''
        ${pkgs.notmuch}/bin/notmuch new
      ''}";
    };

    # Full pull-tag chain. The trailing mbsync pushes what the notmuch hooks
    # just did locally (moves into Trash, 30-day purges) up to the server in
    # the same run instead of waiting for the next sync.
    programs.zsh.shellAliases.mail-sync = "mbsync -a && notmuch new && mbsync -a";

    # Escape hatch: empty the Trash now instead of waiting out the 30 days.
    # Destructive and unprompted — trashed mail is gone for good after this.
    programs.zsh.shellAliases.mail-empty-trash = "notmuch search --output=files --format=text0 -- \"folder:/Trash/ or tag:trash or tag:deleted\" | xargs -0 -r rm -f && notmuch new && mbsync -a";
  };
}
