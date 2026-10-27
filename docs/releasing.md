# Releasing

Update `MARKETING_VERSION` in the Xcode project, commit it, then push the matching tag:

```sh
git tag v0.0.10
git push origin v0.0.10
```

Tags matching `vMAJOR.MINOR.PATCH` (optionally `-alpha.N`, `-beta.N`, or `-rc.N`) run tests, build the universal app, sign and notarize a DMG, and publish it with a checksum as a GitHub release. Prerelease tags create prerelease GitHub releases. Signing credentials live in the `release` environment, which only `v*` tags can use.

## Rotating signing credentials

Export a new Developer ID Application certificate as a `.p12` or create a new App Store Connect team key, then replace the matching secrets with `gh secret set <NAME> --env release`:

| Credential | Secrets |
| --- | --- |
| Certificate | `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD` |
| Notary key | `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` |

If a certificate leaks, revoke it in the Apple Developer portal after the replacement is in place.
