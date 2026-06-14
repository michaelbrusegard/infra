_: prev: {
  # DMS bar popouts request OnDemand keyboard focus without a HyprlandFocusGrab,
  # so on Hyprland with input.follow_mouse = 0 the keyboard focus never returns
  # to the previously focused window after a popout closes — you have to switch
  # workspaces to recover it. Inject the focus grab the same way DankModal does.
  #
  # The shell QML is copied into $out during postInstall (the derivation's `src`
  # is only the Go core), so the patch is applied against the installed tree
  # rather than via the usual patchPhase.
  #
  # Hyprland 0.55 switched dispatch IPC to the Lua API, so the legacy
  # `Hyprland.dispatch("dpms off"/"dpms on")` calls fail with a Lua syntax
  # error and the monitors never blank (or wake) on lock/idle. Upstream master
  # already fixed this via HyprlandService.dpms{Off,On}() with the new
  # `hl.dsp.dpms({ action = ... })` form, but the fix has not landed in the
  # `stable` branch (still v1.4.6). Rewrite the two call sites to the 0.55
  # syntax until stable ships the gated fix — then drop this hunk.
  dms-shell = prev.dms-shell.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + ''
        chmod -R u+w $out/share/quickshell/dms/Widgets
        ${prev.patch}/bin/patch -p1 \
          -d $out/share/quickshell/dms \
          < ${./dankpopout-focus-grab.patch}

        chmod u+w $out/share/quickshell/dms/Services/CompositorService.qml
        substituteInPlace $out/share/quickshell/dms/Services/CompositorService.qml \
          --replace-fail 'return Hyprland.dispatch("dpms off");' \
                         'return Hyprland.dispatch(`hl.dsp.dpms({ action = "disable" })`);' \
          --replace-fail 'return Hyprland.dispatch("dpms on");' \
                         'return Hyprland.dispatch(`hl.dsp.dpms({ action = "enable" })`);'
      '';
  });
}
