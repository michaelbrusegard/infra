{
  config,
  pkgs,
  ...
}: let
  ristrettoMac = "f0:2f:74:15:dd:d1";
  ristrettoHost = "10.0.186.16";
  ristrettoPort = config.secrets.wakeOnLan.ristretto.port;
  wakeRistretto = pkgs.writeShellApplication {
    name = "wake-ristretto-nc";
    runtimeInputs = [pkgs.wakeonlan pkgs.netcat-gnu];
    text = ''
      # If sshd already answers, skip the wake entirely.
      if ! nc -z -w1 ${ristrettoHost} ${ristrettoPort} 2>/dev/null; then
        wakeonlan -i 10.0.186.255 ${ristrettoMac} >&2

        # Poll for sshd to come up; cold boot can take a while.
        for _ in $(seq 1 60); do
          if nc -z -w1 ${ristrettoHost} ${ristrettoPort} 2>/dev/null; then
            break
          fi
          sleep 2
        done
      fi

      exec nc ${ristrettoHost} ${ristrettoPort}
    '';
  };
in {
  # Exposed on PATH so `ssh ristretto`'s ProxyCommand (`ssh macchiato
  # wake-ristretto-nc`) can find it.
  environment.systemPackages = [wakeRistretto];
}
