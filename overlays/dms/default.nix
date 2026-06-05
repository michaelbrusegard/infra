_: prev: {
  # DMS bar popouts request OnDemand keyboard focus without a HyprlandFocusGrab,
  # so on Hyprland with input.follow_mouse = 0 the keyboard focus never returns
  # to the previously focused window after a popout closes — you have to switch
  # workspaces to recover it. Inject the focus grab the same way DankModal does.
  #
  # The shell QML is copied into $out during postInstall (the derivation's `src`
  # is only the Go core), so the patch is applied against the installed tree
  # rather than via the usual patchPhase.
  dms-shell = prev.dms-shell.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + ''
        chmod -R u+w $out/share/quickshell/dms/Widgets
        ${prev.patch}/bin/patch -p1 \
          -d $out/share/quickshell/dms \
          < ${./dankpopout-focus-grab.patch}
      '';
  });
}
