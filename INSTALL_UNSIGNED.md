# Install Unsigned QatVasl Builds

QatVasl release artifacts are currently unsigned and not notarized.
On macOS, Gatekeeper may show: "QatVasl is damaged and can't be opened".

This is expected for unsigned apps downloaded from the internet.

## Quick Fix (Terminal)

1. Move `QatVasl.app` to `/Applications`.
2. Run:

```bash
xattr -dr com.apple.quarantine /Applications/QatVasl.app
open /Applications/QatVasl.app
```

## Helper Script

You can also run:

```bash
scripts/open-unsigned-app.sh /Applications/QatVasl.app
```

## Alternative (GUI)

1. Try opening `QatVasl.app` once (it will fail).
2. Open `System Settings` > `Privacy & Security`.
3. Find the blocked app message and click `Open Anyway`.
4. Confirm open.

## Security Note

Only run these steps if you trust the source of the app.
