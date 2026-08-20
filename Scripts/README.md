# StarCatch offline orbit catalog

`update_catalog.py` is a release-time tool. The iOS app does not download orbital
data and does not need a network connection after installation.

The generator downloads the public CelesTrak active GP catalog in OMM JSON,
uses CelesTrak group membership plus conservative name rules for StarCatch's
task semantics, identifies major constellation families for independent sampling,
overlays the hand-authored metadata in
`catalog-curated.json`, rejects active element sets older than 14 days (or more
than 4 days ahead of packaging) as an absolute development limit, and
writes the bundled `StarCatch/Resources/catalog.json` snapshot.

From the repository root:

```sh
python3 Scripts/update_catalog.py --refresh-active
```

The normal release refresh performs one `GROUP=active` download and preserves the
previous snapshot's reviewed category assignments. This follows CelesTrak's request
to avoid repeatedly downloading overlapping groups. `--refresh-groups` is reserved
for an intentional classification-maintenance pass, not routine releases.

For a reproducible build from an already downloaded active snapshot:

```sh
python3 Scripts/update_catalog.py \
  --active-json /path/to/active-omm.json \
  --cache-dir /path/to/group-cache
```

Before release, verify the printed total/category counts, run `OrbitTests`, and
confirm `snapshotEpoch`, `generatedAt`, unique NORAD IDs, and the release gate's
72-hour age limit. Authored objects absent from the active source are retained only in the
legacy category and marked silent. TLE/OMM propagation is most reliable near
its epoch; refreshing the
bundled snapshot is therefore part of every App Store release.

Run the repository-wide archive gate after generating the catalog:

```sh
python3 Scripts/satellite_knowledge.py sync
python3 Scripts/satellite_knowledge.py validate
python3 Scripts/release_check.py
```

`sync` deterministically rebuilds only notes marked `review_status: generated`,
preserves authored notes, and refreshes every generated compact summary from
the object's real COSPAR/NORAD identity and OMM orbit. The validation and
release gates reject placeholder markers or duplicate first-layer/individual
story copy.

An Xcode Archive (`ACTION=install`) runs the same release check automatically.
The check rejects a stale packaged snapshot even if no catalog generation took
place during that build, and also verifies the privacy manifest, Info.plist,
App Icon and locked Swift Package dependency.
