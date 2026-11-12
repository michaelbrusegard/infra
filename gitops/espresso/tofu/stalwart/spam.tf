# Junk-only handling: Postfix already accepted the message into its queue.
# Native authentication and contact/reply learning run here, not at the edge.
resource "stalwart_spam_settings" "this" {
  enable                = true
  score_spam            = 5
  score_reject          = 0
  score_discard         = 0
  trust_contacts        = true
  trust_replies         = true
  spam_filter_rules_url = "https://github.com/stalwartlabs/spam-filter/releases/download/v3.0.1/spam-filter-rules.json.gz"
}

resource "stalwart_spam_pyzor" "this" {
  enable = false
}

# The pinned rules seed BLOCKED_DOMAIN as a Reject tag, which would refuse
# mail the edge has already queued. Tags are unique by name: create adopts
# the seeded tag at its ID and switches it to Score in place, and rule
# updates never overwrite an existing tag. Never destroy it, or the next
# rules update restores Reject.
resource "stalwart_spam_tag_score" "blocked_domain" {
  lifecycle {
    prevent_destroy = true
  }

  tag   = "BLOCKED_DOMAIN"
  score = 1000
}
