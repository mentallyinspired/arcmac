{
  description = "arcmac — built-ins-first vanilla Emacs 31 as a Nix flake";

  # The nix-community cache holds the emacs-overlay CI builds (Emacs 31
  # pretest); without it Emacs compiles from source. Consumers need the same
  # substituter configured (or must accept this flake's config).
  nixConfig = {
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Emacs 31 pretest builds. Deliberately NO nixpkgs.follows: its packages
    # output is built against its own locked nixpkgs, which is exactly what
    # the nix-community CI pushed to nix-community.cachix.org — prebuilt, no
    # local compile. Applying the overlay against our nixpkgs would rebuild.
    emacs-overlay.url = "github:nix-community/emacs-overlay";
  };

  outputs =
    {
      self,
      nixpkgs,
      emacs-overlay,
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      arcmacEmacs = import ./emacs-package.nix { inherit pkgs emacs-overlay; };
    in
    {
      homeManagerModules = rec {
        arcmac = import ./module.nix { inherit emacs-overlay; };
        default = arcmac;
      };

      checks.${system} = {
        mail-sync =
          pkgs.runCommand "mail-sync-check"
            {
              nativeBuildInputs = [
                (import ./mail-sync.nix { inherit pkgs; })
                pkgs.python3
                pkgs.util-linux
              ];
              src = self;
            }
            ''
              # Build/shellcheck the installed entry point, then exercise
              # its script with fake tools: no account or network access.
              status=0
              mail-sync --invalid || status=$?
              test "$status" -eq 64
              python "$src/tests/mail-sync-test.py"
              touch "$out"
            '';

        # Exercise actual early-init/init and startup hooks in a separate
        # foreground daemon, with the same Emacs/packages as the module.
        startup =
          pkgs.runCommand "startup-check"
            {
              nativeBuildInputs = [
                (pkgs.hunspell.withDicts (dicts: [
                  dicts.sv_SE
                  dicts.en_US-large
                ]))
              ];
              src = self;
            }
            ''
              bash "$src/tests/startup-check.sh" ${arcmacEmacs}/bin/emacs "$src"
              touch "$out"
            '';

        # config.org tangles to TWO files via per-block :tangle headers, so
        # tangle next to a copy and diff both against the committed output.
        tangle =
          pkgs.runCommand "tangle-check"
            {
              nativeBuildInputs = [
                pkgs.diffutils
                pkgs.emacs
              ];
              src = self;
            }
            ''
              mkdir work
              cp "$src/config.org" work/
              emacs --batch --quick \
                --eval "(require 'ob-tangle)" \
                --eval "(org-babel-tangle-file \"work/config.org\")"
              diff -u "$src/init.el" work/init.el
              diff -u "$src/early-init.el" work/early-init.el
              touch "$out"
            '';

        org-workflow =
          pkgs.runCommand "org-workflow-check"
            {
              nativeBuildInputs = [ pkgs.emacs ];
              src = self;
            }
            ''
              emacs --batch --quick \
                -l "$src/tests/org-workflow-test.el" \
                -f ert-run-tests-batch-and-exit
              touch "$out"
            '';

        formatting =
          pkgs.runCommand "formatting-check"
            {
              nativeBuildInputs = [ pkgs.nixfmt ];
              src = self;
            }
            ''
              nixfmt --check "$src"/*.nix
              touch "$out"
            '';
      };

      formatter.${system} = pkgs.writeShellApplication {
        name = "format";
        runtimeInputs = [ pkgs.nixfmt ];
        text = ''
          nixfmt ./*.nix
        '';
      };
    };
}
