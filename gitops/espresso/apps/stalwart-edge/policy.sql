SELECT EXISTS(
 SELECT 1 FROM policy_recipients AS r
 JOIN policy_domains AS d ON d.name = r.domain AND d.source = r.source
 JOIN policy_sources AS s ON s.name = r.source
 WHERE r.address = lower(?1)
 AND d.name = lower(substr(?1, instr(?1, '@') + 1))
 AND instr(?1, '@') > 1
 AND instr(substr(?1, instr(?1, '@') + 1), '@') = 0
)
