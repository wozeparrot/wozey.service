{
  description = "wozey.service dev flake";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
        {
          devShell = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              libopus
              libsodium
              ffmpeg
            ];

            LD_LIBRARY_PATH = "${pkgs.libopus}/lib:${pkgs.libsodium}/lib";

            shellHook = ''
              echo "${pkgs.libopus}"
            '';
          };
        }
    );
}
