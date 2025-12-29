{ ... }:

{
  services.home-assistant = {
    enable = true;
    config = null;
    extraComponents = [
      "backup"
      "bluetooth"
      "config"
      "dhcp"
      "energy"
      "go2rtc"
      "history"
      "homeassistant_alerts"
      "image_upload"
      "logbook"
      "media_source"
      "mobile_app"
      "my"
      "ssdp"
      "stream"
      "sun"
      "usb"
      "webhook"
      "zeroconf"
      "zha"
      "met"
      "otbr"
      "thread"
      "matter"
    ];
  };
}
