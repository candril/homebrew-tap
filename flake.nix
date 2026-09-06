# Every tool packaged from its GitHub release binary — the same .gz and SHA256SUMS the
# curl installer and the Homebrew formula use — so all three routes install byte-identical
# binaries. Building from source under Nix would need a fixed-output hash for the bun
# dependency tree, which differs per platform (OpenTUI ships native packages) and changes
# with every bun.lock edit; a release hash is one line per platform in releases/<tool>.json
# and never needs a hand edit.
{
  description = "candril's terminal tools — lane, monq, presto, riff, topiq — from their releases";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      target = {
        aarch64-darwin = "darwin-arm64";
        x86_64-darwin = "darwin-x64";
        aarch64-linux = "linux-arm64";
        x86_64-linux = "linux-x64";
      };
      tools = builtins.fromJSON (builtins.readFile ./tools.json);
      released = lib.filterAttrs (name: _: builtins.pathExists (./releases + "/${name}.json")) tools;

      mkTool = pkgs: system: name: meta:
        let
          rel = builtins.fromJSON (builtins.readFile (./releases + "/${name}.json"));
          t = target.${system};
          runtime = map (p: pkgs.${p}) meta.nix_runtime;
        in
        pkgs.stdenvNoCC.mkDerivation {
          pname = name;
          version = rel.version;

          src = pkgs.fetchurl {
            url = "https://github.com/candril/${name}/releases/download/v${rel.version}/${name}-${t}.gz";
            sha256 = rel.sha256.${t};
          };
          dontUnpack = true;

          nativeBuildInputs = [ pkgs.makeWrapper ]
            ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.autoPatchelfHook ];
          # Bun-compiled binaries link glibc and libstdc++ dynamically.
          buildInputs = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.stdenv.cc.cc.lib ];

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            gunzip -c $src > $out/bin/${name}
            chmod +x $out/bin/${name}
            ${lib.optionalString (runtime != [ ]) ''
              wrapProgram $out/bin/${name} --prefix PATH : ${lib.makeBinPath runtime}
            ''}
            runHook postInstall
          '';

          meta = {
            description = meta.desc;
            homepage = meta.homepage;
            license = lib.licenses.mit;
            mainProgram = name;
            platforms = systems;
          };
        };
    in
    {
      packages = lib.genAttrs systems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in lib.mapAttrs (mkTool pkgs system) released
      );
    };
}
