require ["editheader", "variables"];
deleteheader "X-Edge-Auth";
deleteheader "Authentication-Results";
set "spf" "none";
if string :is "${env.spf.result}" "pass" { set "spf" "pass"; }
if string :is "${env.spf.result}" "fail" { set "spf" "fail"; }
if string :is "${env.spf.result}" "softfail" { set "spf" "softfail"; }
if string :is "${env.spf.result}" "neutral" { set "spf" "neutral"; }
if string :is "${env.spf.result}" "temperror" { set "spf" "temperror"; }
if string :is "${env.spf.result}" "permerror" { set "spf" "permerror"; }
if string :is "${env.spf.result}" "none" { set "spf" "none"; }
set "dkim" "none";
if string :is "${env.dkim.result}" "pass" { set "dkim" "pass"; }
if string :is "${env.dkim.result}" "fail" { set "dkim" "fail"; }
if string :is "${env.dkim.result}" "neutral" { set "dkim" "neutral"; }
if string :is "${env.dkim.result}" "temperror" { set "dkim" "temperror"; }
if string :is "${env.dkim.result}" "permerror" { set "dkim" "permerror"; }
if string :is "${env.dkim.result}" "none" { set "dkim" "none"; }
set "dmarc" "none";
if string :is "${env.dmarc.result}" "pass" { set "dmarc" "pass"; }
if string :is "${env.dmarc.result}" "temperror" { set "dmarc" "temperror"; }
if string :is "${env.dmarc.result}" "permerror" { set "dmarc" "permerror"; }
if string :is "${env.dmarc.result}" "none" { set "dmarc" "none"; }
if string :is "${env.dmarc.result}" "fail" { set "dmarc" "fail"; }
set "policy" "none";
if string :is "${env.dmarc.policy}" "reject" { set "policy" "reject"; }
if string :is "${env.dmarc.policy}" "quarantine" { set "policy" "quarantine"; }
if string :is "${env.dmarc.policy}" "none" { set "policy" "none"; }
if string :is "${env.dmarc.policy}" "unspecified" { set "policy" "unspecified"; }
addheader "X-Edge-Auth" "spf=${spf}; dkim=${dkim}; dmarc=${dmarc}; policy=${policy};";
