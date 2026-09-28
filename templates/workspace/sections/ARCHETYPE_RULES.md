| Archetype | Cannot depend on | Can depend on |
|-----------|------------------|---------------|
| api-contract | anyone | external_deps only |
| engine | engine, library, feature | api-contract |
| library | feature | api-contract, engine, library |
| feature | nothing else | api-contract, engine, library |

Validating `workspace.yml` checks every `deps` entry against this table. A package lists in
`allowed_deps` the packages it may depend on despite the table; nothing checks the imports in the
sources.
