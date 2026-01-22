inputs: {
  meta = {
    allowApplyAll = false;
    nixpkgs = system:
      import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [inputs.self.overlays.default];
      };
    specialArgs = {
      inherit inputs;
    };
  };
}

