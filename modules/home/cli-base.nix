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
    ssh-to-age
    uutils-coreutils
    findutils
    gnumake
    gnutar
    openssl
    dos2unix
  ];
}
