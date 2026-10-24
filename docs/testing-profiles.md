# Test execution profiles

The shipped product and offline tests cover Codex, Claude and shared behavior.
Unused providers, provider plugins and QuickJS, hooks and iCloud synchronization
have been removed from source. Both `normal` and `full` remain valid profile
names for existing SwiftPM, CLI and CI callers; they select the same retained
source because the full-only and mixed full-only partitions are empty.

## Commands and restoration

```sh
make test
CODEXBAR_TEST_PROFILE=normal make test
CODEXBAR_TEST_PROFILE=full make test
python3 Scripts/test_profiles.py describe
```

An invalid explicit profile still fails. Profile and manifest digest remain part
of campaign/cache identity. Selecting `full` does not restore deleted code.
For deliberate restoration, recover the relevant implementation, tests and
package membership from Git revision
`91bd5fb4af704da9181212bea636d527a058e615`, then qualify the restored behavior.
See the [product spec](engineering-specs/slim-codex-claude-product.md).

## Retained boundaries

Codex/Claude account switching, credential isolation, quota/reset tracking,
persistence, local usage/spend history, cache integrity and scanner scale
regressions remain covered. No high-limit scanner or persistence fixture was
reduced for this removal. OpenAI dashboard/web parsing remains Codex coverage;
OpenCodex ingestion remains an optional spend source. Claude offline quota
fallback and widget quota fields remain.

MiniMax-named LogRedactor tests cover shared redaction. Kiro-named TTY process
and hard-stop suites protect shared process cleanup used by Codex and Claude.
Local fleet/account identity is retained independently of removed iCloud
transport. Tests with arbitrary retired-provider IDs use retained provider or
account scopes when their subject is shared behavior. Removed-provider adapters
and UI inventories have no retained product route.

The CLI and supported-platform build checks remain enabled. Offline tests do
not authorize Keychain, browser-cookie, private-account, live provider, signing
or packaging access. Native journey placement remains advisory and opt-in.
