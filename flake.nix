{
  description = "wozey.service flake";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      rec {
        packages.luvi =
          pkgs.stdenv.mkDerivation rec {
            pname = "luvi";
            version = "v2.12.0";
            src = pkgs.fetchgit {
              url = "https://github.com/luvit/luvi.git";
              rev = version;
              leaveDotGit = true;
              sha256 = "sha256-vBARlOyW+leh5d9gh/5LzqicKLpMNldgod4zobQ2Xac=";
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
        packages.luvit =
          let
            luvitSrc = pkgs.fetchgit {
              url = "https://github.com/luvit/luvit.git";
              rev = "2.17.0";
              leaveDotGit = true;
              sha256 = "sha256-1p67H/Na8G1OYVjRHokl/VeWJeyn5ssfoZZFo5kQFZQ=";
            };
          in
          pkgs.writeShellScriptBin "luvit" ''
            ${packages.luvi}/bin/luvi ${luvitSrc} -- "$@"
          '';

        packages.wozey =
          let
            wozeySrc = builtins.toString ./.;
          in
          pkgs.writeShellScriptBin "wozey" ''
            ${packages.luvit}/bin/luvit ${wozeySrc}/main.lua
          '';
      }
    );
}
