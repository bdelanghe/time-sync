{
  description = "time-sync: an hourly clock-offset check for macOS (sntp, no root, never sets the clock), as a Home Manager module";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    # Only for the module-eval check; consumers already carry home-manager and should `follows` it.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager }:
    let
      lib = nixpkgs.lib;
      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      forAll = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      homeManagerModules.default = import ./nix/module.nix;

      checks = forAll (pkgs:
        {
          # The check script's offset parsing and DRIFT threshold, on any system: the script run against a stub sntp.
          parse = pkgs.runCommand "time-sync-parse" { nativeBuildInputs = [ pkgs.gawk ]; } ''
            awk_expr=$(sed -n "s/.*awk -v o=\"\$off\" -v m=[^ ]* '\(.*\)'.*/\1/p" ${./nix/module.nix})
            parse_expr=$(sed -n "s/.*awk '\(\/\^\[+-\]?.*exit }\)'.*/\1/p" ${./nix/module.nix})
            [ -n "$awk_expr" ] && [ -n "$parse_expr" ]
            line='+0.012345 +/- 0.003 time.example 1.2.3.4'
            [ "$(printf '%s\n' "$line" | awk "$parse_expr")" = +0.012345 ]
            printf '%s\n' '-3.47 +/- 0.01 x' | awk "$parse_expr" | grep -qx -- -3.47
            awk -v o=-3.47 -v m=1 "$awk_expr" && echo "DRIFT detected for -3.47 > 1"
            ! awk -v o=0.2 -v m=1 "$awk_expr"
            touch $out
          '';
        }
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          # Under Home Manager: off by default; on, one hourly agent that logs to the state dir.
          module-eval =
            let
              hm = extra: (home-manager.lib.homeManagerConfiguration {
                inherit pkgs;
                modules = [ self.homeManagerModules.default { home = { username = "t"; homeDirectory = "/Users/t"; stateVersion = "24.11"; }; } extra ];
              }).config;
              on = hm { programs.timeSync = { enable = true; server = "time.example"; maxOffset = 2; }; };
              off = hm { };
              a = on.launchd.agents.time-sync-check;
            in
            assert !(off.launchd.agents ? time-sync-check) || !off.launchd.agents.time-sync-check.enable;
            assert a.enable && a.config.StartInterval == 3600;
            assert a.config.StandardOutPath == "/Users/t/.local/state/time-sync/offset.log";
            pkgs.runCommand "time-sync-module-eval" { } ''
              grep -qE "sntp -t 5 '?time.example" ${builtins.head a.config.ProgramArguments}
              grep -q 'm=2 ' ${builtins.head a.config.ProgramArguments}
              ${pkgs.bash}/bin/bash -n ${builtins.head a.config.ProgramArguments}
              touch $out
            '';
        });
    };
}
