# RegenWS — Contributing

## Archetype rules

<!-- WORKSPACE_ARCHETYPE_RULES_BEGIN -->
| Archetype | Cannot depend on | Can depend on |
|-----------|------------------|---------------|
| api-contract | anyone | external_deps only |
| engine | engine, library, feature | api-contract |
| library | feature | api-contract, engine, library |
| feature | nothing else | api-contract, engine, library |

`allowed_deps` per package overrides defaults. No tool checks imports against these rules: validating
`workspace.yml` rejects only a `deps` entry that a non-empty `allowed_deps` does not list.
<!-- WORKSPACE_ARCHETYPE_RULES_END -->

## Project-specific rules

(manual section — toolkit does not touch this)
