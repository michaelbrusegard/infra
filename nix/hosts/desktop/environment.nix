{ pkgs, ... }: {
  environment = {
    systemPackages = with pkgs; [
      kanata
      qemu
    ];
  }
};
