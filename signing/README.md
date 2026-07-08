# Code signing setup (why the app used to "randomly" break)

macOS ties Accessibility and Microphone permissions (TCC) to the app's code signature.
Ad-hoc signatures (`codesign --sign -`) produce a different signature hash on every build, so each rebuild silently invalidated the old permission grants — the checkbox in System Settings stayed on, but paste-at-cursor stopped working.

The permanent fix is signing every build with one stable identity.

## One-time setup (already mostly done)

A self-signed code-signing certificate named **"Kalam Dev Signing"** (private key + cert) has been imported into the login keychain.
Its public certificate is `KalamDevSigning.crt` in this folder.

The only remaining step needs your password once — mark the certificate trusted for code signing:

```bash
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db "signing/KalamDevSigning.crt"
```

(Run from the repo root; approve the dialog.)

After that, `./build-app.sh` auto-detects the identity and every build carries the same signature.
Identity builds use hardened runtime, which **requires** `Kalam-direct.entitlements` (microphone entitlement) — signing without it makes mic access fail silently with no prompt.
The first codesign use of the key may show a "codesign wants to access key" dialog — click **Always Allow**.

## After the FIRST build with the new identity

The signature changes one final time, so re-grant once:

1. System Settings → Privacy & Security → Accessibility → remove the old Kalam entry (minus button), then re-add `/Applications/Kalam.app` and enable it.
2. Grant Microphone when the app prompts.

From then on, rebuilds keep the same identity and permissions stick permanently.

## If the certificate is ever lost

Regenerate (same procedure, 10-year validity):

```bash
openssl req -x509 -newkey rsa:2048 -keyout kalam-sign.key -out signing/KalamDevSigning.crt -days 3650 -nodes \
  -subj "/CN=Kalam Dev Signing" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:FALSE"
openssl pkcs12 -export -legacy -out kalam-sign.p12 -inkey kalam-sign.key -in signing/KalamDevSigning.crt -passout pass:TEMP -name "Kalam Dev Signing"
security import kalam-sign.p12 -k ~/Library/Keychains/login.keychain-db -P TEMP -T /usr/bin/codesign
security add-trusted-cert -p codeSign -k ~/Library/Keychains/login.keychain-db signing/KalamDevSigning.crt
```

Then delete `kalam-sign.key` / `kalam-sign.p12` (the identity lives in the keychain) and re-grant permissions once.
