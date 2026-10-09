{
  description = "Odin + raylib TSP brute force";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      libs = with pkgs; [
        # libGL
        # libxkbcommon
        # wayland
        # (pkgs.libx11 or pkgs.xorg.libX11)
        # (pkgs.libxcursor or pkgs.xorg.libXcursor)
        # (pkgs.libxrandr or pkgs.xorg.libXrandr)
        # (pkgs.libxi or pkgs.xorg.libXi)
        # (pkgs.libxinerama or pkgs.xorg.libXinerama)
        # (pkgs.libxext or pkgs.xorg.libXext)
      ];
    in {
      devShells.${system}.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [ odin pkg-config clang gnumake ];
        buildInputs = libs;
        shellHook = ''
          export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath libs}:$LD_LIBRARY_PATH"
        '';
      };
    };
}
