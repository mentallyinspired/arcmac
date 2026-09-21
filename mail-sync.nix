# One sync entry point for the timer, shell and Emacs.
{ pkgs }:
pkgs.writeShellApplication {
  name = "mail-sync";
  runtimeInputs = with pkgs; [
    isync
    notmuch
    util-linux
    coreutils
  ];
  text = builtins.readFile ./scripts/mail-sync.sh;
}
