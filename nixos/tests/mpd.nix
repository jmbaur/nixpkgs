{ pkgs, lib, ... }:
let
  track = pkgs.fetchurl {
    # Sourced from http://freemusicarchive.org/music/Blue_Wave_Theory/Surf_Music_Month_Challenge/Skyhawk_Beach_fade_in

    name = "Blue_Wave_Theory-Skyhawk_Beach.mp3";
    url = "https://freemusicarchive.org/file/music/ccCommunity/Blue_Wave_Theory/Surf_Music_Month_Challenge/Blue_Wave_Theory_-_04_-_Skyhawk_Beach.mp3";
    hash = "sha256-91VDWwrcP6Cw4rk72VHvZ8RGfRBrpRE8xo/02dcJhHc=";
    meta.license = lib.licenses.cc-by-sa-40;
  };

  defaultCfg = rec {
    user = "mpd";
    group = "mpd";
    dataDir = "/var/lib/mpd";
    musicDirectory = "${dataDir}/music";
  };

  defaultMpdCfg = {
    inherit (defaultCfg)
      dataDir
      musicDirectory
      user
      group
      ;
    enable = true;
  };

  musicService =
    {
      user,
      group,
      musicDirectory,
    }:
    {
      description = "Sets up the music file(s) for MPD to use.";
      requires = [ "mpd.service" ];
      after = [ "mpd.service" ];
      wantedBy = [ "default.target" ];
      script = ''
        cp ${track} ${musicDirectory}
      '';
      serviceConfig = {
        User = user;
        Group = group;
      };
    };

  mkServer =
    { mpd, musicService }:
    {
      boot.kernelModules = [ "snd-dummy" ];
      services.mpd = mpd;
      systemd.services.musicService = musicService;
    };
in
{
  name = "mpd";
  meta = {
    maintainers = with lib.maintainers; [ emmanuelrosa ];
  };

  nodes = {
    client = { ... }: { };

    serverALSA =
      { ... }:
      lib.mkMerge [
        (mkServer {
          mpd = defaultMpdCfg // {
            network.listenAddress = "any";
            extraConfig = ''
              audio_output {
                type "alsa"
                name "ALSA"
                mixer_type "null"
              }
            '';
          };
          musicService = musicService { inherit (defaultMpdCfg) user group musicDirectory; };
        })
        { networking.firewall.allowedTCPPorts = [ 6600 ]; }
      ];

    serverPulseAudio =
      { ... }:
      lib.mkMerge [
        (mkServer {
          mpd = defaultMpdCfg // {
            extraConfig = ''
              audio_output {
                type "pulse"
                name "The Pulse"
              }
            '';
          };

          musicService = musicService { inherit (defaultMpdCfg) user group musicDirectory; };
        })
        {
          services.pulseaudio = {
            enable = true;
            systemWide = true;
            tcp.enable = true;
            tcp.anonymousClients.allowAll = true;
          };
          systemd.services.mpd.environment.PULSE_SERVER = "localhost";
        }
      ];
  };

  testScript = ''
    mpc = "${lib.getExe pkgs.mpc} --wait"

    # Connects to the given server and attempts to play a tune.
    def play_some_music(server):
        server.wait_for_unit("mpd.service")
        server.succeed(f"{mpc} update")
        _, tracks = server.execute(f"{mpc} ls")

        for track in tracks.splitlines():
            server.succeed(f"{mpc} add {track}")

        _, added_tracks = server.execute(f"{mpc} playlist")

        # Check we succeeded adding audio tracks to the playlist
        assert len(added_tracks.splitlines()) > 0

        server.succeed(f"{mpc} play")

        _, output = server.execute(f"{mpc} status")
        # Assure audio track is playing
        assert "playing" in output

        server.succeed(f"{mpc} stop")


    play_some_music(serverALSA)
    play_some_music(serverPulseAudio)

    client.wait_for_unit("multi-user.target")
    client.succeed(f"{mpc} -h serverALSA status")

    # The PulseAudio-based server is configured not to accept external client connections
    # to perform the following test:
    client.fail(f"{mpc} -h serverPulseAudio status")
  '';
}
