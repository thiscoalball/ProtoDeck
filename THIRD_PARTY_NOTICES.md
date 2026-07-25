# Third-party notices

ProtoDeck's Apache-2.0 license applies to original project code only. Third-party software, fonts,
data and online services remain subject to their own licenses and terms. This file is an attribution
index; the complete license text shipped with a component controls if this summary differs from it.

## Embedded and bundled components

### iPerf 3

- Project: ESnet iPerf
- Version: 3.21 for distributed application builds
- License: BSD-style license, with additional notices for bundled source files
- Source and complete license: `app/android/app/src/main/cpp/iperf/`
- Upstream: https://github.com/esnet/iperf

Android links the maintained native source. Linux and Windows packaging scripts provide a pinned
iPerf executable and retain the applicable notices.

### Cygwin runtime for Windows iPerf

- Component: Cygwin runtime used by the bundled Windows iPerf executable
- License information: https://cygwin.com/licensing.html
- Distribution details: `app/third_party/iperf3-windows-NOTICE.txt`

The Windows packaging process includes the corresponding Cygwin source archive and license material
in the distributed bundle. Those files must not be removed when redistributing that bundle.

### Droid Sans Fallback

- Component: `DroidSansFallbackFull.ttf`
- License: Apache License 2.0
- Complete license: `app/assets/fonts/DroidSansFallbackFull-LICENSE.txt`

### SMBJ

- Project: SMBJ
- License: Apache License 2.0
- Upstream: https://github.com/hierynomus/smbj

SMBJ is resolved as an Android Gradle dependency. Its transitive dependencies retain their own
licenses.

### Flutter and Dart packages

Package names and pinned versions are recorded in `app/pubspec.yaml` and
`app/pubspec.lock`. Each package retains its own license distributed in its source
package. Redistributors should preserve the license registry produced by Flutter and review it after
dependency updates.

## Data

### IEEE Registration Authority public listings

The offline OUI database is derived from the IEEE Registration Authority public MA-L, MA-M and MA-S
CSV listings:

- https://standards-oui.ieee.org/oui/oui.csv
- https://standards-oui.ieee.org/oui28/mam.csv
- https://standards-oui.ieee.org/oui36/oui36.csv

IEEE and related marks belong to their respective owners. ProtoDeck is not affiliated with or
endorsed by IEEE. Database metadata records source URLs, source hashes and generation information.

## Online providers

Public-IP, GeoIP, DNS-over-HTTPS, RDAP, map and connectivity providers are network services rather
than code incorporated into ProtoDeck. Default endpoints and the data sent to them are documented in
`docs/permissions.md`. Use of those services is subject to the provider's current terms and privacy
policy.

## Maintaining this file

Dependency, bundled binary, font, native source or dataset changes must update this index and retain
the corresponding complete license. Generated release archives should be checked before publication.
