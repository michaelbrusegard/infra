inputs: {
  meta = {
    allowApplyAll = false;
    nixpkgs = import inputs.nixpkgs {
      config.allowUnfree = true;
      overlays = [inputs.self.overlays.default];
    };
    specialArgs = {
      inherit inputs;
    };
  };
}
