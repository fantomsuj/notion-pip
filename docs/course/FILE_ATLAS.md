# Notion PiP File Atlas

This atlas maps every repository-owned path visible in the sorted union of
`git ls-files` and `git ls-files --others --exclude-standard`. The refreshed
inventory contains **262 current paths**, all tracked, including this atlas and
the completed presenter and condensed-talk artifacts. There are no nonignored
untracked paths. Every current path appears in exactly one table row.

Roles and symbols describe committed baseline
`e86d3daea299cc0073d42c217ddc2e4d2470ad94`. Pre-existing uncommitted product
and test edits were excluded; re-run the inventory and inspect current source
before treating a row as implementation authority.

Use the [architecture map](ARCHITECTURE_MAP.md) for runtime flows, the
[change guide](CHANGE_GUIDE.md) for ownership decisions, and the
[course syllabus](README.md) for lecture titles. “Consumer” names the immediate
reader or caller; “Evidence” names the nearest test boundary or explicitly marks
a row as Manual, Generated, Test support, or Reference.

Ignored artifact groups are deliberately absent from the inventory:

- `.build/` is SwiftPM compiler output.
- `dist/` is the staged, ad-hoc-signed application bundle.
- `node_modules/` is npm-installed dependency output.
- `.context/` and `.superpowers/` hold ignored local evidence/orchestration
  state rather than repository-owned product/course inputs.

Do not infer that all generated output is excluded:
[`Sources/NotionPiP/Resources/QuickCapture/editor.js`](../../Sources/NotionPiP/Resources/QuickCapture/editor.js)
is a checked-in generated runtime resource and therefore has its own row.

## Root and configuration

| Path | Role | Types / artifacts | Consumer | Lecture | Evidence |
|---|---|---|---|---|---|
| [`.codex/environments/environment.toml`](../../.codex/environments/environment.toml) | Defines Codex workspace environment | environment metadata | Codex workspace | [L2](02-repository-and-technology-stack.md) | Reference |
| [`.conductor/settings.toml`](../../.conductor/settings.toml) | Defines Conductor workspace settings | workspace metadata | Conductor | [L2](02-repository-and-technology-stack.md) | Reference |
| [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) | Runs repository CI checks | GitHub Actions workflow | contributors and releases | [L12](12-testing-debugging-and-change-workflow.md) | Reference |
| [`.gitignore`](../../.gitignore) | Excludes generated/local artifacts | Git ignore rules | Git and contributors | [L2](02-repository-and-technology-stack.md) | Reference |
| [`.gitkeep`](../../.gitkeep) | Retains an otherwise empty repository path | placeholder | Git | [L2](02-repository-and-technology-stack.md) | Reference |
| [`.impeccable.md`](../../.impeccable.md) | Records interface design guidance | design instructions | UI maintainers | [L11](11-views-settings-and-state.md) | Reference |
| [`AGENTS.md`](../../AGENTS.md) | Defines repository agent rules and setup safety | maintainer instructions | automation and contributors | [L12](12-testing-debugging-and-change-workflow.md) | Reference |
| [`Package.swift`](../../Package.swift) | Declares Swift tools, targets, resources, platform | SwiftPM manifest | SwiftPM/build script | [L2](02-repository-and-technology-stack.md) | Reference |
| [`README.md`](../../README.md) | Introduces product, build, and usage | project README | users and contributors | [L1](01-product-and-user-experience.md) | Reference |
| [`package-lock.json`](../../package-lock.json) | Pins web dependency graph | npm lockfile | npm ci and editor build | [L9](09-quick-capture-editor-bridge.md) | Generated |
| [`package.json`](../../package.json) | Defines web scripts and dependencies | npm manifest | web contributors/CI | [L9](09-quick-capture-editor-bridge.md) | Reference |
| [`tsconfig.json`](../../tsconfig.json) | Configures TypeScript checking | TypeScript config | tsc and editor sources | [L9](09-quick-capture-editor-bridge.md) | Reference |

## Swift — App

| Path | Role | Types / artifacts | Consumer | Lecture | Evidence |
|---|---|---|---|---|---|
| [`Sources/NotionPiP/App/AppCommandActionRelay.swift`](../../Sources/NotionPiP/App/AppCommandActionRelay.swift) | Relays command closures through composition | `AppCommandActionRelay` | composition and command model | [L4](04-composition-and-runtime.md) | Tests: AppCommandActionRelayTests |
| [`Sources/NotionPiP/App/AppCommandModel.swift`](../../Sources/NotionPiP/App/AppCommandModel.swift) | Defines shared app commands and groups | `AppCommandID`, `AppCommandModel` | SwiftUI and AppKit menus | [L11](11-views-settings-and-state.md) | Tests: AppCommandTests |
| [`Sources/NotionPiP/App/AppDelegate.swift`](../../Sources/NotionPiP/App/AppDelegate.swift) | Owns application lifecycle callbacks and URL handoff | `AppDelegate`, `ApplicationURLHandling` | NSApplication and runtime | [L3](03-application-lifecycle.md) | Tests: RuntimeTerminationTests |
| [`Sources/NotionPiP/App/AppRuntime+Activation.swift`](../../Sources/NotionPiP/App/AppRuntime+Activation.swift) | Routes page and capture activation | `AppRuntime` activation extension | views, shortcuts, URL routes | [L4](04-composition-and-runtime.md) | Tests: RuntimeActivationAndMenuBarTests |
| [`Sources/NotionPiP/App/AppRuntime+Persistence.swift`](../../Sources/NotionPiP/App/AppRuntime+Persistence.swift) | Serializes page persistence work | `AppRuntime` persistence extension | runtime activation and termination | [L8](08-persistence-and-restoration.md) | Tests: RuntimePinnedPagePersistenceTests |
| [`Sources/NotionPiP/App/AppRuntime.swift`](../../Sources/NotionPiP/App/AppRuntime.swift) | Publishes the application facade and state | `AppRuntime` | all SwiftUI surfaces and composition | [L4](04-composition-and-runtime.md) | Tests: AppRuntimeFacadeTests |
| [`Sources/NotionPiP/App/AppRuntimeStateTypes.swift`](../../Sources/NotionPiP/App/AppRuntimeStateTypes.swift) | Defines runtime health and connection values | `ServiceHealthState`, activation/token states | runtime and status views | [L4](04-composition-and-runtime.md) | Tests: AppRuntimeFacadeTests |
| [`Sources/NotionPiP/App/NotionConnectionController.swift`](../../Sources/NotionPiP/App/NotionConnectionController.swift) | Coordinates token-backed workspace connection | `NotionConnectionController`, client lease | settings and delivery | [L10](10-notion-api-and-delivery.md) | Tests: NotionConnectionControllerTests |
| [`Sources/NotionPiP/App/NotionPiPApp.swift`](../../Sources/NotionPiP/App/NotionPiPApp.swift) | Builds dependencies and starts the process | `NotionPiPApp`, `AppStartup`, composition | NSApplication entry point | [L3](03-application-lifecycle.md) | Tests: RuntimeTerminationTests |
| [`Sources/NotionPiP/App/PageSwitcherController.swift`](../../Sources/NotionPiP/App/PageSwitcherController.swift) | Owns switcher loading, selection, and pin intent | `PageSwitcherController` | PageSwitcherView | [L4](04-composition-and-runtime.md) | Tests: PageSwitcherMatcherTests |
| [`Sources/NotionPiP/App/PageURLInputState.swift`](../../Sources/NotionPiP/App/PageURLInputState.swift) | Owns typed page-URL form state | `PageURLInputState` | URL input view/presenter | [L4](04-composition-and-runtime.md) | Tests: PageURLInputPresenterTests |
| [`Sources/NotionPiP/App/PanelSizeController.swift`](../../Sources/NotionPiP/App/PanelSizeController.swift) | Coordinates saved panel-size choices | `PanelSizeController`, `PanelSizing` | size menus/settings and panel | [L4](04-composition-and-runtime.md) | Tests: PanelSizeControllerTests |
| [`Sources/NotionPiP/App/PinCoordinator.swift`](../../Sources/NotionPiP/App/PinCoordinator.swift) | Converges page pin/show/replace commands | `PinCoordinator`, `PinInputError` | AppRuntime and panel coordinator | [L4](04-composition-and-runtime.md) | Tests: PinCoordinatorTests |
| [`Sources/NotionPiP/App/QuickCaptureDestinationController.swift`](../../Sources/NotionPiP/App/QuickCaptureDestinationController.swift) | Publishes destination selection/search state | `QuickCaptureDestinationController` | destination settings | [L10](10-notion-api-and-delivery.md) | Tests: QuickCaptureDestinationControllerTests |

## Swift — Domain

| Path | Role | Types / artifacts | Consumer | Lecture | Evidence |
|---|---|---|---|---|---|
| [`Sources/NotionPiP/Domain/CaptureExport.swift`](../../Sources/NotionPiP/Domain/CaptureExport.swift) | Renders recoverable capture exports | `CaptureExport`, Markdown renderer | runtime recovery actions | [L7](07-domain-modeling-and-policies.md) | Tests: CaptureExportTests |
| [`Sources/NotionPiP/Domain/CaptureSnapshot.swift`](../../Sources/NotionPiP/Domain/CaptureSnapshot.swift) | Defines draft/record snapshots and canonical JSON | `DraftMutation`, capture snapshots, `CanonicalJSON` | repositories, bridge, delivery | [L7](07-domain-modeling-and-policies.md) | Tests: CaptureRepositoryTests |
| [`Sources/NotionPiP/Domain/DeliveryState.swift`](../../Sources/NotionPiP/Domain/DeliveryState.swift) | Defines durable delivery and destination states | `DeliveryState`, `CaptureDestination`, safe error | repositories and delivery services | [L10](10-notion-api-and-delivery.md) | Tests: DeliveryEngineTests |
| [`Sources/NotionPiP/Domain/DesignTokens.swift`](../../Sources/NotionPiP/Domain/DesignTokens.swift) | Centralizes visual design constants | `DesignTokens` | SwiftUI views | [L11](11-views-settings-and-state.md) | Tests: QuickCaptureDangerContrastTests |
| [`Sources/NotionPiP/Domain/ExternalURLRoute.swift`](../../Sources/NotionPiP/Domain/ExternalURLRoute.swift) | Validates external URL routes | `ExternalURLRoute` and errors | AppDelegate and runtime | [L7](07-domain-modeling-and-policies.md) | Tests: ExternalURLRouteTests |
| [`Sources/NotionPiP/Domain/HistoryAssembler.swift`](../../Sources/NotionPiP/Domain/HistoryAssembler.swift) | Builds deduplicated history sections | `HistoryAssembler` and history values | history consumers | [L7](07-domain-modeling-and-policies.md) | Tests: HistoryAssemblerTests |
| [`Sources/NotionPiP/Domain/JSONValue.swift`](../../Sources/NotionPiP/Domain/JSONValue.swift) | Models Codable JSON values | `JSONValue` | capture and bridge values | [L7](07-domain-modeling-and-policies.md) | Tests: CaptureBridgeProtocolTests |
| [`Sources/NotionPiP/Domain/NotionPageReference.swift`](../../Sources/NotionPiP/Domain/NotionPageReference.swift) | Validates canonical Notion page identity | `NotionPageReference` | activation, persistence, navigation | [L7](07-domain-modeling-and-policies.md) | Tests: NotionPageReferenceTests |
| [`Sources/NotionPiP/Domain/PageSwitcherMatcher.swift`](../../Sources/NotionPiP/Domain/PageSwitcherMatcher.swift) | Ranks and groups switcher pages | switcher item/section/matcher | PageSwitcherController | [L7](07-domain-modeling-and-policies.md) | Tests: PageSwitcherMatcherTests |
| [`Sources/NotionPiP/Domain/PageWorkingSetPolicy.swift`](../../Sources/NotionPiP/Domain/PageWorkingSetPolicy.swift) | Computes bounded page-working-set mutations | `PageWorkingSetPolicy`, mutation | PageRepository and in-memory store | [L7](07-domain-modeling-and-policies.md) | Tests: PageWorkingSetPolicyTests |
| [`Sources/NotionPiP/Domain/PageWorkingSetSnapshot.swift`](../../Sources/NotionPiP/Domain/PageWorkingSetSnapshot.swift) | Defines working-set and restoration snapshots | `PageWorkingSetSnapshot`, restoration, errors | runtime and repositories | [L7](07-domain-modeling-and-policies.md) | Tests: PageRepositoryTests |
| [`Sources/NotionPiP/Domain/PanelSizePreferences.swift`](../../Sources/NotionPiP/Domain/PanelSizePreferences.swift) | Defines validated built-in/custom sizes | panel size values, presets, preferences | size controller and store | [L7](07-domain-modeling-and-policies.md) | Tests: PanelSizePreferencesTests |
| [`Sources/NotionPiP/Domain/PersonalIntegrationToken.swift`](../../Sources/NotionPiP/Domain/PersonalIntegrationToken.swift) | Validates personal integration tokens | `PersonalIntegrationToken` | credential vault and connection | [L7](07-domain-modeling-and-policies.md) | Tests: PersonalIntegrationTokenTests |
| [`Sources/NotionPiP/Domain/QuickCaptureDestination.swift`](../../Sources/NotionPiP/Domain/QuickCaptureDestination.swift) | Models saved Quick Capture destination | `QuickCaptureDestination` | destination controller/repository | [L10](10-notion-api-and-delivery.md) | Tests: QuickCaptureDestinationRepositoryTests |
| [`Sources/NotionPiP/Domain/RetryPolicy.swift`](../../Sources/NotionPiP/Domain/RetryPolicy.swift) | Defines retry, retention, and clock policy | `RetryPolicy`, `RetentionPolicy`, `CaptureClock` | delivery engine/repository | [L10](10-notion-api-and-delivery.md) | Tests: DeliveryEngineTests |

## Swift — Persistence

| Path | Role | Types / artifacts | Consumer | Lecture | Evidence |
|---|---|---|---|---|---|
| [`Sources/NotionPiP/Persistence/ActivePageModel.swift`](../../Sources/NotionPiP/Persistence/ActivePageModel.swift) | Stores the active page row | SwiftData `ActivePageModel` | PageRepository | [L8](08-persistence-and-restoration.md) | Tests: PageRepositoryTests |
| [`Sources/NotionPiP/Persistence/CaptureDraftModel.swift`](../../Sources/NotionPiP/Persistence/CaptureDraftModel.swift) | Stores mutable local capture drafts | SwiftData `CaptureDraftModel` | CaptureRepository | [L8](08-persistence-and-restoration.md) | Tests: CaptureRepositoryTests |
| [`Sources/NotionPiP/Persistence/CaptureRecordModel.swift`](../../Sources/NotionPiP/Persistence/CaptureRecordModel.swift) | Stores durable outbox/delivery records | SwiftData `CaptureRecordModel` | CaptureRepository | [L8](08-persistence-and-restoration.md) | Tests: CaptureRepositoryTests |
| [`Sources/NotionPiP/Persistence/CaptureRepository.swift`](../../Sources/NotionPiP/Persistence/CaptureRepository.swift) | Commits capture revisions, claims, and journals | model actor `CaptureRepository` | editor lifecycle and delivery | [L8](08-persistence-and-restoration.md) | Tests: CaptureRepositoryTests |
| [`Sources/NotionPiP/Persistence/NotionPiPPersistence.swift`](../../Sources/NotionPiP/Persistence/NotionPiPPersistence.swift) | Creates the shared SwiftData container | `NotionPiPPersistence` | composition and tests | [L8](08-persistence-and-restoration.md) | Tests: SchemaMigrationTests |
| [`Sources/NotionPiP/Persistence/NotionPiPSchema.swift`](../../Sources/NotionPiP/Persistence/NotionPiPSchema.swift) | Versions schemas and migrations | V1–V3 schemas, migration plan | container construction | [L8](08-persistence-and-restoration.md) | Tests: SchemaMigrationTests |
| [`Sources/NotionPiP/Persistence/PageRepository.swift`](../../Sources/NotionPiP/Persistence/PageRepository.swift) | Commits active/pinned/recent/restoration state | model actor `PageRepository`, stored snapshot | runtime and switcher | [L8](08-persistence-and-restoration.md) | Tests: PageRepositoryTests |
| [`Sources/NotionPiP/Persistence/PageRestorationModel.swift`](../../Sources/NotionPiP/Persistence/PageRestorationModel.swift) | Stores durable browser restoration data | SwiftData `PageRestorationModel` | PageRepository | [L8](08-persistence-and-restoration.md) | Tests: PageRepositoryTests |
| [`Sources/NotionPiP/Persistence/PageWorkingSetStore.swift`](../../Sources/NotionPiP/Persistence/PageWorkingSetStore.swift) | Defines working-set port and in-memory actor | `PageWorkingSetPersisting`, in-memory store | switcher/runtime/tests | [L8](08-persistence-and-restoration.md) | Tests: PageWorkingSetPolicyTests |
| [`Sources/NotionPiP/Persistence/PanelSizePreferencesStore.swift`](../../Sources/NotionPiP/Persistence/PanelSizePreferencesStore.swift) | Persists panel sizes in UserDefaults | `PanelSizePreferencesPersisting`, store | PanelSizeController | [L8](08-persistence-and-restoration.md) | Tests: PanelSizePreferencesStoreTests |
| [`Sources/NotionPiP/Persistence/PinnedPageModel.swift`](../../Sources/NotionPiP/Persistence/PinnedPageModel.swift) | Stores pinned-page order | SwiftData `PinnedPageModel` | PageRepository | [L8](08-persistence-and-restoration.md) | Tests: PageRepositoryTests |
| [`Sources/NotionPiP/Persistence/QuickCaptureDestinationRepository.swift`](../../Sources/NotionPiP/Persistence/QuickCaptureDestinationRepository.swift) | Persists the selected delivery destination | destination port and model actor | destination controller | [L8](08-persistence-and-restoration.md) | Tests: QuickCaptureDestinationRepositoryTests |
| [`Sources/NotionPiP/Persistence/QuickCaptureSettingsModel.swift`](../../Sources/NotionPiP/Persistence/QuickCaptureSettingsModel.swift) | Stores Quick Capture settings | SwiftData `QuickCaptureSettingsModel` | destination repository | [L8](08-persistence-and-restoration.md) | Tests: QuickCaptureDestinationRepositoryTests |
| [`Sources/NotionPiP/Persistence/RecentPageModel.swift`](../../Sources/NotionPiP/Persistence/RecentPageModel.swift) | Stores recent-page order and timestamp | SwiftData `RecentPageModel` | PageRepository | [L8](08-persistence-and-restoration.md) | Tests: PageRepositoryTests |

## Swift — Services

| Path | Role | Types / artifacts | Consumer | Lecture | Evidence |
|---|---|---|---|---|---|
| [`Sources/NotionPiP/Services/CapturePersistencePorts.swift`](../../Sources/NotionPiP/Services/CapturePersistencePorts.swift) | Defines capture persistence/scheduling ports | finalize, delivery, scheduling, journal protocols | lifecycle, engine, scheduler | [L10](10-notion-api-and-delivery.md) | Tests: DeliveryEngineTests |
| [`Sources/NotionPiP/Services/DeliveryEngine.swift`](../../Sources/NotionPiP/Services/DeliveryEngine.swift) | Claims and delivers queued captures | `DeliveryEngine`, transport, receipts | scheduler and runtime | [L10](10-notion-api-and-delivery.md) | Tests: DeliveryEngineTests |
| [`Sources/NotionPiP/Services/DeliveryScheduler.swift`](../../Sources/NotionPiP/Services/DeliveryScheduler.swift) | Coalesces delivery triggers and health | `DeliveryScheduler`, health snapshot | runtime and connection flow | [L10](10-notion-api-and-delivery.md) | Tests: DeliverySchedulerTests |
| [`Sources/NotionPiP/Services/NotionAPIClient.swift`](../../Sources/NotionPiP/Services/NotionAPIClient.swift) | Implements bounded Notion HTTP operations | workspace/capture protocols, client, DTOs | connection, search, delivery | [L10](10-notion-api-and-delivery.md) | Tests: NotionAPIClientTests |
| [`Sources/NotionPiP/Services/NotionBlockConverter.swift`](../../Sources/NotionPiP/Services/NotionBlockConverter.swift) | Converts ProseMirror JSON to Notion blocks | `NotionBlockConverter`, conversion result | delivery service | [L10](10-notion-api-and-delivery.md) | Tests: NotionBlockConverterTests |
| [`Sources/NotionPiP/Services/NotionCaptureDeliveryService.swift`](../../Sources/NotionPiP/Services/NotionCaptureDeliveryService.swift) | Journals create/append delivery progress | actor delivery service and journal | DeliveryEngine | [L10](10-notion-api-and-delivery.md) | Tests: NotionCaptureDeliveryServiceTests |
| [`Sources/NotionPiP/Services/PersonalTokenNotionCaptureAPI.swift`](../../Sources/NotionPiP/Services/PersonalTokenNotionCaptureAPI.swift) | Provides token-scoped capture API access | actor API adapter | delivery service | [L10](10-notion-api-and-delivery.md) | Tests: PersonalTokenConnectionTests |
| [`Sources/NotionPiP/Services/QuickCaptureLifecycleCoordinator.swift`](../../Sources/NotionPiP/Services/QuickCaptureLifecycleCoordinator.swift) | Finalizes close into discard or outbox | lifecycle actor, close outcome, document content | capture window close path | [L10](10-notion-api-and-delivery.md) | Tests: QuickCaptureLifecycleTests |

## Swift — Platform

| Path | Role | Types / artifacts | Consumer | Lecture | Evidence |
|---|---|---|---|---|---|
| [`Sources/NotionPiP/Platform/AppKitCommandMenuFactory.swift`](../../Sources/NotionPiP/Platform/AppKitCommandMenuFactory.swift) | Projects shared commands into AppKit menus | `AppKitCommandMenuFactory` | main/status menus | [L11](11-views-settings-and-state.md) | Tests: AppCommandTests |
| [`Sources/NotionPiP/Platform/AppMainMenuFactory.swift`](../../Sources/NotionPiP/Platform/AppMainMenuFactory.swift) | Builds the process main menu | `AppMainMenuFactory` | NotionPiPApp | [L3](03-application-lifecycle.md) | Tests: AppMainMenuTests |
| [`Sources/NotionPiP/Platform/AppWindowFactory.swift`](../../Sources/NotionPiP/Platform/AppWindowFactory.swift) | Constructs Settings and Quick Capture windows | `AppWindowFactory` | composition/runtime | [L11](11-views-settings-and-state.md) | Manual factory assembly; presenter behavior: AppWindowPresenterTests |
| [`Sources/NotionPiP/Platform/AppWindowPresenter.swift`](../../Sources/NotionPiP/Platform/AppWindowPresenter.swift) | Retains lazy app windows and termination work | window protocols and presenters | runtime and AppDelegate | [L3](03-application-lifecycle.md) | Tests: AppWindowPresenterTests |
| [`Sources/NotionPiP/Platform/CaptureBridgeProtocol.swift`](../../Sources/NotionPiP/Platform/CaptureBridgeProtocol.swift) | Validates and encodes native editor envelopes | bridge request/reply/context/error types | CaptureEditorSession and web editor | [L9](09-quick-capture-editor-bridge.md) | Tests: CaptureBridgeProtocolTests |
| [`Sources/NotionPiP/Platform/CaptureEditorSession.swift`](../../Sources/NotionPiP/Platform/CaptureEditorSession.swift) | Owns local editor WebView lifecycle and dispatch | `CaptureEditorSession`, resources, navigation policy | QuickCaptureView/window | [L9](09-quick-capture-editor-bridge.md) | Tests: CaptureEditorFlowTests |
| [`Sources/NotionPiP/Platform/ExternalDropActivatingWebView.swift`](../../Sources/NotionPiP/Platform/ExternalDropActivatingWebView.swift) | Routes external text drops through activation | drop value, activation helper, WKWebView subclass | live Notion session | [L6](06-webkit-notion-session.md) | Tests: ExternalDropActivatingWebViewTests |
| [`Sources/NotionPiP/Platform/GlobalShortcut.swift`](../../Sources/NotionPiP/Platform/GlobalShortcut.swift) | Stores shortcut and trusted-capture preferences | shortcut value and defaults stores | runtime/settings | [L5](05-panel-stashing-and-controls.md) | Tests: GlobalShortcutTests |
| [`Sources/NotionPiP/Platform/GlobalShortcutRegistrar.swift`](../../Sources/NotionPiP/Platform/GlobalShortcutRegistrar.swift) | Registers Carbon global shortcuts | registrar/engine protocols and Carbon adapters | runtime | [L5](05-panel-stashing-and-controls.md) | Tests: GlobalShortcutTests |
| [`Sources/NotionPiP/Platform/MenuBarIconPreferenceStore.swift`](../../Sources/NotionPiP/Platform/MenuBarIconPreferenceStore.swift) | Stores menu-bar icon visibility | `MenuBarIconPreferenceStore` | runtime/status item | [L11](11-views-settings-and-state.md) | Tests: MenuBarIconPreferenceStoreTests |
| [`Sources/NotionPiP/Platform/NotionEditorSelection.swift`](../../Sources/NotionPiP/Platform/NotionEditorSelection.swift) | Decodes saved live-editor selections | selection snapshot and evaluation | NotionWebSession | [L6](06-webkit-notion-session.md) | Tests: NotionEditorSelectionTests |
| [`Sources/NotionPiP/Platform/NotionWebLifecycleController.swift`](../../Sources/NotionPiP/Platform/NotionWebLifecycleController.swift) | Suspends/rebuilds the live Notion WebView | `NotionWebLifecycleController` | NotionWebSession and panel | [L6](06-webkit-notion-session.md) | Tests: NotionWebLifecycleControllerTests |
| [`Sources/NotionPiP/Platform/NotionWebSession.swift`](../../Sources/NotionPiP/Platform/NotionWebSession.swift) | Owns one live Notion browser session | session state, bridges, loading protocol | panel/runtime | [L6](06-webkit-notion-session.md) | Tests: NotionWebSessionTests |
| [`Sources/NotionPiP/Platform/NotionWebView.swift`](../../Sources/NotionPiP/Platform/NotionWebView.swift) | Hosts the live WKWebView in SwiftUI | `NotionWebView` representable | PiPChromeView | [L6](06-webkit-notion-session.md) | Tests: NotionWebSessionTests |
| [`Sources/NotionPiP/Platform/PageURLInputPresenter.swift`](../../Sources/NotionPiP/Platform/PageURLInputPresenter.swift) | Owns URL-input window presentation | presenter protocols/factory | runtime | [L4](04-composition-and-runtime.md) | Tests: PageURLInputPresenterTests |
| [`Sources/NotionPiP/Platform/PanelFramePolicy.swift`](../../Sources/NotionPiP/Platform/PanelFramePolicy.swift) | Computes panel frames across screens | screen/anchor/placement values and policy | PiPPanelCoordinator | [L5](05-panel-stashing-and-controls.md) | Tests: PanelFramePolicyTests |
| [`Sources/NotionPiP/Platform/PanelStashPolicy.swift`](../../Sources/NotionPiP/Platform/PanelStashPolicy.swift) | Computes edge stash placement | stash side/placement/policy | panel and handle coordinators | [L5](05-panel-stashing-and-controls.md) | Tests: PanelStashPolicyTests |
| [`Sources/NotionPiP/Platform/PasteboardReading.swift`](../../Sources/NotionPiP/Platform/PasteboardReading.swift) | Adapts the system pasteboard | pasteboard protocol/system reader | capture shortcut runtime | [L4](04-composition-and-runtime.md) | Tests: ClipboardPinTests |
| [`Sources/NotionPiP/Platform/PerformanceSignposter.swift`](../../Sources/NotionPiP/Platform/PerformanceSignposter.swift) | Records first-only performance intervals | operation/outcome/token/signposter | startup and presenters | [L12](12-testing-debugging-and-change-workflow.md) | Tests: PerformanceSignposterTests |
| [`Sources/NotionPiP/Platform/PersonalTokenCredentialVault.swift`](../../Sources/NotionPiP/Platform/PersonalTokenCredentialVault.swift) | Stores optional tokens in Keychain | secret store protocol, Keychain adapter, vault | connection controller | [L10](10-notion-api-and-delivery.md) | Tests: PersonalTokenCredentialVaultTests |
| [`Sources/NotionPiP/Platform/PiPPanelCoordinator.swift`](../../Sources/NotionPiP/Platform/PiPPanelCoordinator.swift) | Owns PiP panel presentation and stash state | panel/handle protocols, coordinator, NSPanel | PinCoordinator and size controller | [L5](05-panel-stashing-and-controls.md) | Tests: PiPPanelGeometryTests |
| [`Sources/NotionPiP/Platform/PiPStashHandleController.swift`](../../Sources/NotionPiP/Platform/PiPStashHandleController.swift) | Owns the retained edge-handle panel | `PiPStashHandleController` | PiPPanelCoordinator | [L5](05-panel-stashing-and-controls.md) | Tests: PiPStashHandleInteractionTests |
| [`Sources/NotionPiP/Platform/SettingsWindowPresenter.swift`](../../Sources/NotionPiP/Platform/SettingsWindowPresenter.swift) | Presents and focuses Settings | settings presenter protocol/adapter | runtime and status menu | [L11](11-views-settings-and-state.md) | Tests: AppWindowPresenterTests |
| [`Sources/NotionPiP/Platform/StatusItemController.swift`](../../Sources/NotionPiP/Platform/StatusItemController.swift) | Owns the menu-bar item and context menu | status commands and controller | composition/runtime | [L11](11-views-settings-and-state.md) | Tests: RuntimeActivationAndMenuBarTests |
| [`Sources/NotionPiP/Platform/StatusItemEventRouter.swift`](../../Sources/NotionPiP/Platform/StatusItemEventRouter.swift) | Maps status-item mouse events | `StatusItemEventRouter` | StatusItemController | [L11](11-views-settings-and-state.md) | Tests: RuntimeActivationAndMenuBarTests |
| [`Sources/NotionPiP/Platform/WeakScriptMessageHandler.swift`](../../Sources/NotionPiP/Platform/WeakScriptMessageHandler.swift) | Weakly forwards WKScriptMessage replies | handler protocol and weak adapter | CaptureEditorSession | [L9](09-quick-capture-editor-bridge.md) | Tests: CaptureEditorFlowTests |
| [`Sources/NotionPiP/Platform/WebNavigationDestination.swift`](../../Sources/NotionPiP/Platform/WebNavigationDestination.swift) | Classifies internal/external navigation | `WebNavigationDestination` | NotionWebSession | [L6](06-webkit-notion-session.md) | Tests: WebNavigationDestinationTests |
| [`Sources/NotionPiP/Platform/WindowRolePolicy.swift`](../../Sources/NotionPiP/Platform/WindowRolePolicy.swift) | Defines window role and AppKit behavior | `WindowRole`, `WindowRolePolicy` | window factories/coordinators | [L5](05-panel-stashing-and-controls.md) | Tests: WindowRolePolicyTests |

## Swift — Views

| Path | Role | Types / artifacts | Consumer | Lecture | Evidence |
|---|---|---|---|---|---|
| [`Sources/NotionPiP/Views/CaptureOutboxStatusView.swift`](../../Sources/NotionPiP/Views/CaptureOutboxStatusView.swift) | Renders durable delivery history/recovery | delivery presentation and outbox view | SettingsView | [L11](11-views-settings-and-state.md) | Tests: NotionCaptureDeliveryServiceTests |
| [`Sources/NotionPiP/Views/CaptureStatusView.swift`](../../Sources/NotionPiP/Views/CaptureStatusView.swift) | Renders compact capture delivery status | `CaptureStatusView` | No committed production constructor | [L11](11-views-settings-and-state.md) | Manual |
| [`Sources/NotionPiP/Views/ConflictRecoveryView.swift`](../../Sources/NotionPiP/Views/ConflictRecoveryView.swift) | Renders stale-revision recovery actions | `ConflictRecoveryView` | QuickCaptureView | [L11](11-views-settings-and-state.md) | Tests: CaptureWebViewConflictTests |
| [`Sources/NotionPiP/Views/DeveloperStatusView.swift`](../../Sources/NotionPiP/Views/DeveloperStatusView.swift) | Shows point-in-time process metrics | `DeveloperStatusView`, process metrics | SettingsView | [L11](11-views-settings-and-state.md) | Manual |
| [`Sources/NotionPiP/Views/GlobalShortcutRecorderView.swift`](../../Sources/NotionPiP/Views/GlobalShortcutRecorderView.swift) | Captures and displays both shortcuts | recorder views and AppKit capture view | SettingsView | [L11](11-views-settings-and-state.md) | Tests: GlobalShortcutTests |
| [`Sources/NotionPiP/Views/NotionWorkspaceSearchView.swift`](../../Sources/NotionPiP/Views/NotionWorkspaceSearchView.swift) | Searches workspace pages for the Settings Pinned Page section | `NotionWorkspaceSearchView` | SettingsView | [L11](11-views-settings-and-state.md) | Tests: AppRuntimeFacadeTests |
| [`Sources/NotionPiP/Views/PagePickerView.swift`](../../Sources/NotionPiP/Views/PagePickerView.swift) | Renders generic page choices | `PagePickerDisplay`, `PagePickerView` | No committed production constructor | [L11](11-views-settings-and-state.md) | Tests: PinCoordinatorTests |
| [`Sources/NotionPiP/Views/PageSwitcherView.swift`](../../Sources/NotionPiP/Views/PageSwitcherView.swift) | Renders searchable page switching | switcher view and rows | PiPChromeView | [L11](11-views-settings-and-state.md) | Tests: PageSwitcherMatcherTests |
| [`Sources/NotionPiP/Views/PageURLField.swift`](../../Sources/NotionPiP/Views/PageURLField.swift) | Renders reusable Notion URL entry | `PageURLField` | PageURLInputView | [L11](11-views-settings-and-state.md) | Tests: PageURLInputPresenterTests |
| [`Sources/NotionPiP/Views/PageURLInputView.swift`](../../Sources/NotionPiP/Views/PageURLInputView.swift) | Renders URL entry, validation, and focus | `PageURLInputView`, `PageURLInputWindowContent` | SettingsView and PageURLInputWindowContent | [L11](11-views-settings-and-state.md) | Tests: PageURLInputPresenterTests |
| [`Sources/NotionPiP/Views/PanelSizeMenu.swift`](../../Sources/NotionPiP/Views/PanelSizeMenu.swift) | Renders panel-size menu choices | `PanelSizeMenu` | PiPAppCommandMenu | [L11](11-views-settings-and-state.md) | Tests: PanelSizeControllerTests |
| [`Sources/NotionPiP/Views/PanelSizeSettingsView.swift`](../../Sources/NotionPiP/Views/PanelSizeSettingsView.swift) | Renders built-in/custom size settings | settings view and custom rows | SettingsView | [L11](11-views-settings-and-state.md) | Tests: PanelSizePreferencesTests |
| [`Sources/NotionPiP/Views/PiPAppCommandMenu.swift`](../../Sources/NotionPiP/Views/PiPAppCommandMenu.swift) | Projects app commands in SwiftUI | `PiPAppCommandMenu` | PiPChromeView | [L11](11-views-settings-and-state.md) | Tests: AppCommandTests |
| [`Sources/NotionPiP/Views/PiPChromeView.swift`](../../Sources/NotionPiP/Views/PiPChromeView.swift) | Composes the visible PiP chrome | `PiPChromeView`, toolbar mark | PiPPanelCoordinator | [L11](11-views-settings-and-state.md) | Tests: PiPChromeViewTests |
| [`Sources/NotionPiP/Views/PiPStashHandleView.swift`](../../Sources/NotionPiP/Views/PiPStashHandleView.swift) | Renders and tracks edge-handle interaction | stash handle view/NSView/shape | PiPStashHandleController | [L11](11-views-settings-and-state.md) | Tests: PiPStashHandleInteractionTests |
| [`Sources/NotionPiP/Views/QuickCaptureDestinationSettingsView.swift`](../../Sources/NotionPiP/Views/QuickCaptureDestinationSettingsView.swift) | Renders destination mode/search controls | destination settings view | SettingsView | [L11](11-views-settings-and-state.md) | Tests: QuickCaptureDestinationControllerTests |
| [`Sources/NotionPiP/Views/QuickCaptureView.swift`](../../Sources/NotionPiP/Views/QuickCaptureView.swift) | Hosts the local editor and conflict UI | capture view, launch action, WebView representable | AppWindowFactory | [L11](11-views-settings-and-state.md) | Tests: CaptureWebViewFocusTests |
| [`Sources/NotionPiP/Views/ServiceHealthView.swift`](../../Sources/NotionPiP/Views/ServiceHealthView.swift) | Renders degraded-service issues/actions | `ServiceHealthView` | SettingsView | [L11](11-views-settings-and-state.md) | Tests: AppRuntimeFacadeTests |
| [`Sources/NotionPiP/Views/SettingsView.swift`](../../Sources/NotionPiP/Views/SettingsView.swift) | Composes all settings groups | `SettingsView` | AppWindowFactory | [L11](11-views-settings-and-state.md) | Tests: RuntimeActivationAndMenuBarTests |
| [`Sources/NotionPiP/Views/TopControlsHoverController.swift`](../../Sources/NotionPiP/Views/TopControlsHoverController.swift) | Owns delayed reveal/dismiss intent | `TopControlsHoverController` | PiPChromeView | [L11](11-views-settings-and-state.md) | Tests: PiPChromeViewTests |

## Packaged resources

| Path | Role | Types / artifacts | Consumer | Lecture | Evidence |
|---|---|---|---|---|---|
| [`Sources/NotionPiP/Resources/QuickCapture/composer.css`](../../Sources/NotionPiP/Resources/QuickCapture/composer.css) | Styles the local editor | CSS resource | index.html/editor UI | [L9](09-quick-capture-editor-bridge.md) | Tests: QuickCaptureDangerContrastTests; manual rendering |
| [`Sources/NotionPiP/Resources/QuickCapture/editor.js`](../../Sources/NotionPiP/Resources/QuickCapture/editor.js) | Runs the bundled local editor | checked-in generated JavaScript | CaptureEditorSession WKWebView | [L9](09-quick-capture-editor-bridge.md) | Generated |
| [`Sources/NotionPiP/Resources/QuickCapture/index.html`](../../Sources/NotionPiP/Resources/QuickCapture/index.html) | Defines local editor markup and CSP | HTML resource | CaptureEditorSession WKWebView | [L9](09-quick-capture-editor-bridge.md) | Tests: CaptureEditorResourceTests |

## Swift tests and support

| Path | Role | Types / artifacts | Consumer | Lecture | Evidence |
|---|---|---|---|---|---|
| [`Tests/NotionPiPTests/AppCommandActionRelayTests.swift`](../../Tests/NotionPiPTests/AppCommandActionRelayTests.swift) | Tests App Command Action Relay | XCTestCase | SwiftPM test target | [L4](04-composition-and-runtime.md) | Test |
| [`Tests/NotionPiPTests/AppCommandTests.swift`](../../Tests/NotionPiPTests/AppCommandTests.swift) | Tests App Command | XCTestCase | SwiftPM test target | [L11](11-views-settings-and-state.md) | Test |
| [`Tests/NotionPiPTests/AppMainMenuTests.swift`](../../Tests/NotionPiPTests/AppMainMenuTests.swift) | Tests App Main Menu | XCTestCase | SwiftPM test target | [L3](03-application-lifecycle.md) | Test |
| [`Tests/NotionPiPTests/AppRuntimeFacadeTests.swift`](../../Tests/NotionPiPTests/AppRuntimeFacadeTests.swift) | Tests App Runtime Facade | XCTestCase | SwiftPM test target | [L4](04-composition-and-runtime.md) | Test |
| [`Tests/NotionPiPTests/AppRuntimeTestSupport.swift`](../../Tests/NotionPiPTests/AppRuntimeTestSupport.swift) | Provides App Runtime Test Support fixtures | XCTest helpers/fakes | SwiftPM test target | [L4](04-composition-and-runtime.md) | Test support |
| [`Tests/NotionPiPTests/AppWindowPresenterTests.swift`](../../Tests/NotionPiPTests/AppWindowPresenterTests.swift) | Tests App Window Presenter | XCTestCase | SwiftPM test target | [L4](04-composition-and-runtime.md) | Test |
| [`Tests/NotionPiPTests/CaptureBridgeProtocolTests.swift`](../../Tests/NotionPiPTests/CaptureBridgeProtocolTests.swift) | Tests Capture Bridge Protocol | XCTestCase | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Tests/NotionPiPTests/CaptureEditorFlowTests.swift`](../../Tests/NotionPiPTests/CaptureEditorFlowTests.swift) | Tests Capture Editor Flow | XCTestCase | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Tests/NotionPiPTests/CaptureEditorResourceTests.swift`](../../Tests/NotionPiPTests/CaptureEditorResourceTests.swift) | Tests Capture Editor Resource | XCTestCase | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Tests/NotionPiPTests/CaptureExportTests.swift`](../../Tests/NotionPiPTests/CaptureExportTests.swift) | Tests Capture Export | XCTestCase | SwiftPM test target | [L7](07-domain-modeling-and-policies.md) | Test |
| [`Tests/NotionPiPTests/CaptureRepositoryTests.swift`](../../Tests/NotionPiPTests/CaptureRepositoryTests.swift) | Tests Capture Repository | XCTestCase | SwiftPM test target | [L8](08-persistence-and-restoration.md) | Test |
| [`Tests/NotionPiPTests/CaptureWebViewAutosaveTests.swift`](../../Tests/NotionPiPTests/CaptureWebViewAutosaveTests.swift) | Tests Capture Web View Autosave | XCTestCase | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Tests/NotionPiPTests/CaptureWebViewConflictTests.swift`](../../Tests/NotionPiPTests/CaptureWebViewConflictTests.swift) | Tests Capture Web View Conflict | XCTestCase | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Tests/NotionPiPTests/CaptureWebViewFocusTests.swift`](../../Tests/NotionPiPTests/CaptureWebViewFocusTests.swift) | Tests Capture Web View Focus | XCTestCase | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Tests/NotionPiPTests/CaptureWebViewFormattingTestSupport.swift`](../../Tests/NotionPiPTests/CaptureWebViewFormattingTestSupport.swift) | Provides Capture Web View Formatting Test Support fixtures | XCTest helpers/fakes | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test support |
| [`Tests/NotionPiPTests/CaptureWebViewLifecycleTests.swift`](../../Tests/NotionPiPTests/CaptureWebViewLifecycleTests.swift) | Tests Capture Web View Lifecycle | XCTestCase | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Tests/NotionPiPTests/CaptureWebViewNavigationTests.swift`](../../Tests/NotionPiPTests/CaptureWebViewNavigationTests.swift) | Tests Capture Web View Navigation | XCTestCase | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Tests/NotionPiPTests/CaptureWebViewPersistenceTestSupport.swift`](../../Tests/NotionPiPTests/CaptureWebViewPersistenceTestSupport.swift) | Provides Capture Web View Persistence Test Support fixtures | XCTest helpers/fakes | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test support |
| [`Tests/NotionPiPTests/CaptureWebViewRecoveryTests.swift`](../../Tests/NotionPiPTests/CaptureWebViewRecoveryTests.swift) | Tests Capture Web View Recovery | XCTestCase | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Tests/NotionPiPTests/CaptureWebViewRichTextTests.swift`](../../Tests/NotionPiPTests/CaptureWebViewRichTextTests.swift) | Tests Capture Web View Rich Text | XCTestCase | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Tests/NotionPiPTests/CaptureWebViewSlashMenuTestSupport.swift`](../../Tests/NotionPiPTests/CaptureWebViewSlashMenuTestSupport.swift) | Provides Capture Web View Slash Menu Test Support fixtures | XCTest helpers/fakes | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test support |
| [`Tests/NotionPiPTests/CaptureWebViewSlashMenuTests.swift`](../../Tests/NotionPiPTests/CaptureWebViewSlashMenuTests.swift) | Tests Capture Web View Slash Menu | XCTestCase | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Tests/NotionPiPTests/CaptureWebViewTestSupport.swift`](../../Tests/NotionPiPTests/CaptureWebViewTestSupport.swift) | Provides Capture Web View Test Support fixtures | XCTest helpers/fakes | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test support |
| [`Tests/NotionPiPTests/CaptureWebViewToolbarTests.swift`](../../Tests/NotionPiPTests/CaptureWebViewToolbarTests.swift) | Tests Capture Web View Toolbar | XCTestCase | SwiftPM test target | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Tests/NotionPiPTests/ClipboardPinTests.swift`](../../Tests/NotionPiPTests/ClipboardPinTests.swift) | Tests Clipboard Pin | XCTestCase | SwiftPM test target | [L5](05-panel-stashing-and-controls.md) | Test |
| [`Tests/NotionPiPTests/DeliveryEngineTests.swift`](../../Tests/NotionPiPTests/DeliveryEngineTests.swift) | Tests Delivery Engine | XCTestCase | SwiftPM test target | [L10](10-notion-api-and-delivery.md) | Test |
| [`Tests/NotionPiPTests/DeliverySchedulerTests.swift`](../../Tests/NotionPiPTests/DeliverySchedulerTests.swift) | Tests Delivery Scheduler | XCTestCase | SwiftPM test target | [L10](10-notion-api-and-delivery.md) | Test |
| [`Tests/NotionPiPTests/ExternalDropActivatingWebViewTests.swift`](../../Tests/NotionPiPTests/ExternalDropActivatingWebViewTests.swift) | Tests External Drop Activating Web View | XCTestCase | SwiftPM test target | [L6](06-webkit-notion-session.md) | Test |
| [`Tests/NotionPiPTests/ExternalURLRouteTests.swift`](../../Tests/NotionPiPTests/ExternalURLRouteTests.swift) | Tests External URLRoute | XCTestCase | SwiftPM test target | [L7](07-domain-modeling-and-policies.md) | Test |
| [`Tests/NotionPiPTests/GlobalShortcutTests.swift`](../../Tests/NotionPiPTests/GlobalShortcutTests.swift) | Tests Global Shortcut | XCTestCase | SwiftPM test target | [L5](05-panel-stashing-and-controls.md) | Test |
| [`Tests/NotionPiPTests/HistoryAssemblerTests.swift`](../../Tests/NotionPiPTests/HistoryAssemblerTests.swift) | Tests History Assembler | XCTestCase | SwiftPM test target | [L7](07-domain-modeling-and-policies.md) | Test |
| [`Tests/NotionPiPTests/MenuBarIconPreferenceStoreTests.swift`](../../Tests/NotionPiPTests/MenuBarIconPreferenceStoreTests.swift) | Tests Menu Bar Icon Preference Store | XCTestCase | SwiftPM test target | [L11](11-views-settings-and-state.md) | Test |
| [`Tests/NotionPiPTests/NotionAPIClientTests.swift`](../../Tests/NotionPiPTests/NotionAPIClientTests.swift) | Tests Notion APIClient | XCTestCase | SwiftPM test target | [L10](10-notion-api-and-delivery.md) | Test |
| [`Tests/NotionPiPTests/NotionBlockConverterTests.swift`](../../Tests/NotionPiPTests/NotionBlockConverterTests.swift) | Tests Notion Block Converter | XCTestCase | SwiftPM test target | [L10](10-notion-api-and-delivery.md) | Test |
| [`Tests/NotionPiPTests/NotionCaptureDeliveryServiceTests.swift`](../../Tests/NotionPiPTests/NotionCaptureDeliveryServiceTests.swift) | Tests Notion Capture Delivery Service | XCTestCase | SwiftPM test target | [L10](10-notion-api-and-delivery.md) | Test |
| [`Tests/NotionPiPTests/NotionConnectionControllerTests.swift`](../../Tests/NotionPiPTests/NotionConnectionControllerTests.swift) | Tests Notion Connection Controller | XCTestCase | SwiftPM test target | [L10](10-notion-api-and-delivery.md) | Test |
| [`Tests/NotionPiPTests/NotionEditorSelectionTests.swift`](../../Tests/NotionPiPTests/NotionEditorSelectionTests.swift) | Tests Notion Editor Selection | XCTestCase | SwiftPM test target | [L6](06-webkit-notion-session.md) | Test |
| [`Tests/NotionPiPTests/NotionPageReferenceTests.swift`](../../Tests/NotionPiPTests/NotionPageReferenceTests.swift) | Tests Notion Page Reference | XCTestCase | SwiftPM test target | [L7](07-domain-modeling-and-policies.md) | Test |
| [`Tests/NotionPiPTests/NotionWebLifecycleControllerTests.swift`](../../Tests/NotionPiPTests/NotionWebLifecycleControllerTests.swift) | Tests Notion Web Lifecycle Controller | XCTestCase | SwiftPM test target | [L6](06-webkit-notion-session.md) | Test |
| [`Tests/NotionPiPTests/NotionWebSessionTests.swift`](../../Tests/NotionPiPTests/NotionWebSessionTests.swift) | Tests Notion Web Session | XCTestCase | SwiftPM test target | [L6](06-webkit-notion-session.md) | Test |
| [`Tests/NotionPiPTests/PageRepositoryTests.swift`](../../Tests/NotionPiPTests/PageRepositoryTests.swift) | Tests Page Repository | XCTestCase | SwiftPM test target | [L8](08-persistence-and-restoration.md) | Test |
| [`Tests/NotionPiPTests/PageSwitcherMatcherTests.swift`](../../Tests/NotionPiPTests/PageSwitcherMatcherTests.swift) | Tests Page Switcher Matcher | XCTestCase | SwiftPM test target | [L7](07-domain-modeling-and-policies.md) | Test |
| [`Tests/NotionPiPTests/PageURLInputPresenterTests.swift`](../../Tests/NotionPiPTests/PageURLInputPresenterTests.swift) | Tests Page URLInput Presenter | XCTestCase | SwiftPM test target | [L4](04-composition-and-runtime.md) | Test |
| [`Tests/NotionPiPTests/PageWorkingSetPolicyTests.swift`](../../Tests/NotionPiPTests/PageWorkingSetPolicyTests.swift) | Tests Page Working Set Policy | XCTestCase | SwiftPM test target | [L7](07-domain-modeling-and-policies.md) | Test |
| [`Tests/NotionPiPTests/PanelFramePolicyTests.swift`](../../Tests/NotionPiPTests/PanelFramePolicyTests.swift) | Tests Panel Frame Policy | XCTestCase | SwiftPM test target | [L5](05-panel-stashing-and-controls.md) | Test |
| [`Tests/NotionPiPTests/PanelSizeControllerTests.swift`](../../Tests/NotionPiPTests/PanelSizeControllerTests.swift) | Tests Panel Size Controller | XCTestCase | SwiftPM test target | [L4](04-composition-and-runtime.md) | Test |
| [`Tests/NotionPiPTests/PanelSizePreferencesStoreTests.swift`](../../Tests/NotionPiPTests/PanelSizePreferencesStoreTests.swift) | Tests Panel Size Preferences Store | XCTestCase | SwiftPM test target | [L8](08-persistence-and-restoration.md) | Test |
| [`Tests/NotionPiPTests/PanelSizePreferencesTests.swift`](../../Tests/NotionPiPTests/PanelSizePreferencesTests.swift) | Tests Panel Size Preferences | XCTestCase | SwiftPM test target | [L7](07-domain-modeling-and-policies.md) | Test |
| [`Tests/NotionPiPTests/PanelStashPolicyTests.swift`](../../Tests/NotionPiPTests/PanelStashPolicyTests.swift) | Tests Panel Stash Policy | XCTestCase | SwiftPM test target | [L5](05-panel-stashing-and-controls.md) | Test |
| [`Tests/NotionPiPTests/PerformanceSignposterTests.swift`](../../Tests/NotionPiPTests/PerformanceSignposterTests.swift) | Tests Performance Signposter | XCTestCase | SwiftPM test target | [L12](12-testing-debugging-and-change-workflow.md) | Test |
| [`Tests/NotionPiPTests/PersonalIntegrationTokenTests.swift`](../../Tests/NotionPiPTests/PersonalIntegrationTokenTests.swift) | Tests Personal Integration Token | XCTestCase | SwiftPM test target | [L7](07-domain-modeling-and-policies.md) | Test |
| [`Tests/NotionPiPTests/PersonalTokenConnectionTests.swift`](../../Tests/NotionPiPTests/PersonalTokenConnectionTests.swift) | Tests Personal Token Connection | XCTestCase | SwiftPM test target | [L10](10-notion-api-and-delivery.md) | Test |
| [`Tests/NotionPiPTests/PersonalTokenCredentialVaultTests.swift`](../../Tests/NotionPiPTests/PersonalTokenCredentialVaultTests.swift) | Tests Personal Token Credential Vault | XCTestCase | SwiftPM test target | [L10](10-notion-api-and-delivery.md) | Test |
| [`Tests/NotionPiPTests/PiPChromeViewTests.swift`](../../Tests/NotionPiPTests/PiPChromeViewTests.swift) | Tests PiP Chrome View | XCTestCase | SwiftPM test target | [L5](05-panel-stashing-and-controls.md) | Test |
| [`Tests/NotionPiPTests/PiPPanelGeometryTests.swift`](../../Tests/NotionPiPTests/PiPPanelGeometryTests.swift) | Tests PiP Panel Geometry | XCTestCase | SwiftPM test target | [L5](05-panel-stashing-and-controls.md) | Test |
| [`Tests/NotionPiPTests/PiPStashHandleInteractionTests.swift`](../../Tests/NotionPiPTests/PiPStashHandleInteractionTests.swift) | Tests PiP Stash Handle Interaction | XCTestCase | SwiftPM test target | [L5](05-panel-stashing-and-controls.md) | Test |
| [`Tests/NotionPiPTests/PinCoordinatorTests.swift`](../../Tests/NotionPiPTests/PinCoordinatorTests.swift) | Tests Pin Coordinator | XCTestCase | SwiftPM test target | [L4](04-composition-and-runtime.md) | Test |
| [`Tests/NotionPiPTests/QuickCaptureDangerContrastTests.swift`](../../Tests/NotionPiPTests/QuickCaptureDangerContrastTests.swift) | Tests Quick Capture Danger Contrast | XCTestCase | SwiftPM test target | [L11](11-views-settings-and-state.md) | Test |
| [`Tests/NotionPiPTests/QuickCaptureDestinationControllerTests.swift`](../../Tests/NotionPiPTests/QuickCaptureDestinationControllerTests.swift) | Tests Quick Capture Destination Controller | XCTestCase | SwiftPM test target | [L10](10-notion-api-and-delivery.md) | Test |
| [`Tests/NotionPiPTests/QuickCaptureDestinationRepositoryTests.swift`](../../Tests/NotionPiPTests/QuickCaptureDestinationRepositoryTests.swift) | Tests Quick Capture Destination Repository | XCTestCase | SwiftPM test target | [L8](08-persistence-and-restoration.md) | Test |
| [`Tests/NotionPiPTests/QuickCaptureLifecycleTests.swift`](../../Tests/NotionPiPTests/QuickCaptureLifecycleTests.swift) | Tests Quick Capture Lifecycle | XCTestCase | SwiftPM test target | [L10](10-notion-api-and-delivery.md) | Test |
| [`Tests/NotionPiPTests/RepositoryModelActorTests.swift`](../../Tests/NotionPiPTests/RepositoryModelActorTests.swift) | Tests Repository Model Actor | XCTestCase | SwiftPM test target | [L8](08-persistence-and-restoration.md) | Test |
| [`Tests/NotionPiPTests/RetentionPolicyTests.swift`](../../Tests/NotionPiPTests/RetentionPolicyTests.swift) | Tests Retention Policy | XCTestCase | SwiftPM test target | [L8](08-persistence-and-restoration.md) | Test |
| [`Tests/NotionPiPTests/RuntimeActivationAndMenuBarTests.swift`](../../Tests/NotionPiPTests/RuntimeActivationAndMenuBarTests.swift) | Tests Runtime Activation And Menu Bar | XCTestCase | SwiftPM test target | [L4](04-composition-and-runtime.md) | Test |
| [`Tests/NotionPiPTests/RuntimePinnedPagePersistenceTests.swift`](../../Tests/NotionPiPTests/RuntimePinnedPagePersistenceTests.swift) | Tests Runtime Pinned Page Persistence | XCTestCase | SwiftPM test target | [L8](08-persistence-and-restoration.md) | Test |
| [`Tests/NotionPiPTests/RuntimeTerminationTests.swift`](../../Tests/NotionPiPTests/RuntimeTerminationTests.swift) | Tests Runtime Termination | XCTestCase | SwiftPM test target | [L4](04-composition-and-runtime.md) | Test |
| [`Tests/NotionPiPTests/SchemaMigrationTests.swift`](../../Tests/NotionPiPTests/SchemaMigrationTests.swift) | Tests Schema Migration | XCTestCase | SwiftPM test target | [L8](08-persistence-and-restoration.md) | Test |
| [`Tests/NotionPiPTests/Task3TestSupport.swift`](../../Tests/NotionPiPTests/Task3TestSupport.swift) | Provides canonical JSON and delivery-clock fixtures | XCTest helpers/fakes | SwiftPM test target | [L10](10-notion-api-and-delivery.md) | Test support |
| [`Tests/NotionPiPTests/WebNavigationDestinationTests.swift`](../../Tests/NotionPiPTests/WebNavigationDestinationTests.swift) | Tests Web Navigation Destination | XCTestCase | SwiftPM test target | [L6](06-webkit-notion-session.md) | Test |
| [`Tests/NotionPiPTests/WindowRolePolicyTests.swift`](../../Tests/NotionPiPTests/WindowRolePolicyTests.swift) | Tests Window Role Policy | XCTestCase | SwiftPM test target | [L5](05-panel-stashing-and-controls.md) | Test |

## Web source and build

| Path | Role | Types / artifacts | Consumer | Lecture | Evidence |
|---|---|---|---|---|---|
| [`Web/QuickCaptureEditor/block-commands.ts`](../../Web/QuickCaptureEditor/block-commands.ts) | Implements editor block commands | Tiptap command helpers | editor controller | [L9](09-quick-capture-editor-bridge.md) | Tests: block-commands.test.ts |
| [`Web/QuickCaptureEditor/bridge/bridge-client.ts`](../../Web/QuickCaptureEditor/bridge/bridge-client.ts) | Correlates typed native requests/replies | bridge client | editor controller | [L9](09-quick-capture-editor-bridge.md) | Tests: protocol.test.ts |
| [`Web/QuickCaptureEditor/bridge/debounced-change-publisher.ts`](../../Web/QuickCaptureEditor/bridge/debounced-change-publisher.ts) | Serializes debounced autosaves | `DebouncedChangePublisher` | editor controller | [L9](09-quick-capture-editor-bridge.md) | Tests: autosave.test.ts |
| [`Web/QuickCaptureEditor/build.ts`](../../Web/QuickCaptureEditor/build.ts) | Bundles TypeScript into checked-in editor.js | esbuild script | npm run build:editor | [L9](09-quick-capture-editor-bridge.md) | Generated |
| [`Web/QuickCaptureEditor/controllers/formatting-toolbar-controller.ts`](../../Web/QuickCaptureEditor/controllers/formatting-toolbar-controller.ts) | Owns formatting toolbar DOM behavior | formatting toolbar controller | editor controller | [L9](09-quick-capture-editor-bridge.md) | Tests: formatting-toolbar-controller.test.ts |
| [`Web/QuickCaptureEditor/controllers/slash-menu-controller.ts`](../../Web/QuickCaptureEditor/controllers/slash-menu-controller.ts) | Owns slash-menu DOM behavior | slash menu controller | editor controller | [L9](09-quick-capture-editor-bridge.md) | Tests: slash-menu-controller.test.ts |
| [`Web/QuickCaptureEditor/editor-state.ts`](../../Web/QuickCaptureEditor/editor-state.ts) | Defines editor snapshot/state helpers | editor state values | editor controller | [L9](09-quick-capture-editor-bridge.md) | Tests: quick-capture-editor-controller.test.ts |
| [`Web/QuickCaptureEditor/editor.ts`](../../Web/QuickCaptureEditor/editor.ts) | Bootstraps the packaged editor | browser entry module | build.ts/editor bundle | [L9](09-quick-capture-editor-bridge.md) | Tests: CaptureEditorResourceTests |
| [`Web/QuickCaptureEditor/formatting.ts`](../../Web/QuickCaptureEditor/formatting.ts) | Implements marks, links, and formatting | Tiptap formatting helpers | controllers/editor | [L9](09-quick-capture-editor-bridge.md) | Tests: formatting.test.ts |
| [`Web/QuickCaptureEditor/protocol.ts`](../../Web/QuickCaptureEditor/protocol.ts) | Defines and validates bridge v1 types | request/reply types and guards | bridge client/native protocol | [L9](09-quick-capture-editor-bridge.md) | Tests: protocol.test.ts |
| [`Web/QuickCaptureEditor/quick-capture-editor-controller.ts`](../../Web/QuickCaptureEditor/quick-capture-editor-controller.ts) | Coordinates editor DOM, autosave, and transitions | `QuickCaptureEditorController` | editor.ts | [L9](09-quick-capture-editor-bridge.md) | Tests: quick-capture-editor-controller.test.ts |
| [`Web/QuickCaptureEditor/state/editor-transition-gate.ts`](../../Web/QuickCaptureEditor/state/editor-transition-gate.ts) | Serializes stash/restore/conflict transitions | `EditorTransitionGate` | editor controller | [L9](09-quick-capture-editor-bridge.md) | Tests: transition.test.ts |

## Web tests and support

| Path | Role | Types / artifacts | Consumer | Lecture | Evidence |
|---|---|---|---|---|---|
| [`Web/QuickCaptureEditor/autosave.test.ts`](../../Web/QuickCaptureEditor/autosave.test.ts) | Tests autosave.test | node:test suite | npm test | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Web/QuickCaptureEditor/block-commands.test.ts`](../../Web/QuickCaptureEditor/block-commands.test.ts) | Tests block commands.test | node:test suite | npm test | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Web/QuickCaptureEditor/controllers/formatting-toolbar-controller.test.ts`](../../Web/QuickCaptureEditor/controllers/formatting-toolbar-controller.test.ts) | Tests controllers/formatting toolbar controller.test | node:test suite | npm test | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Web/QuickCaptureEditor/controllers/slash-menu-controller.test.ts`](../../Web/QuickCaptureEditor/controllers/slash-menu-controller.test.ts) | Tests controllers/slash menu controller.test | node:test suite | npm test | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Web/QuickCaptureEditor/formatting.test.ts`](../../Web/QuickCaptureEditor/formatting.test.ts) | Tests formatting.test | node:test suite | npm test | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Web/QuickCaptureEditor/protocol.test.ts`](../../Web/QuickCaptureEditor/protocol.test.ts) | Tests protocol.test | node:test suite | npm test | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Web/QuickCaptureEditor/quick-capture-editor-controller.test.ts`](../../Web/QuickCaptureEditor/quick-capture-editor-controller.test.ts) | Tests quick capture editor controller.test | node:test suite | npm test | [L9](09-quick-capture-editor-bridge.md) | Test |
| [`Web/QuickCaptureEditor/test-support/dom.ts`](../../Web/QuickCaptureEditor/test-support/dom.ts) | Installs isolated DOM globals | happy-dom test support | DOM-facing Node tests | [L9](09-quick-capture-editor-bridge.md) | Test support |
| [`Web/QuickCaptureEditor/transition.test.ts`](../../Web/QuickCaptureEditor/transition.test.ts) | Tests transition.test | node:test suite | npm test | [L9](09-quick-capture-editor-bridge.md) | Test |

## Support and scripts

| Path | Role | Types / artifacts | Consumer | Lecture | Evidence |
|---|---|---|---|---|---|
| [`Support/NotionPiP.entitlements`](../../Support/NotionPiP.entitlements) | Declares sandbox/network capabilities | entitlements plist | build/signing script | [L12](12-testing-debugging-and-change-workflow.md) | Reference |
| [`Support/Version.env`](../../Support/Version.env) | Defines bundle version/build values | version environment file | build script | [L12](12-testing-debugging-and-change-workflow.md) | Reference |
| [`script/build_and_run.sh`](../../script/build_and_run.sh) | Builds, stages, signs, launches, and verifies | shell build pipeline | developers and CI diagnostics | [L12](12-testing-debugging-and-change-workflow.md) | Manual |

## Current project documentation

| Path | Role | Types / artifacts | Consumer | Lecture | Evidence |
|---|---|---|---|---|---|
| [`docs/BETA_READINESS.md`](../BETA_READINESS.md) | Tracks beta release readiness | readiness checklist | release maintainers | [L12](12-testing-debugging-and-change-workflow.md) | Reference |
| [`docs/HANDOFF_PROTOCOL.md`](../HANDOFF_PROTOCOL.md) | Defines implementation handoff expectations | handoff protocol | maintainers/agents | [L12](12-testing-debugging-and-change-workflow.md) | Reference |
| [`docs/MANUAL_TEST_MATRIX.md`](../MANUAL_TEST_MATRIX.md) | Records irreducible macOS verification | manual test matrix | QA and release maintainers | [L12](12-testing-debugging-and-change-workflow.md) | Manual |
| [`docs/MODULARITY_ROADMAP.md`](../MODULARITY_ROADMAP.md) | Plans architectural modularity work | roadmap | architecture maintainers | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/OPEN_SOURCE_RESEARCH.md`](../OPEN_SOURCE_RESEARCH.md) | Records open-source comparison research | research report | product/architecture maintainers | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/PRODUCT_RESEARCH_REPORT.md`](../PRODUCT_RESEARCH_REPORT.md) | Records product research findings | research report | product maintainers | [L1](01-product-and-user-experience.md) | Reference |
| [`docs/UPSTREAM_REUSE.md`](../UPSTREAM_REUSE.md) | Tracks upstream reuse opportunities | reuse analysis | architecture maintainers | [L2](02-repository-and-technology-stack.md) | Reference |

## Historical specifications and plans

| Path | Role | Types / artifacts | Consumer | Lecture | Evidence |
|---|---|---|---|---|---|
| [`docs/superpowers/plans/2026-07-20-notion-pip-v1.md`](../superpowers/plans/2026-07-20-notion-pip-v1.md) | Notion pip v1 | historical implementation plan | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/plans/2026-07-21-durable-pinned-page.md`](../superpowers/plans/2026-07-21-durable-pinned-page.md) | Durable pinned page | historical implementation plan | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/plans/2026-07-21-edge-stash.md`](../superpowers/plans/2026-07-21-edge-stash.md) | Edge stash | historical implementation plan | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/plans/2026-07-21-one-click-new-notion-page.md`](../superpowers/plans/2026-07-21-one-click-new-notion-page.md) | One click new notion page | historical implementation plan | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/plans/2026-07-22-draggable-edge-stash.md`](../superpowers/plans/2026-07-22-draggable-edge-stash.md) | Draggable edge stash | historical implementation plan | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/plans/2026-07-22-performance-signposts-lazy-capture.md`](../superpowers/plans/2026-07-22-performance-signposts-lazy-capture.md) | Performance signposts lazy capture | historical implementation plan | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/plans/2026-07-22-progressive-quick-capture-parity.md`](../superpowers/plans/2026-07-22-progressive-quick-capture-parity.md) | Progressive quick capture parity | historical implementation plan | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/plans/2026-07-22-typing-aware-pip-chrome.md`](../superpowers/plans/2026-07-22-typing-aware-pip-chrome.md) | Typing aware pip chrome | historical implementation plan | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/plans/2026-07-28-open-in-notion-stash.md`](../superpowers/plans/2026-07-28-open-in-notion-stash.md) | Open in notion stash | historical implementation plan | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/plans/2026-07-28-repin-active-page.md`](../superpowers/plans/2026-07-28-repin-active-page.md) | Repin active page | historical implementation plan | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/plans/2026-07-28-retained-notion-selection.md`](../superpowers/plans/2026-07-28-retained-notion-selection.md) | Retained notion selection | historical implementation plan | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/plans/2026-07-30-performance-informed-modularity.md`](../superpowers/plans/2026-07-30-performance-informed-modularity.md) | Performance informed modularity | historical implementation plan | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/plans/2026-08-03-repository-course.md`](../superpowers/plans/2026-08-03-repository-course.md) | Repository course | historical implementation plan | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/specs/2026-07-21-durable-pinned-page-design.md`](../superpowers/specs/2026-07-21-durable-pinned-page-design.md) | Durable pinned page | historical design specification | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/specs/2026-07-21-edge-stash-design.md`](../superpowers/specs/2026-07-21-edge-stash-design.md) | Edge stash | historical design specification | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/specs/2026-07-21-global-shortcut-toggle-design.md`](../superpowers/specs/2026-07-21-global-shortcut-toggle-design.md) | Global shortcut toggle | historical design specification | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/specs/2026-07-21-menu-bar-pip-toggle-design.md`](../superpowers/specs/2026-07-21-menu-bar-pip-toggle-design.md) | Menu bar pip toggle | historical design specification | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/specs/2026-07-21-one-click-new-notion-page-design.md`](../superpowers/specs/2026-07-21-one-click-new-notion-page-design.md) | One click new notion page | historical design specification | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/specs/2026-07-22-draggable-edge-stash-design.md`](../superpowers/specs/2026-07-22-draggable-edge-stash-design.md) | Draggable edge stash | historical design specification | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/specs/2026-07-22-live-only-pip-cleanup-design.md`](../superpowers/specs/2026-07-22-live-only-pip-cleanup-design.md) | Live only pip cleanup | historical design specification | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/specs/2026-07-22-progressive-quick-capture-parity-design.md`](../superpowers/specs/2026-07-22-progressive-quick-capture-parity-design.md) | Progressive quick capture parity | historical design specification | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/specs/2026-07-22-typing-aware-pip-chrome-design.md`](../superpowers/specs/2026-07-22-typing-aware-pip-chrome-design.md) | Typing aware pip chrome | historical design specification | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/specs/2026-07-23-reload-saved-pin-design.md`](../superpowers/specs/2026-07-23-reload-saved-pin-design.md) | Reload saved pin | historical design specification | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/specs/2026-07-24-consolidated-settings-design.md`](../superpowers/specs/2026-07-24-consolidated-settings-design.md) | Consolidated settings | historical design specification | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/specs/2026-07-24-swift-tooling-baseline-design.md`](../superpowers/specs/2026-07-24-swift-tooling-baseline-design.md) | Swift tooling baseline | historical design specification | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/specs/2026-07-28-open-in-notion-stash-design.md`](../superpowers/specs/2026-07-28-open-in-notion-stash-design.md) | Open in notion stash | historical design specification | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/specs/2026-07-28-retained-notion-selection-design.md`](../superpowers/specs/2026-07-28-retained-notion-selection-design.md) | Retained notion selection | historical design specification | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/superpowers/specs/2026-08-03-repository-course-design.md`](../superpowers/specs/2026-08-03-repository-course-design.md) | Repository course | historical design specification | maintainers and archaeology | [L2](02-repository-and-technology-stack.md) | Reference |

## Course documentation

| Path | Role | Types / artifacts | Consumer | Lecture | Evidence |
|---|---|---|---|---|---|
| [`docs/course/01-product-and-user-experience.md`](01-product-and-user-experience.md) | Teaches product and user experience | course lecture | learners and presenters | [L1](01-product-and-user-experience.md) | Reference |
| [`docs/course/02-repository-and-technology-stack.md`](02-repository-and-technology-stack.md) | Teaches repository and technology stack | course lecture | learners and presenters | [L2](02-repository-and-technology-stack.md) | Reference |
| [`docs/course/03-application-lifecycle.md`](03-application-lifecycle.md) | Teaches application lifecycle | course lecture | learners and presenters | [L3](03-application-lifecycle.md) | Reference |
| [`docs/course/04-composition-and-runtime.md`](04-composition-and-runtime.md) | Teaches composition and runtime | course lecture | learners and presenters | [L4](04-composition-and-runtime.md) | Reference |
| [`docs/course/05-panel-stashing-and-controls.md`](05-panel-stashing-and-controls.md) | Teaches panel stashing and controls | course lecture | learners and presenters | [L5](05-panel-stashing-and-controls.md) | Reference |
| [`docs/course/06-webkit-notion-session.md`](06-webkit-notion-session.md) | Teaches webkit notion session | course lecture | learners and presenters | [L6](06-webkit-notion-session.md) | Reference |
| [`docs/course/07-domain-modeling-and-policies.md`](07-domain-modeling-and-policies.md) | Teaches domain modeling and policies | course lecture | learners and presenters | [L7](07-domain-modeling-and-policies.md) | Reference |
| [`docs/course/08-persistence-and-restoration.md`](08-persistence-and-restoration.md) | Teaches persistence and restoration | course lecture | learners and presenters | [L8](08-persistence-and-restoration.md) | Reference |
| [`docs/course/09-quick-capture-editor-bridge.md`](09-quick-capture-editor-bridge.md) | Teaches quick capture editor bridge | course lecture | learners and presenters | [L9](09-quick-capture-editor-bridge.md) | Reference |
| [`docs/course/10-notion-api-and-delivery.md`](10-notion-api-and-delivery.md) | Teaches notion api and delivery | course lecture | learners and presenters | [L10](10-notion-api-and-delivery.md) | Reference |
| [`docs/course/11-views-settings-and-state.md`](11-views-settings-and-state.md) | Teaches views settings and state | course lecture | learners and presenters | [L11](11-views-settings-and-state.md) | Reference |
| [`docs/course/12-testing-debugging-and-change-workflow.md`](12-testing-debugging-and-change-workflow.md) | Teaches testing debugging and change workflow | course lecture | learners and presenters | [L12](12-testing-debugging-and-change-workflow.md) | Reference |
| [`docs/course/ARCHITECTURE_MAP.md`](ARCHITECTURE_MAP.md) | Maps owners and six runtime flows | architecture reference | maintainers and lectures | [Course](README.md) | Reference |
| [`docs/course/CHANGE_GUIDE.md`](CHANGE_GUIDE.md) | Guides ownership, diagnosis, and verification | maintainer playbook | contributors | [Guide](CHANGE_GUIDE.md) | Reference |
| [`docs/course/GLOSSARY.md`](GLOSSARY.md) | Defines repository vocabulary | course glossary | all course readers | [Course](README.md) | Reference |
| [`docs/course/README.md`](README.md) | Indexes outcomes, paths, and lectures | course syllabus | learners and presenters | [Course](README.md) | Reference |
| [`docs/course/FILE_ATLAS.md`](FILE_ATLAS.md) | Catalogs every Git-visible repository file | exhaustive file atlas | maintainers and course readers | [Course](README.md) | Reference |
| [`docs/course/PRESENTER_GUIDE.md`](PRESENTER_GUIDE.md) | Guides full-course schedules, demos, timing, and recovery | completed course guide | presenters | [Course](README.md) | Reference |
| [`docs/course/CONDENSED_TALK.md`](CONDENSED_TALK.md) | Provides the self-contained 60-, 75-, or 90-minute architecture talk | completed course talk | presenters and fast-track learners | [Course](README.md) | Reference |
