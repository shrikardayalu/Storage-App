# Onboarding acquisition reporting

The final onboarding step asks **How did you hear about us?**, after the scan
and cleanup picks, immediately before Home. An empty or skipped scan goes to
this question too. One answer, no preselection, no free text. **Skip for now**
sends nothing and does not restrict any feature.

Channels: TikTok, Instagram, Facebook, Reddit/forums, simpleshrink.com (including
its blog and guides), search engines, App Store, YouTube, friend/family,
article/newsletter, and somewhere else. This is self-reported first discovery,
not automatic attribution of a specific ad, SEO query, or blog post.

## Configuration

TelemetryDeck app ID: `D3C0724A-3429-476D-882F-3450CA8D75DB`.
This is public configuration, not an API secret. It is set under
`TelemetryDeckAppID` in **both** `ios/project.yml` (Xcode) and
`ios/xtool-Info.plist` (WSL). No App Store URL is required.

Only `AcquisitionReporter.swift` can use the network. It posts directly to the
`com.simpleshrink` namespace at `https://nom.telemetrydeck.com/v2/namespace/com.simpleshrink/`
using TelemetryDeck's [v2 ingestion API](https://telemetrydeck.com/docs/ingest/v2/),
without an SDK, automatic session events, device metadata or a unique user ID.
The `clientUser` field is the same constant on every installation.

## Seeing channel totals

1. Open the saved [How people find SimpleShrink dashboard](https://dashboard.telemetrydeck.com/o/F6E161B9-089F-4B12-B1A2-8C4DF94A2396/apps/D3C0724A-3429-476D-882F-3450CA8D75DB/d/F8B543B5-51F1-49A1-89EF-23121906AFE3).
   **Discovery channels** groups response counts by `Acquisition.source`;
   **Total submitted survey answers** counts all submissions. It is saved in production mode.
2. In **Explore > Recent Events**, filter for `Onboarding.acquisitionSource`.
   Turn on **Test Mode** for development builds; release builds send production events.
3. When creating additional insights, filter that event, use **event/signal count**
   as the measure, and group by **`Acquisition.source`**.
4. Choose a date range. Export the resulting counts if needed.

The organization's **Namespace Status** page currently says **Queued for Data
Processing**. On the free plan, new events are processed between once an hour
and once a day. A 200 response confirms receipt, not immediate query availability.
The dashboard may remain empty/loading while its dataset is queued. Real-time
ingestion requires a paid plan; no upgrade was made. The channel query explicitly
uses `dataSource: "com.simpleshrink"`, `baseFilters: "thisApp"`, the app ID above,
and the `eventCount` aggregation.

Use **event counts**, not distinct users or sessions. Every response deliberately
shares a sender label. These are submitted responses, not all installs. Skips do
not appear, so percentages are shares of people who answered.

The first submit/skip decision is remembered per installation. Replaying
onboarding does not send another event. Offline submissions are saved locally
and retried on the next foreground launch. A successful HTTP response clears
the pending event. An ambiguous network failure after server acceptance can
cause a duplicate on retry; totals are approximate. Reinstalling can also
produce a new response. There is deliberately no identifier for deduplication.

## App Store privacy

For the reporting-enabled build, select **Yes, we collect data from this app**.
The manifest declares **Other Data Types** (the survey choice) and
**Product Interaction** (its submission), for **Analytics**, **not linked to
identity**, and **not used for tracking**. This categorization follows Apple's
broad definitions; confirm it against the archived build's privacy report.
No Device ID or User ID is transmitted by this implementation.

This does not require ATT permission: no cross-company ad tracking or data
brokering is implemented. The voluntary survey submission is explained on the
page. Do not claim **Data Not Collected**, even though the answer has no identity.
See [Apple's App Privacy definitions](https://developer.apple.com/app-store/app-privacy-details/).

Deploy the updated `/privacy` and `/support` pages before distributing this
build. Keep the manifest, privacy policy, and App Store Connect answers aligned.
If you later add an SDK, identifiers, advertising, or more event fields, review
the labels again; TelemetryDeck's SDK defaults differ from this minimal client.

## Verification (2026-11-16)

- Unsigned iOS app cross-compiled successfully with xtool and the Darwin SDK.
- Five reporting XCTest cases passed on the unchanged Foundation sources in an
  isolated Swift package: payload fields, skips/replays, successful delivery,
  failed HTTP response retry, and offline/missing-config retry.
- Device-access safety check, privacy plist parsing, website typecheck and
  focused lint passed.
- TelemetryDeck ingestion returned **200 OK** for one synthetic website response
  with `isTestMode: true`. No production response was sent. The dashboard query
  was saved and inspected; its charts were still loading during verification.
- Simulator layout checks and the full app XCTest suite require macOS/Xcode;
  CI now includes `acquisition` screenshots in light, dark and large-text modes.

### Physical iPhone follow-up

- Built, signed and installed the updated app via xtool on the connected iPhone.
  The installation service confirms its signed ID is
  `XTL-YWQ93M8UD9.com.simpleshrink.app` (xtool adds a team prefix).
- Automatic launch failed with `DebugserverClient.Error.unknown`; opening the app
  manually works. The user confirmed **Settings → Show Onboarding Again** opens
  onboarding. Updating the app preserves the prior onboarding-completed flag.
- Development builds also accept `-showOnboarding` as an explicit launch argument
  to reset only that completed flag, leaving cleanup history intact.
- Corrected ingestion to the organization's namespace and received **200 OK**
  for a namespaced synthetic test response. Queried results remain subject to
  the free plan's processing queue described above.
