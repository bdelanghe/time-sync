{ config, lib, pkgs, ... }:

# Clock drift CHECK, not sync. Setting the clock needs root (`systemsetup
# -setusingnetworktime on`, `sntp -sS`), which a user-level home-manager
# config cannot do and must not try; turning network time on belongs to the
# host's system layer (e.g. nix-darwin). This agent is the witness that tells
# whether that layer is doing its job: hourly, it asks the configured server
# for the offset with plain `sntp` (no root, does not touch the clock) and
# appends one line to $XDG_STATE_HOME/time-sync/offset.log, `DRIFT` when
# |offset| exceeds `maxOffset` seconds.
#
# Why it matters: anything that signs or orders events by timestamp across
# hosts (signed frames, bridges) breaks quietly when one host's clock is
# seconds behind another's.
let
  cfg = config.programs.timeSync;
  stateDir = "${config.xdg.stateHome}/time-sync";

  check = pkgs.writeShellScript "time-sync-check" ''
    set -u
    mkdir -p ${lib.escapeShellArg stateDir}
    now=$(/bin/date -u +%FT%TZ)
    if ! out=$(/usr/bin/sntp -t 5 ${lib.escapeShellArg cfg.server} 2>&1); then
      echo "$now ERROR sntp ${cfg.server}: $(printf '%s' "$out" | tail -n1)"; exit 0
    fi
    off=$(printf '%s\n' "$out" | /usr/bin/awk '/^[+-]?[0-9.]+ \+\/-/ { print $1; exit }')
    [ -n "$off" ] || { echo "$now ERROR unparsed: $(printf '%s' "$out" | tail -n1)"; exit 0; }
    if /usr/bin/awk -v o="$off" -v m=${toString cfg.maxOffset} 'BEGIN { o = o < 0 ? -o : o; exit !(o > m) }'; then
      echo "$now DRIFT offset=$off s (> ${toString cfg.maxOffset} s) server=${cfg.server}"
    else
      echo "$now ok offset=$off s server=${cfg.server}"
    fi
  '';
in
{
  options.programs.timeSync = {
    enable = lib.mkEnableOption "an hourly clock-offset check (sntp, no root, never sets the clock)";
    server = lib.mkOption { type = lib.types.str; default = "time.apple.com"; };
    maxOffset = lib.mkOption { type = lib.types.number; default = 1; description = "Seconds; a larger |offset| logs DRIFT."; };
  };

  config = lib.mkIf cfg.enable {
    launchd.agents.time-sync-check = {
      enable = true;
      config = {
        ProgramArguments = [ "${check}" ];
        RunAtLoad = true;
        StartInterval = 3600;
        StandardOutPath = "${stateDir}/offset.log";
        StandardErrorPath = "${stateDir}/offset.log";
      };
    };

    home.activation.timeSyncStateDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg stateDir}
    '';
  };
}
