# Proton's records were created by hand. These stay so rebuilding state
# cannot duplicate them. Its MX, SPF and DMARC were adopted once the same way
# and are in state now; their import blocks are gone because the switch
# deletes the secondary MX, and an import of a deleted record fails the plan
# that would switch back.
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
