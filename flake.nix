{
  description = "wozey.service flake";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    let
      overlay = final: prev: {
        wozey =
          let
            luvi = final.stdenv.mkDerivation rec {
              pname = "luvi";
              version = "v2.13.0";
              src = prev.fetchgit {
                url = "https://github.com/luvit/luvi.git";
                rev = version;
                leaveDotGit = false;
                sha256 = "sha256-h9Xdm/+9X3AoqBj1LJftqn3+3PbdankfAJSBP3KnRgw=";
              };

              nativeBuildInputs = with prev; [
                git
                cmake
              ];
              buildInputs = with prev; [
                openssl
              ];

              configurePhase = ''
                echo ${version} > VERSION
                make regular-shared
              '';

              installPhase = ''
                mkdir -p $out/bin
                install -p build/luvi $out/bin/
              '';
            };
            luvit =
              let
                luvitSrc = prev.fetchgit {
                  url = "https://github.com/luvit/luvit.git";
                  rev = "2.18.1";
                  leaveDotGit = false;
                  sha256 = "sha256-nxvzfiHURbNMkEqjtpO5Ja+miwX/2JfUc7b29mIY1xs=";
                };
              in
              final.writeShellScriptBin "luvit" ''
                ${luvi}/bin/luvi ${luvitSrc} -- "$@"
              '';
          in
          rec {
            wozey =
              let
                wozeySrc = ./bot;
              in
              final.writeShellScriptBin "wozey" ''
                export PATH="${prev.yt-dlp}/bin:${prev.ffmpeg}/bin:${prev.ffmpeg-normalize}/bin:${prev.busybox}/bin"
                LD_LIBRARY_PATH="${prev.libopus}/lib:${prev.libsodium}/lib" WOZEY_ROOT=${wozeySrc} ${luvit}/bin/luvit ${wozeySrc}/main.lua "$@"
              '';
          };
      };
    in
    flake-utils.lib.eachDefaultSystem
      (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ overlay ];
          };
        in
        rec {
          packages = with pkgs.wozey; {
            inherit wozey;
          };
          defaultPackages = packages.wozey;
          defaultApp = packages.wozey;
        }
      ) // {
      overlay = overlay;
    };
}
