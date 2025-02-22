{ lib
, stdenv
, stdenvNoCC
, rustPlatform
, fetchFromGitHub
, wrapGAppsHook
, cargo
, rustc
, cargo-tauri
, pkg-config
, nodePackages
, esbuild
, buildGoModule
, jq
, moreutils
, libayatana-appindicator
, gtk3
, webkitgtk
, libsoup
, openssl
, xdotool
}:

stdenv.mkDerivation rec {
  pname = "pot";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "pot-app";
    repo = "pot-desktop";
    rev = version;
    hash = "sha256-sAAdw7gYUQTHZYmxSAk2LByR+iMT836sQolk2NOgWD0=";
  };

  sourceRoot = "source/src-tauri";

  postPatch = ''
    substituteInPlace $cargoDepsCopy/libappindicator-sys-*/src/lib.rs \
      --replace "libayatana-appindicator3.so.1" "${libayatana-appindicator}/lib/libayatana-appindicator3.so.1"

    chmod -R +w ..
    # Disable auto update check by default
    sed -i -e '/auto_check/s/true/false/' src/main.rs ../src/windows/Config/index.jsx
  '';

  pnpm-deps = stdenvNoCC.mkDerivation {
    pname = "${pname}-pnpm-deps";
    inherit src version;

    nativeBuildInputs = [
      jq
      moreutils
      nodePackages.pnpm
    ];

    installPhase = ''
      export HOME=$(mktemp -d)
      pnpm config set store-dir $out
      # use --ignore-script and --no-optional to avoid downloading binaries
      # use --frozen-lockfile to avoid checking git deps
      pnpm install --frozen-lockfile --no-optional --ignore-script

      # Remove timestamp and sort the json files
      rm -rf $out/v3/tmp
      for f in $(find $out -name "*.json"); do
        sed -i -E -e 's/"checkedAt":[0-9]+,//g' $f
        jq --sort-keys . $f | sponge $f
      done
    '';

    dontFixup = true;
    outputHashMode = "recursive";
    outputHash = "sha256-lqGskG1MWbZKEmqJf4b9dGltmFHw/qOo/Sh7JIFS4IQ=";
  };

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "tauri-plugin-single-instance-0.0.0" = "sha256-M6uGcf4UWAU+494wAK/r2ta1c3IZ07iaURLwJJR9F3U=";
      "tauri-plugin-autostart-0.0.0" = "sha256-M6uGcf4UWAU+494wAK/r2ta1c3IZ07iaURLwJJR9F3U=";
      "enigo-0.1.2" = "sha256-99VJ0WYD8jV6CYUZ1bpYJBwIE2iwOZ9SjOvyA2On12Q=";
    };
  };

  nativeBuildInputs = [
    rustPlatform.cargoSetupHook
    cargo
    rustc
    cargo-tauri
    wrapGAppsHook
    nodePackages.pnpm
    pkg-config
  ];

  buildInputs = [
    gtk3
    libsoup
    libayatana-appindicator
    openssl
    webkitgtk
    xdotool
  ];

  ESBUILD_BINARY_PATH = "${lib.getExe (esbuild.override {
    buildGoModule = args: buildGoModule (args // rec {
      version = "0.17.15";
      src = fetchFromGitHub {
        owner = "evanw";
        repo = "esbuild";
        rev = "v${version}";
        hash = "sha256-AzkjVw3o+yP/l6jiMmgzaymb0el2/OcAl8WQYbuMprw=";
      };
      vendorHash = "sha256-+BfxCyg0KkDQpHt/wycy/8CTG6YBA/VJvJFhhzUnSiQ=";
    });
  })}";

  preBuild = ''
    export HOME=$(mktemp -d)
    pnpm config set store-dir ${pnpm-deps}
    pnpm install --offline --frozen-lockfile --no-optional --ignore-script
    chmod -R +w ../node_modules
    pnpm rebuild
    # Use cargo-tauri from nixpkgs instead of pnpm tauri from npm
    cargo tauri build -b deb
  '';

  preInstall = ''
    mv target/release/bundle/deb/*/data/usr/ $out
  '';

  meta = with lib; {
    description = "A cross-platform translation software";
    homepage = "https://pot.pylogmon.com";
    platforms = platforms.linux;
    license = licenses.gpl3Only;
    maintainers = with maintainers; [ linsui ];
  };
}

