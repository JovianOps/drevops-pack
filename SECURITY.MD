# Security

## reporting a vulnerability

found a security issue? don't open a public issue — email me directly or open a private issue.

you'll get a response within 48h. if it's real, i'll patch and release asap.

## what to include

- description of the vulnerability
- steps to reproduce
- any suggested fixes (optional but helpful)

## scope

drevops-pack is a docker image that bundles PHP/composer tools. the main risks are:
- supply-chain issues with upstream `drevops/*` packages
- privilege escalation via the docker socket mount
- shell injection via the dispatcher (uses `exec`, so no shell interpolation in arguments)

## out of scope

- theoretical vulnerabilities in PHP/composer themselves
- vulnerabilities in the upstream drevops tools (report those to their repos)
- container escape techniques that require already having docker access
