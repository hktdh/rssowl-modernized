# NOTICE — Third-party components

All source code in this repository is distributed under the **Eclipse Public
License v1.0 (EPL-1.0)**, see [LICENSE](LICENSE). Every source file keeps the
original RSSOwl Development Team copyright header, as the header itself
requires.

This document lists the parts that are **not** under EPL-1.0, or that are
under EPL-1.0 but copyrighted by someone else. The list was compiled from
license files actually present in the repository, not inferred from external
documentation; anything that could not be verified from within the repository
is marked as such.

---

## 1. Exceptions inside the RSSOwl source itself

Declared in [org.rssowl.core/about.html](org.rssowl.core/about.html):

| Component | License |
|---|---|
| `org.rssowl.core/src/.../HTMLStripReader.java` | Apache License 2.0 |
| `org.rssowl.core/src/.../HTMLFilterReader.java` | Apache License 2.0 |
| package `org.rssowl.core.internal.interpreter.json` | JSON License (http://www.json.org/license.html) |

## 2. Bundled runtime libraries

| Bundle | Library | License | License text |
|---|---|---|---|
| `org.rssowl.lib.db4o` | db4o 6.1 (`db4o-6.1-java5.jar`, `db4o-6.1-nqopt.jar`) | **GNU GPL** — see section 5 | `org.rssowl.lib.db4o/META-INF/db4o.license.txt` |
| `org.rssowl.lib.db4o` | BLOAT 1.0 (`bloat-1.0.jar`) | GNU LGPL v2.1 | `lgpl.license.txt` inside the jar |
| `org.rssowl.lib.httpclient` | Apache HttpClient 3.1, Commons Codec 1.3, Commons Logging 1.0.4 | Apache License 2.0 | `org.rssowl.lib.httpclient/META-INF/LICENSE.txt` |
| `org.rssowl.lib.jdom` | JDOM 1.1 | JDOM License (BSD/Apache style) | `org.rssowl.lib.jdom/META-INF/LICENSE.txt` |
| `org.rssowl.lib.lucene.queryparser` | Apache Lucene QueryParser 10.5.1 | Apache License 2.0 | `META-INF/LICENSE.txt` and `META-INF/NOTICE.txt` inside the jar |

Corresponding source for db4o, HttpClient and JDOM ships in the `src.zip` of
each bundle.

`org.rssowl.lib.lucene.queryparser` is a new bundle that does not exist in
upstream RSSOwl: it only wraps the Lucene 10.5.1 jar as an OSGi bundle and
contains no code written by us.

## 3. Build-time-only tooling

Located in `org.rssowl.build/build-files/`, inherited from upstream RSSOwl.
This pluginbuilder/Ant build path is **no longer used** (see the README); the
files are kept as-is.

| Component | License |
|---|---|
| ant-contrib (`ant-contrib.jar`) | Apache Software License 1.1 — `ant-contrib-LICENSE.txt` |
| Ganymed SSH-2 (`svn/ganymed.jar`) | BSD (ETH Zurich / Christian Plattner) — `LICENSE.txt` inside the jar |
| SVNKit (`svn/svnkit.jar`) | TMate Open Source License — `COPYING` and `SEQUENCE-LICENSE` inside the jar |
| `svn/svnant.jar`, `svn/svnClientAdapter.jar`, `svn/svnjavahl.jar` | Part of the svnant/Subversion projects (Apache License). The jars embed no license text — *not verifiable from within this repository* |
| EMMA (`automatedTests/emma.jar`, `emma_ant.jar`) | Common Public License 1.0 per the EMMA project. The jars embed no license text — *not verifiable from within this repository* |
| `pluginbuilder-anttasks.jar` | Part of the Pluginbuilder project (EPL-1.0). The jar embeds no license text — *not verifiable from within this repository* |
| `automatedTests/eclipse-test-framework-3.3.2.zip` | Eclipse Test Framework — EPL-1.0 |
| `automatedTests/org.pluginbuilder.autotestsuite.feature-*.zip` | Pluginbuilder Auto Test Suite — EPL-1.0 |

## 4. Test data

`org.rssowl.core.tests/data/performance/corpus_*.zip` contains snapshots of
real newsfeeds crawled in 2007, inherited from upstream RSSOwl. The article
content in them is **copyrighted by the respective publishers**, is not
covered by EPL-1.0, and is not licensed by RSSOwl. It exists only for
performance measurements.

## 5. Special note on db4o (GPL)

db4o is the only strong-copyleft component in this repository, and upstream
RSSOwl is inconsistent about which version applies:

- `org.rssowl.lib.db4o/META-INF/db4o.license.txt` is the full text of **GPL v2**
- `org.rssowl.lib.db4o/META-INF/about.html` states **GPL v3**

Either way, both permit redistribution provided the corresponding source is
made available — a condition satisfied by `org.rssowl.lib.db4o/src.zip`, which
is present in this repository.

Be aware: EPL-1.0 and the GPL are not compatible when combined into a single
derivative work. Here db4o is kept as a **separate OSGi bundle** reached only
through its API, exactly the arrangement upstream RSSOwl shipped publicly for
years. This repository does not change that situation. Anyone redistributing
this, or using it commercially, should evaluate that point for themselves.

## 6. Components present only in the installer (not in this repository)

`dist.ps1` and `package.ps1` produce a Windows installer that additionally
contains:

| Component | License |
|---|---|
| Eclipse 4.41 platform bundles + SWT | EPL-2.0 (taken from the target platform on the build machine) |
| Trimmed JRE produced with `jlink` from JDK 21 | Depends on the JDK used. With Eclipse Temurin 21 this is GPL v2 with Classpath Exception, which permits redistribution |
| Microsoft Edge WebView2 Runtime | **Not** bundled; the installer only checks for it and points the user to Microsoft |

If you distribute the installer, include the licenses of the Eclipse platform
and of the JDK actually used to build it.

## 7. Trademarks

"RSSOwl" and the owl logo are trademarks of the RSSOwl Development Team.
EPL-1.0 grants rights to the source code, **not** to trademarks. This
repository is an unofficial modified version with no affiliation with, or
endorsement by, the RSSOwl Development Team.
