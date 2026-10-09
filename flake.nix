{
  description = "Odin + raylib";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          odin
          clang
        ];

        buildInputs = [ pkgs.raylib ];
        LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.raylib ];
      };
    };
}
