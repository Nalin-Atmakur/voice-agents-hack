import SwiftUI

struct ContentView: View {
    @StateObject private var bootstrapViewModel = AppBootstrapViewModel()
    @StateObject private var treeBuilderViewModel = TreeBuilderViewModel(
        createdBy: ProcessInfo.processInfo.hostName
    )
    @StateObject private var appNetworkCoordinator = AppNetworkCoordinator()
    @State private var onboardingRoute: OnboardingRoute = .welcome

    private enum OnboardingRoute {
        case welcome
        case createNetwork
        case joinNetwork
    }

    var body: some View {
        Group {
            if bootstrapViewModel.isDownloadComplete {
                mainAppShell
            } else {
                downloadGate
            }
        }
        .task {
            bootstrapViewModel.startIfNeeded()
        }
    }

    private var mainAppShell: some View {
        NavigationStack {
            switch onboardingRoute {
            case .welcome:
                WelcomeView {
                    onboardingRoute = .createNetwork
                } onJoinNetwork: {
                    onboardingRoute = .joinNetwork
                }

            case .createNetwork:
                TreeBuilderView(
                    viewModel: treeBuilderViewModel,
                    onBack: {
                        onboardingRoute = .welcome
                    },
                    onPublishNetwork: { config in
                        appNetworkCoordinator.publish(networkConfig: config)
                    }
                )

            case .joinNetwork:
                JoinNetworkFlowView(
                    discoveryService: appNetworkCoordinator.discoveryService,
                    treeSyncService: appNetworkCoordinator.treeSyncService
                ) {
                    onboardingRoute = .welcome
                }
            }
        }
    }

    private var downloadGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Preparing On-Device AI Model")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Gemma 4 E4B INT4 (~6.7 GB)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView(value: bootstrapViewModel.downloadProgress, total: 1)
                .progressViewStyle(.linear)
                .frame(maxWidth: 260)

            Text(bootstrapViewModel.progressLabel)
                .font(.headline.monospacedDigit())

            if let errorMessage = bootstrapViewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("Retry Download") {
                    bootstrapViewModel.retry()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("TacNet features are locked until model download completes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
    }
}

struct WelcomeView: View {
    let onCreateNetwork: () -> Void
    let onJoinNetwork: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 24)

            Image(systemName: "person.3.sequence.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color.accentColor)

            Text("Welcome to TacNet")
                .font(.title2)
                .fontWeight(.bold)

            Text("Set up a command tree as organiser or join an existing network.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button("Create Network", action: onCreateNetwork)
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                Button("Join Network", action: onJoinNetwork)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)

            Spacer()
        }
        .navigationTitle("Onboarding")
    }
}

struct TreeBuilderView: View {
    @ObservedObject var viewModel: TreeBuilderViewModel
    let onBack: (() -> Void)?
    let onPublishNetwork: ((NetworkConfig) -> Void)?

    @State private var networkNameDraft: String
    @State private var pinDraft: String
    @State private var selectedNodeID: String?
    @State private var renameDraft: String
    @State private var newChildLabelDraft: String = ""
    @State private var isPublished = false

    init(
        viewModel: TreeBuilderViewModel,
        onBack: (() -> Void)? = nil,
        onPublishNetwork: ((NetworkConfig) -> Void)? = nil
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.onBack = onBack
        self.onPublishNetwork = onPublishNetwork
        _networkNameDraft = State(initialValue: viewModel.networkConfig.networkName)
        _pinDraft = State(initialValue: "")
        _selectedNodeID = State(initialValue: viewModel.networkConfig.tree.id)
        _renameDraft = State(initialValue: viewModel.networkConfig.tree.label)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Network Settings") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Network name", text: $networkNameDraft)
                            .textFieldStyle(.roundedBorder)

                        SecureField("Optional PIN", text: $pinDraft)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("Apply Settings") {
                                _ = viewModel.updateNetworkName(networkNameDraft)
                                _ = viewModel.updatePin(pinDraft)
                            }
                            .buttonStyle(.borderedProminent)

                            Text("Version \(viewModel.currentVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button(isPublished ? "Update BLE Publish" : "Publish Network") {
                                onPublishNetwork?(viewModel.networkConfig)
                                isPublished = true
                            }
                            .buttonStyle(.bordered)
                            .disabled(onPublishNetwork == nil)

                            if isPublished {
                                Label("Advertising live", systemImage: "dot.radiowaves.left.and.right")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }

                        Text("Open slots: \(viewModel.networkConfig.openSlotCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Tree") {
                    VStack(alignment: .leading, spacing: 10) {
                        if viewModel.isTreeEmpty {
                            Text("Tree is empty. Add a child node to start building the hierarchy.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        TreeNodeTreeView(
                            node: viewModel.networkConfig.tree,
                            depth: 0,
                            selectedNodeID: selectedNodeID
                        ) { node in
                            selectedNodeID = node.id
                            renameDraft = node.label
                        }
                    }
                }

                GroupBox("Edit Selected Node") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(selectedNodeSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        TextField("Rename selected node", text: $renameDraft)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("Rename") {
                                guard let selectedNodeID else { return }
                                _ = viewModel.renameNode(nodeID: selectedNodeID, newLabel: renameDraft)
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedNodeID == nil)

                            Button("Remove", role: .destructive) {
                                guard let selectedNodeID else { return }
                                if viewModel.removeNode(nodeID: selectedNodeID) {
                                    let root = viewModel.networkConfig.tree
                                    self.selectedNodeID = root.id
                                    renameDraft = root.label
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedNodeID == nil)
                        }

                        TextField("New child label", text: $newChildLabelDraft)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("Add Child") {
                                let parentID = selectedNodeID ?? viewModel.networkConfig.tree.id
                                guard let created = viewModel.addNode(parentID: parentID, label: newChildLabelDraft) else {
                                    return
                                }
                                selectedNodeID = created.id
                                renameDraft = created.label
                                newChildLabelDraft = ""
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Clear Tree", role: .destructive) {
                                guard viewModel.clearTree() else { return }
                                let root = viewModel.networkConfig.tree
                                selectedNodeID = root.id
                                renameDraft = root.label
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                GroupBox("BLE Distribution JSON") {
                    Text(viewModel.serializedTreeJSON(prettyPrinted: true) ?? "{}")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .navigationTitle("Tree Builder")
        .toolbar {
            if let onBack {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back", action: onBack)
                }
            }
        }
        .onChange(of: selectedNodeID) { newValue in
            guard
                let newValue,
                let node = viewModel.node(withID: newValue)
            else {
                return
            }
            renameDraft = node.label
        }
        .onReceive(viewModel.$networkConfig) { updatedConfig in
            guard isPublished else {
                return
            }
            onPublishNetwork?(updatedConfig)
        }
    }

    private var selectedNodeSummary: String {
        guard
            let selectedNodeID,
            let node = viewModel.node(withID: selectedNodeID)
        else {
            return "No node selected."
        }

        let nodeLabel = node.label.isEmpty ? "(unnamed)" : node.label
        return "Selected: \(nodeLabel) • \(selectedNodeID)"
    }
}

private struct TreeNodeTreeView: View {
    let node: TreeNode
    let depth: Int
    let selectedNodeID: String?
    let onSelect: (TreeNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                onSelect(node)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.label.isEmpty ? "(unnamed node)" : node.label)
                            .font(.subheadline.weight(.medium))
                        Text(node.claimedBy ?? "Available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(node.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, CGFloat(depth) * 16)

            ForEach(node.children, id: \.id) { child in
                TreeNodeTreeView(
                    node: child,
                    depth: depth + 1,
                    selectedNodeID: selectedNodeID,
                    onSelect: onSelect
                )
            }
        }
    }

    private var rowBackground: Color {
        selectedNodeID == node.id ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12)
    }
}

private struct JoinNetworkFlowView: View {
    @ObservedObject var discoveryService: NetworkDiscoveryService
    @ObservedObject var treeSyncService: TreeSyncService
    let onBack: () -> Void

    @State private var selectedPINNetwork: DiscoveredNetwork?
    @State private var pinDraft = ""
    @State private var joinErrorMessage: String?
    @State private var isJoining = false
    @State private var joinedConfig: NetworkConfig?

    var body: some View {
        Group {
            if let joinedConfig {
                joinedState(config: joinedConfig)
            } else if let selectedPINNetwork {
                pinEntryState(network: selectedPINNetwork)
            } else {
                NetworkScanView(
                    discoveryService: discoveryService,
                    onSelectNetwork: handleNetworkSelection,
                    onBack: onBack
                )
            }
        }
        .navigationTitle("Join")
        .onDisappear {
            discoveryService.stopScanning()
        }
    }

    @ViewBuilder
    private func pinEntryState(network: DiscoveredNetwork) -> some View {
        PinEntryView(
            network: network,
            pin: $pinDraft,
            errorMessage: joinErrorMessage,
            isJoining: isJoining,
            onSubmit: {
                Task {
                    await join(network: network, pin: pinDraft)
                }
            },
            onCancel: {
                selectedPINNetwork = nil
                pinDraft = ""
                joinErrorMessage = nil
            }
        )
    }

    @ViewBuilder
    private func joinedState(config: NetworkConfig) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Joined \(config.networkName)", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)

            Text("Version \(config.version) • Open slots \(config.openSlotCount)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            GroupBox("Received Tree JSON") {
                ScrollView {
                    Text(prettyPrintedJSON(for: config) ?? "{}")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 260)
            }

            HStack(spacing: 10) {
                Button("Join Another Network") {
                    joinedConfig = nil
                    selectedPINNetwork = nil
                    pinDraft = ""
                    joinErrorMessage = nil
                    discoveryService.startScanning(timeout: 10)
                }
                .buttonStyle(.bordered)

                Button("Back", action: onBack)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func handleNetworkSelection(_ network: DiscoveredNetwork) {
        joinErrorMessage = nil

        if network.requiresPIN {
            selectedPINNetwork = network
            pinDraft = ""
            return
        }

        Task {
            await join(network: network, pin: nil)
        }
    }

    private func join(network: DiscoveredNetwork, pin: String?) async {
        guard !isJoining else {
            return
        }

        isJoining = true
        defer { isJoining = false }

        do {
            let joined = try await treeSyncService.join(network: network, pin: pin)
            joinedConfig = joined
            selectedPINNetwork = nil
            joinErrorMessage = nil
            discoveryService.stopScanning()
        } catch let error as TreeSyncJoinError {
            joinErrorMessage = joinErrorMessage(for: error)
        } catch {
            joinErrorMessage = error.localizedDescription
        }
    }

    private func joinErrorMessage(for error: TreeSyncJoinError) -> String {
        switch error {
        case .treeConfigUnavailable:
            return "Unable to fetch tree data from organiser. Try scanning again."
        case .networkMismatch:
            return "Discovered network details changed. Please rescan."
        case .pinRequired:
            return "PIN is required to join this network."
        case .invalidPIN:
            return "Incorrect PIN. Join blocked."
        }
    }

    private func prettyPrintedJSON(for config: NetworkConfig) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config.tree) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct NetworkScanView: View {
    @ObservedObject var discoveryService: NetworkDiscoveryService
    let onSelectNetwork: (DiscoveredNetwork) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if discoveryService.nearbyNetworks.isEmpty {
                VStack(spacing: 8) {
                    if discoveryService.isScanning {
                        ProgressView()
                    }

                    Text(discoveryService.isScanning ? "Scanning for nearby TacNet networks…" : "No networks found.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(discoveryService.nearbyNetworks) { network in
                    Button {
                        onSelectNetwork(network)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(network.networkName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("Open slots: \(network.openSlotCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: network.requiresPIN ? "lock.fill" : "lock.open.fill")
                                .foregroundStyle(network.requiresPIN ? .orange : .green)
                        }
                    }
                }
                .listStyle(.plain)
            }

            HStack(spacing: 12) {
                Button("Rescan (10s)") {
                    discoveryService.startScanning(timeout: 10)
                }
                .buttonStyle(.bordered)

                Button("Back", action: onBack)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal)
        .task {
            discoveryService.startScanning(timeout: 10)
        }
    }
}

private struct PinEntryView: View {
    let network: DiscoveredNetwork
    @Binding var pin: String
    let errorMessage: String?
    let isJoining: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Enter PIN for \(network.networkName)")
                .font(.headline)
                .multilineTextAlignment(.center)

            SecureField("Network PIN", text: $pin)
                .textFieldStyle(.roundedBorder)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)

                Button(isJoining ? "Joining…" : "Join Network", action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .disabled(isJoining)
            }
        }
        .padding()
    }
}

@MainActor
final class AppNetworkCoordinator: ObservableObject {
    let meshService: BluetoothMeshService
    let discoveryService: NetworkDiscoveryService
    let treeSyncService: TreeSyncService

    init(meshService: BluetoothMeshService = BluetoothMeshService()) {
        self.meshService = meshService
        discoveryService = NetworkDiscoveryService(meshService: meshService)
        treeSyncService = TreeSyncService(meshService: meshService)
    }

    func publish(networkConfig: NetworkConfig) {
        meshService.publishNetwork(networkConfig)
    }
}

@MainActor
final class AppBootstrapViewModel: ObservableObject {
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var isDownloadComplete = false
    @Published private(set) var errorMessage: String?

    private let downloadService: ModelDownloadService
    private var hasStarted = false

    init(downloadService: ModelDownloadService = .live) {
        self.downloadService = downloadService
    }

    var progressLabel: String {
        "\(Int((downloadProgress * 100).rounded()))%"
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true

        Task {
            if await downloadService.canUseTacticalFeatures() {
                downloadProgress = 1
                isDownloadComplete = true
                errorMessage = nil
                return
            }

            do {
                _ = try await downloadService.ensureModelAvailable { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        self.downloadProgress = max(self.downloadProgress, progress)
                    }
                }

                downloadProgress = 1
                isDownloadComplete = true
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func retry() {
        hasStarted = false
        errorMessage = nil
        startIfNeeded()
    }
}

#Preview {
    ContentView()
}
