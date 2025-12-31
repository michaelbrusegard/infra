{pkgs, ...}: {
  home.packages = with pkgs; [
    curl
    wget
    zstd
    file
    unzip
    unrar
    rsync
    fontconfig
    age
    sops
    uutils-coreutils
    findutils
    gnumake
    gnutar
    openssl
  ];
}
