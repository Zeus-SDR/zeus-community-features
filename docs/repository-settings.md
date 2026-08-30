# Required repository settings

`main` is the protected review and publication boundary. Configure a GitHub
ruleset for `refs/heads/main` with pull requests, one code-owner approval for
outside contributions, stale-review dismissal, resolved conversations, strict
required Actions checks, and blocked force-push/deletion.

Set default workflow-token permissions to read-only. Keep `@Kb2uka` and
`@iamexemplar` as explicit bypass actors so either maintainer retains
independent authority for their own work.

Never attach self-hosted runners to this public repository and never use
`pull_request_target` to check out or execute contributor content. Future CDN
credentials belong in a protected post-merge environment whose job does not
execute feature code.

