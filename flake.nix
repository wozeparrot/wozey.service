{
  description = "wozey.service flake";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  inputs.vosk-nix.url = "github:sbruder/nixpkgs/vosk";

  outputs = inputs @ {
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem
    (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          config.allowBroken = true;
        };
        vosk-nix = import inputs.vosk-nix {
          inherit system;
          overlays = [
            (self: super: {
              python3Packages =
                pkgs.python3Packages
                // {
                  vosk = super.python3Packages.vosk.overrideAttrs (oldAttrs: {
                    propagatedBuildInputs = with pkgs.python3Packages; [
                      cffi
                      requests
                      srt
                      tqdm
                      websockets
                    ];
                  });
                };
            })
          ];
        };

        luvi = pkgs.stdenv.mkDerivation rec {
          pname = "luvi";
          version = "v2.14.0";
          src = pkgs.fetchgit {
            url = "https://github.com/luvit/luvi.git";
            rev = version;
            leaveDotGit = false;
            sha256 = "sha256-c1rvRDHSU23KwrfEAu+fhouoF16Sla6hWvxyvUb5/Kg=";
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
        luvit = let
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
        lit = let
          litSrc = pkgs.fetchgit {
            url = "https://github.com/luvit/lit.git";
            rev = "3.8.5";
            sha256 = "sha256-8Fy1jIDNSI/bYHmiGPEJipTEb7NYCbN3LsrME23sLqQ=";
          };
        in
          pkgs.writeShellScriptBin "lit" ''
            ${luvi}/bin/luvi ${litSrc} -- "$@"
          '';
      in rec {
        packages.wozey = let
          wozeySrc = ./bot;
        in
          pkgs.writeShellScriptBin "wozey" ''
            export PATH="${pkgs.yt-dlp}/bin:${pkgs.ffmpeg}/bin:${pkgs.ffmpeg-normalize}/bin:${pkgs.busybox}/bin"
            LD_LIBRARY_PATH="${pkgs.libopus}/lib:${pkgs.libsodium}/lib" WOZEY_ROOT=${wozeySrc} ${luvit}/bin/luvit ${wozeySrc}/main.lua "$@"
          '';
        packages.wozey-compute = with pkgs.python3Packages;
          buildPythonApplication {
            pname = "wozey-compute";
            version = "0.1.0";

            src = ./compute;

            propagatedBuildInputs = let
              espnet = pkgs.python3Packages.buildPythonPackage rec {
                pname = "espnet";
                version = "202301";

                src = pkgs.fetchPypi {
                  inherit pname version;
                  sha256 = "sha256-QkzCSo6jeQB2F2FZjphdngIAeBNJerI8XqA7o6h7lpk=";
                };

                prePatch = ''
                  substituteInPlace setup.py \
                    --replace "jamo==0.4.1" "jamo" \
                    --replace "protobuf<=3.20.1" "protobuf" \
                    --replace "importlib-metadata<5.0" "importlib-metadata" \
                    --replace "hydra-core" "" \
                    --replace "fast-bss-eval==0.1.3" "fast-bss-eval"
                '';

                propagatedBuildInputs = with pkgs.python3Packages; [
                  configargparse
                  editdistance
                  h5py
                  humanfriendly
                  importlib-metadata
                  jamo
                  librosa
                  opt-einsum
                  protobuf
                  pytest-runner
                  pyworld
                  pyyaml
                  scipy
                  sentencepiece
                  soundfile
                  typeguard
                  (pkgs.python3Packages.buildPythonPackage rec {
                    pname = "torch-complex";
                    version = "0.4.3";

                    src = pkgs.fetchPypi {
                      inherit version;
                      pname = "torch_complex";
                      sha256 = "sha256-i4yjNjTQwP03bgrSryPxiQTRCgmA8Q2z+k23dqZ3fws=";
                    };

                    propagatedBuildInputs = with pkgs.python3Packages; [
                      numpy
                      pytest-runner
                    ];

                    doCheck = false;
                  })
                  (pkgs.python3Packages.buildPythonPackage rec {
                    pname = "fast-bss-eval";
                    version = "0.1.4";

                    src = pkgs.fetchPypi {
                      inherit version;
                      pname = "fast_bss_eval";
                      sha256 = "sha256-ubEwdXf3cSjdqe+4MQ/01Mo5r8D8zODGJkCh40+a3RM=";
                    };

                    propagatedBuildInputs = with pkgs.python3Packages; [
                      numpy
                      scipy
                    ];

                    doCheck = false;
                  })
                  (pkgs.python3Packages.buildPythonPackage rec {
                    pname = "hydra-core";
                    version = "1.3.2";

                    src = pkgs.fetchPypi {
                      inherit pname version;
                      sha256 = "sha256-ioeO1nIWmXw+nYio5y57R2foGvN6+06jM0smmkOQqCQ=";
                    };

                    prePatch = ''
                      substituteInPlace requirements/requirements.txt \
                        --replace "antlr4-python3-runtime==4.9.*" "antlr4-python3-runtime"
                    '';

                    nativeBuildInputs = with pkgs; [
                      jre_minimal
                    ];

                    propagatedBuildInputs = with pkgs.python3Packages; [
                      antlr4-python3-runtime
                      packaging
                      (omegaconf.overridePythonAttrs (oldAttrs: {
                        doCheck = false;
                      }))
                    ];

                    doCheck = false;
                  })
                  (pkgs.python3Packages.buildPythonPackage rec {
                    pname = "pytorch-wpe";
                    version = "0.0.1";

                    src = pkgs.fetchPypi {
                      inherit version;
                      pname = "pytorch_wpe";
                      sha256 = "sha256-/H5wa1QRgAxEg/6U233Nguz2xXvAE69SmrT7Z1ycwpw=";
                    };

                    propagatedBuildInputs = with pkgs.python3Packages; [
                      numpy
                    ];

                    doCheck = false;
                  })
                  (pkgs.python3Packages.buildPythonPackage rec {
                    pname = "ctc-segmentation";
                    version = "1.7.4";

                    src = pkgs.fetchPypi {
                      inherit version;
                      pname = "ctc_segmentation";
                      sha256 = "sha256-GdOD6l8iQ467FpnXKyIHi2PzUaM/pQvtsZwUB3umoRY=";
                    };

                    propagatedBuildInputs = with pkgs.python3Packages; [
                      cython
                      numpy
                    ];

                    doCheck = false;
                  })
                  (pkgs.python3Packages.buildPythonPackage rec {
                    pname = "kaldiio";
                    version = "2.18.0";

                    src = pkgs.fetchPypi {
                      inherit pname version;
                      sha256 = "sha256-AcsdAVLq/GC9vZq9Wyl7CM1LLOc4XHoROwYhJpQiXUI=";
                    };

                    propagatedBuildInputs = with pkgs.python3Packages; [
                      numpy
                      pytest-runner
                    ];

                    doCheck = false;
                  })
                  (pkgs.python3Packages.buildPythonPackage rec {
                    pname = "espnet-tts-frontend";
                    version = "0.0.3";

                    src = pkgs.fetchPypi {
                      inherit version;
                      pname = "espnet_tts_frontend";
                      sha256 = "sha256-1GRN1lxXGDZjczscFGwsT8UwOumkZFJ5tb2q16exfU4=";
                    };

                    propagatedBuildInputs = with pkgs.python3Packages; [
                      inflect
                      unidecode
                      jaconv
                      (pypinyin.overrideAttrs (oldAttrs: rec {
                        version = "0.44.0";

                        src = pkgs.fetchFromGitHub {
                          owner = "mozillazg";
                          repo = "python-pinyin";
                          rev = "refs/tags/v${version}";
                          hash = "sha256-LYiiZvpM/V3QRyTUXGWGnSnR0AnqWfTW0xJB4Vnw7lI=";
                        };
                      }))
                      (pkgs.python3Packages.buildPythonPackage rec {
                        pname = "g2p-en";
                        version = "2.1.0";

                        src = pkgs.fetchPypi {
                          inherit version;
                          pname = "g2p_en";
                          sha256 = "sha256-MuyxGYJ6OxDqjBGXJ29OpPRAcK5Wy70B8PJhh19Valg=";
                        };

                        prePatch = ''
                          substituteInPlace setup.py \
                            --replace "distance>=0.1.3" ""
                        '';

                        propagatedBuildInputs = with pkgs.python3Packages; [
                          inflect
                          nltk
                          numpy
                        ];

                        doCheck = false;
                      })
                    ];

                    doCheck = false;
                  })
                  (pkgs.python3Packages.buildPythonPackage rec {
                    pname = "ci-sdr";
                    version = "0.0.2";

                    src = pkgs.fetchPypi {
                      inherit version;
                      pname = "ci_sdr";
                      sha256 = "sha256-P51MIFubfFwyOakEALgfHybss4SEpGFQ0md/9kahNGU=";
                    };

                    propagatedBuildInputs = with pkgs.python3Packages; [
                      einops
                      pytorch
                      scipy
                    ];

                    doCheck = false;
                  })
                  (pypinyin.overrideAttrs (oldAttrs: rec {
                    version = "0.44.0";

                    src = pkgs.fetchFromGitHub {
                      owner = "mozillazg";
                      repo = "python-pinyin";
                      rev = "refs/tags/v${version}";
                      hash = "sha256-LYiiZvpM/V3QRyTUXGWGnSnR0AnqWfTW0xJB4Vnw7lI=";
                    };
                  }))
                ];

                doCheck = false;
              };
            in [
              bottle
              espnet
              gevent
              nltk
              vosk-nix.python3Packages.vosk
              pytorch
              sentencepiece
              sounddevice
              soundfile
              tokenizers
              transformers
              (pkgs.python3Packages.buildPythonPackage rec {
                pname = "whispercpp";
                version = "0.0.17";

                src = pkgs.fetchPypi {
                  inherit pname version;
                  sha256 = "sha256-F0osguDue8xMITAWM9+G195JOV2B2UVam+37DHkIE94=";
                };

                doCheck = false;
              })
              (pkgs.python3Packages.buildPythonPackage rec {
                pname = "pyopenjtalk";
                version = "0.2.0";

                src = pkgs.fetchPypi {
                  inherit pname version;
                  sha256 = "sha256-/yA8zFPG814i/T0u0XRh1BrXQc++20EsdDtxzD+r67w=";
                };

                nativeBuildInputs = with pkgs; [
                  cmake
                ];

                propagatedBuildInputs = with pkgs.python3Packages; [
                  cython
                  numpy
                  six
                  tqdm
                ];

                dontUseCmakeConfigure = true;

                doCheck = false;
              })
              (pkgs.python3Packages.buildPythonPackage rec {
                pname = "romajitable";
                version = "0.0.1";

                src = pkgs.fetchPypi {
                  inherit pname version;
                  sha256 = "sha256-ue718BG/8ov1xhGKpzxKSEdY9wVmrIWyaFNUBCR5Joc=";
                };
              })
              (pkgs.python3Packages.buildPythonPackage rec {
                pname = "espnet-model-zoo";
                version = "0.1.7";

                src = pkgs.fetchPypi {
                  inherit version;
                  pname = "espnet_model_zoo";
                  sha256 = "sha256-YdiKGJjX1r/r61EQDxlPp/ybaPlZkTJV7lzPaAkEZbA=";
                };

                propagatedBuildInputs = with pkgs.python3Packages; [
                  espnet
                  huggingface-hub
                  pandas
                  pytest-runner
                ];

                doCheck = false;
              })
            ];
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
            luvi
            lit
            luvit

            cargo
            rustc
            libtorch-bin
            packages.wozey-compute
          ];

          LD_LIBRARY_PATH = "${pkgs.libopus}/lib:${pkgs.libsodium}/lib";
        };
      }
    );
}
