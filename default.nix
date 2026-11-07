# The non-flake entry point: the home-manager module and the library.
{
  lib ? import <nixpkgs/lib>,
}:
{
  homeModule = ./modules;
  lib = import ./lib { inherit lib; };
}
