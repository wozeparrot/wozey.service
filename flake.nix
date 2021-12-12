{
  description = "wozey.service flake";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem
      (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          luvi = pkgs.stdenv.mkDerivation rec {
            pname = "luvi";
            version = "v2.13.0";
            src = pkgs.fetchgit {
              url = "https://github.com/luvit/luvi.git";
              rev = version;
              leaveDotGit = false;
              sha256 = "sha256-h9Xdm/+9X3AoqBj1LJftqn3+3PbdankfAJSBP3KnRgw=";
            };

            nativeBuildInputs = with pkgs; [
              git
              cmake
            ];
            buildInputs = with pkgs; [
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
              luvitSrc = pkgs.fetchgit {
                url = "https://github.com/luvit/luvit.git";
                rev = "2.18.1";
                leaveDotGit = false;
                sha256 = "sha256-nxvzfiHURbNMkEqjtpO5Ja+miwX/2JfUc7b29mIY1xs=";
              };
            in
            pkgs.writeShellScriptBin "luvit" ''
              ${luvi}/bin/luvi ${luvitSrc} -- "$@"
            '';
        in
        rec {
          packages.wozey =
            let
              wozeySrc = ./bot;
            in
            pkgs.writeShellScriptBin "wozey" ''
              export PATH="${pkgs.yt-dlp}/bin:${pkgs.ffmpeg}/bin:${pkgs.ffmpeg-normalize}/bin:${pkgs.busybox}/bin"
              LD_LIBRARY_PATH="${pkgs.libopus}/lib:${pkgs.libsodium}/lib" WOZEY_ROOT=${wozeySrc} ${luvit}/bin/luvit ${wozeySrc}/main.lua "$@"
            '';
          packages.wozey-compute = with pkgs.python3Packages; buildPythonApplication {
            pname = "wozey-compute";
            version = "0.1.0";

            src = ./compute;

            propagatedBuildInputs = [ transformers tokenizers pytorch bottle gevent ];
          };
          defaultPackage = packages.wozey;
          
          apps.wozey = flake-utils.lib.mkApp {
            drv = packages.wozey;
          };
          apps.wozey-compute = flake-utils.lib.mkApp {
            drv = packages.wozey-compute;
          };
          defaultApp = apps.wozey;

          devShell = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              luvi luvit
              
              cargo rustc
              libtorch-bin
            ];
          };
        }
      );
}
