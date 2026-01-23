inputs: system: {
  meta = {
    allowApplyAll = false;
    nixpkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [inputs.self.overlays.default];
    };
    specialArgs = {
      inherit inputs;
    };
  };
}
