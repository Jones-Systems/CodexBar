# Work Note — Hosted compiled-test identity mismatch

The CI/harness lane owns this bounded PR40 repair, separately from its frozen
product harness patches. Base: `19749e9e59c41d5a345cfcd8256add571755dbff` in the
app-selected `work/mac-build-once-test-shards-20261024` worktree. Root owns hosted
watching, integration and merge. No host provisioning, installation or native
app execution is authorized here.

## Source-bound diagnosis and intent

Completed run `40120003093`, producer job `120949328974`, logs a successful
`build-exported` event with image `20261013.0424.1`. Failed shard 0 job
`120952328273` uses image `20261021.0445.8`. Its exact artifact download succeeded
and manifest integrity passed before identity rejection. Both job logs select
macos-26-arm64, macOS 26.6.2 build 25G83, Xcode 26.3 build 17C529 and Swift 6.2.4;
their toolchain fingerprint is
`ba0d494e3bd99ca718c3b866478aecef3929bd982e54bdcc30bc90259845ac4f`.
Both check out `beba4178b557a826ace303bd3bfecb1d474de652`; the producer's package,
lock and profile hashes match that exact tracked source. No tests were executed
on the failed shard. This is no runtime or performance success proof.

Official runner-image releases identify the same OS build for
[20261013.0424.1](https://github.com/actions/runner-images/releases/tag/macos-26-arm64%2F20261013.0424)
and [20261021.0445.8](https://github.com/actions/runner-images/releases/tag/macos-26-arm64%2F20261021.0445),
but enumerate changed tools. Those inventories alone do not qualify compatibility
of the complete compiled runtime. Preserve exact image equality and every other
same-run/source/profile/package/toolchain/architecture/integrity constraint.
Report only allowlisted public identity fields on rejection, JSON-escape values,
bound value size, and never echo unknown metadata or structured values.

## Affected checks and evidence plan

Add a regression using the exact observed image pair, asserting both versions in
the diagnostic and rejection before extraction or Swift discovery. Retain tests
for every other identity mismatch and corrupt hashes. Exercise hostile unknown
metadata and malformed values without echoing them. Run the artifact/evidence
fixtures and affected path gate under fresh CPU admission and the nonblocking
portfolio lock; attempt required make test/check and report missing Swift/plutil.
Publish only this note and the artifact helper/fixture repair. Keep frozen product
packaging edits out of this commit and do not rerun an unchanged hosted candidate.

## Local outcome

Fresh admission reported 17.61% CPU and 33.38 GiB available RAM. The portfolio lock
was acquired nonblockingly and one serial process ran 89 artifact/evidence tests
successfully, followed by the passing CI path gate. Required make test/check
were attempted: both exit 2, at absent Swift and plutil respectively. The owned
fixture scratch was removed with absence verified. These results do not establish
hosted runtime compatibility or successful shard execution. The repair retains
strict identity equality; rollout mismatch remains an explicit qualification
failure, now with field-level evidence.
