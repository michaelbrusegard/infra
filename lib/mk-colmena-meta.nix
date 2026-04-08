inputs: {
  meta = {
    allowApplyAll = false;
    nixpkgs = import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
      overlays = [inputs.self.overlays.default];
    };
    specialArgs = {
      inherit inputs;
    };
  };
}
