{ pkgs, ... }: {
  gtk.iconCache.enable = true;
  environment.systemPackages = with pkgs; [
    qemu
  ];
  environment.sessionVariables = {
    LOCALE_ARCHIVE_2_11 = "${pkgs.glibcLocales}/lib/locale/locale-archive";
    LOCALE_ARCHIVE_2_27 = "${pkgs.glibcLocales}/lib/locale/locale-archive";
  };
}
