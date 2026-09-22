# RSSOwl 2.3 — unofficial modernized build

The RSSOwl RSS/Atom reader, ported from Eclipse 3.8.2 / JDK 8 to **Eclipse
4.41 / JDK 21**, and from **Lucene 2.3.2 to Lucene 10.5.1**.

> **This is not an official RSSOwl release.** This repository has no
> affiliation with, sponsorship from, or endorsement by the RSSOwl Development
> Team. Any defect introduced here is this fork's, not upstream's — please do
> not report it to the original project.

## Provenance

| | |
|---|---|
| Upstream project | RSSOwl — https://sourceforge.net/projects/rssowl/ |
| Base revision | RSSOwl 2.1, source trunk r8644 |
| License | Eclipse Public License v1.0 — see [LICENSE](LICENSE) |
| Original copyright | (c) 2005-2011 RSSOwl Development Team |

The first commit (`master`) is the **unmodified upstream source**, so
`git diff master` shows exactly what was changed here and nothing else. All
modifications in this repository are likewise released under EPL-1.0, and the
copyright header in every source file is preserved.

Third-party libraries and everything not under EPL-1.0 are listed separately
in [NOTICE.md](NOTICE.md) — **read section 5 on db4o (GPL)** before
redistributing.

## Branches

| Branch | Contents |
|---|---|
| `master` | Upstream r8644, builds on Eclipse 3.8.2 + JDK 8 |
| `migrate-eclipse-4x` | Port to Eclipse 4.41 + JDK 21 |
| `migrate-lucene-10` | Most complete branch: adds Lucene 10.5.1, the news table, the installer |

## What changed

**Platform: Eclipse 4.41 + JDK 21**

Removed the Update Manager subsystem entirely — `org.rssowl.ui` called even
internal classes of `org.eclipse.update.*` (`InstallWizard2`,
`ConfigurationManagerWindow`), and those bundles no longer exist in Eclipse
4.x. Fixed two runtime breakages that only surfaced when actually running on
4.41 + JDK 21, plus three real defects the compiler warnings pointed at.
Cleaned up 86 unused imports, 22 unnecessary `@SuppressWarnings`, 8 redundant
superinterfaces, and 625 redundant type argument lists (diamond operator).

**Search: Lucene 2.3.2 → 10.5.1**

Ported the whole index/search layer to the Lucene 10 API. Added the
`org.rssowl.lib.lucene.queryparser` bundle wrapping the query parser jar.
Diacritics folding now happens consistently on both sides — when the index is
built and on the terms the query parser generates itself — so unaccented
queries match accented text. Indexes left behind by older Lucene versions are
detected and rebuilt automatically.

**News list**

The news list is drawn as a `Table` covering a whole feed, with items created
lazily via `SWT.VIRTUAL`, so opening a large feed no longer materializes every
row. Capped how many news items a single bookmark renders at once. Fixed the
row count and child count so the table is not short after a refresh.

**Embedded browser**

The reading pane runs on Microsoft Edge (WebView2), not Internet Explorer;
`isIE()` previously reported otherwise, which broke scroll position memory.
Hid the browser preferences only IE honours. Viewer images are served over
real HTTP so the buttons render, and the charset is declared explicitly.

**Versioning and packaging**

Bumped to 2.3.0, repaired stale build metadata and a splash screen showing the
wrong version. Added a Windows installer path: the product is trimmed to ~84
bundles, shipped with a `jlink`-trimmed JRE, and packaged with Inno Setup.

**Tests**

Tests run outside the IDE through a headless application that invokes JUnit
directly.

## Building and running

Requires **JDK 21**, an **Eclipse 4.41 SDK** as the target platform, and
PowerShell on Windows. Pass `-EclipseHome` / `-JavaHome` to point at your own
paths — the defaults in the scripts are those of the development machine.

```powershell
.\build.ps1                 # compile with ecj, no IDE needed
.\run.ps1                   # build, deploy as an RCP runtime, launch
.\test.ps1                  # run the tests in a real runtime
.\package.ps1               # build the Windows installer (needs Inno Setup)
```

Each script has a header comment explaining what it does and why.

The old Ant/pluginbuilder build path (`org.rssowl.build/build.xml`) is **dead**
and no longer used; the reasons are recorded in
`org.rssowl.build/build_local.properties`. The jars under
`org.rssowl.build/build-files/` are leftovers from that path.

## License

Eclipse Public License v1.0. See [LICENSE](LICENSE) for the full text and
[NOTICE.md](NOTICE.md) for third-party components.
