# Proton's records were created by hand. Adopt them with their live content so
# mail.tf rewrites them in place rather than publishing Stalwart's beside
# them. Import blocks stay so rebuilding state cannot duplicate records.
import {
  for_each = {
    proton_verification = "11255a6f2f2d308d5fdc9a95051d6bad"
    proton_dkim         = "b6a677282d765fd4d198beb3d48a1217"
    proton_dkim2        = "4ef6cd2b2d7c260c2b82db466b638d20"
    proton_dkim3        = "c95b6b2940ac8b24adba9a844b6723c6"
  }
  to = cloudflare_dns_record.safe[each.key]
  id = "${data.cloudflare_zone.michaelbrusegard.zone_id}/${each.value}"
}

import {
  for_each = {
    proton_verification = "540adf3c480e8ad2f1b261a5ba80dd88"
    proton_dkim         = "f20ad769eb4e0bb38927281fe23291ac"
    proton_dkim02       = "f76774cea102aeffe8258449b6a6bc21"
    proton_dkim03       = "018f793192ea8b59cbba661a49f950d4"
  }
  to = cloudflare_dns_record.michbrus[each.key]
  id = "${data.cloudflare_zone.michbrus.zone_id}/${each.value}"
}

# Proton's routing records exist only until the switch rewrites them.
import {
  for_each = var.mail_on_stalwart ? {} : {
    mx           = "eb67c5776a04afda3f998e0a80b40b31"
    mx_secondary = "d557aec2f184ef9ec82d7c1859f7e52b"
    spf          = "d6ea6136bd893cd3ae3fdc77023f340e"
    dmarc        = "842aac240dc17d2827cadd276e3f2fc6"
  }
  to = cloudflare_dns_record.safe[each.key]
  id = "${data.cloudflare_zone.michaelbrusegard.zone_id}/${each.value}"
}

import {
  for_each = var.mail_on_stalwart ? {} : {
    mx           = "3cb8852b802d40defc01fe8dada6a797"
    mx_secondary = "35b9ebe588a29dac6fa8e8c10f405351"
    spf          = "f7b2e03b44573d344e50123fd5bca867"
    dmarc        = "b2881cbedb5eb8c4042ab8b0ff2d29cb"
  }
  to = cloudflare_dns_record.michbrus[each.key]
  id = "${data.cloudflare_zone.michbrus.zone_id}/${each.value}"
}
