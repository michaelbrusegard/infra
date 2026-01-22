inputs: {
  meta = {
    allowApplyAll = false;
    nixpkgs = import inputs.nixpkgs {
      system = builtins.currentSystem;
      config = {
        allowUnfree = true;
      };
      overlays = [inputs.self.overlays.default];
    };
    specialArgs = {
      inherit inputs;
    };
  };
}
