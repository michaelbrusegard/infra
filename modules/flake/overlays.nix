{inputs, ...}: {
  flake.overlays.default = import ../../overlays {inherit inputs;};
}
