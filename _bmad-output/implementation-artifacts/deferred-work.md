
- source_spec: `_bmad-output/implementation-artifacts/spec-recommended-hardening.md`
  summary: Config save/retry baseline after runtime reload failure
  evidence: Existing save writes TOML but advances baseline only on successful reload; add failed reload followed by save fixture.

- source_spec: `_bmad-output/implementation-artifacts/spec-recommended-hardening.md`
  summary: Coordinate external TOML writers during compare and atomic replacement
  evidence: Existing save detects prior edits but not another writer between compare and rename; needs cooperative writer protocol.

- source_spec: `_bmad-output/implementation-artifacts/spec-recommended-hardening.md`
  summary: Protect visual config baseline against load while awaited save runs
  evidence: Existing load action can reset the baseline during awaited runtime reload; needs generation/action guard regression.
