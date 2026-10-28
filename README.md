# time-sync

An hourly clock-offset **check** for macOS, as a Home Manager module. It never sets the clock (that needs root and
belongs to the system layer, e.g. nix-darwin's network time); it is the witness that tells whether that layer works.
Each hour a launchd agent runs plain `sntp` (no root) against `server` and appends one line to
`$XDG_STATE_HOME/time-sync/offset.log`: `ok offset=…`, `DRIFT offset=…` when |offset| > `maxOffset` seconds, or `ERROR …`.

```nix
inputs.time-sync = { url = "github:bdelanghe/time-sync"; inputs.nixpkgs.follows = "nixpkgs"; inputs.home-manager.follows = "home-manager"; };
# modules = [ time-sync.homeManagerModules.default ];
programs.timeSync = { enable = true; server = "time.apple.com"; maxOffset = 1; };
```

## Checks

`nix flake check`: the offset parsing and DRIFT threshold (any system), and on macOS the module under Home Manager.
