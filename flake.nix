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
    in
    {
      homeManagerModules = rec {
        arcmac = import ./module.nix { inherit emacs-overlay; };
        default = arcmac;
      };

      checks.${system} = {
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
