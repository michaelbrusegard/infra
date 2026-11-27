{
  flake.modules.nixos.unifi = { pkgs, ... }: {
    services.unifi = {
      enable = true;
      # MongoDB's licence keeps it out of the public cache, and compiling it
      # takes hours. This is the vendor's build of the same release the source
      # package gave, so the data files need no migration.
      mongodbPackage = pkgs.mongodb-ce.overrideAttrs rec {
        version = "7.0.48";
        src = pkgs.fetchurl {
          url = "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2204-${version}.tgz";
          hash = "sha256-BBLE4frQriu2UDunnFvcvXGwnIpx4E+Rc/KNQNEBkWs=";
        };
      };
    };

    environment.persistence."/persistent".directories = [
      "/var/lib/unifi"
    ];
  };
}
