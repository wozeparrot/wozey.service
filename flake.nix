{
  description = "wozey.service flake";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    let
      overlay = final: prev: {
        wozey = rec {
          luvi = final.stdenv.mkDerivation rec {
            pname = "luvi";
            version = "v2.12.0";
            src = prev.fetchgit {
              url = "https://github.com/luvit/luvi.git";
              rev = version;
              leaveDotGit = true;
              sha256 = "sha256-vBARlOyW+leh5d9gh/5LzqicKLpMNldgod4zobQ2Xac=";
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
                rev = "2.17.0";
                leaveDotGit = true;
                sha256 = "sha256-1p67H/Na8G1OYVjRHokl/VeWJeyn5ssfoZZFo5kQFZQ=";
              };
            in
            final.writeShellScriptBin "luvit" ''
              ${luvi}/bin/luvi ${luvitSrc} -- "$@"
            '';

          wozey =
            let
              wozeySrc = builtins.toString ./.;
            in
            prev.writeShellScriptBin "wozey" ''
              ${luvit}/bin/luvit ${wozeySrc}/main.lua
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
        {
          packages = with pkgs.wozey; {
            inherit wozey;
          };
        }
      ) // {
      overlay = overlay;
    };
}
