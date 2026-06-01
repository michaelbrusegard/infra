_: prev: {
  # The driver's Wayland keymap handler crashes (None -> keysym_from_name) on
  # our lv3/Mod5 modifier layout. Guard it until upstream fixes it. The source
  # ships with CRLF line endings (only stripped in preFixup, after patchPhase),
  # so normalize to LF first or the LF-context patch fails to apply.
  asus-dialpad-driver = prev.asus-dialpad-driver.overrideAttrs (old: {
    prePatch =
      (old.prePatch or "")
      + ''
        sed -i 's/\r$//' dialpad.py
      '';
    patches =
      (old.patches or [])
      ++ [./wayland-keysym-none.patch];
  });
}
