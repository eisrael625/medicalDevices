import SwiftUI
import CoreBluetooth
import Foundation
import Combine

private let bleServiceUUID = CBUUID(string: "FFE0")
private let bleDataCharacteristicUUID = CBUUID(string: "FFE1")
private let bleControlCharacteristicUUID = CBUUID(string: "FFE2")
private let bleDeviceName = "MedicalDevices"

@main
struct BioImpedanceApp: App {
    @StateObject private var bleManager = BLEDeviceManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .preferredColorScheme(.dark)
                .tint(.cyan)
        }
    }
}

enum WorkflowStep: Int, CaseIterable {
    case setup
    case baseline
    case comparison
    case symptoms
    case result

    var title: String {
        switch self {
        case .setup: return "Setup"
        case .baseline: return "Baseline"
        case .comparison: return "Comparison"
        case .symptoms: return "Symptoms"
        case .result: return "Result"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var bleManager: BLEDeviceManager
    @State private var currentStep: WorkflowStep = .setup
    @State private var baselineCaptures: [Double] = []
    @State private var comparisonCaptures: [Double] = []
    @State private var symptomClaudication = false
    @State private var symptomColdFoot = false
    @State private var symptomWound = false
    @State private var riskSmoking = false
    @State private var riskDiabetes = false
    @State private var riskCholesterol = false

    private let captureTarget = 3

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                screenHeader(
                    eyebrow: "Vascular Assessment",
                    title: "PulseTrace",
                    subtitle: bleManager.connectionStatus
                )

                connectCard
                progressCard
                stepContent

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Device Status")
                        infoRow("Latest P2P", bleManager.latestP2PText, valueColor: .cyan)
                        infoRow("Stored Measurements", "\(bleManager.captureCount)", valueColor: .white)
                        infoRow("BLE Packets", "\(bleManager.packetCount)", valueColor: .green)
                    }
                }
            }
            .padding()
        }
        .appBackground()
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .setup:
            setupCard
        case .baseline:
            baselineCard
        case .comparison:
            comparisonCard
        case .symptoms:
            symptomCard
        case .result:
            resultCard
        }
    }

    private var connectCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Connect Device")
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                Text("Connect to the measurement module to begin a guided lower-extremity screening session.")
                    .foregroundStyle(.white.opacity(0.72))

                Button(action: bleManager.connect) {
                    Text(bleManager.primaryButtonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(bleManager.isConnected ? Color.green : Color.cyan)
                        )
                        .foregroundStyle(.black)
                }
                .disabled(!bleManager.canTapPrimaryButton)
            }
        }
    }

    private var progressCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Session Progress")

                HStack(spacing: 10) {
                    ForEach(WorkflowStep.allCases, id: \.self) { step in
                        VStack(spacing: 8) {
                            Circle()
                                .fill(step.rawValue <= currentStep.rawValue ? Color.cyan : Color.white.opacity(0.18))
                                .frame(width: 14, height: 14)
                            Text(step.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(step.rawValue <= currentStep.rawValue ? .white : .white.opacity(0.55))
                        }
                        if step != WorkflowStep.allCases.last {
                            Rectangle()
                                .fill(step.rawValue < currentStep.rawValue ? Color.cyan : Color.white.opacity(0.12))
                                .frame(height: 2)
                        }
                    }
                }
            }
        }
    }

    private var setupCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Step 1: Placement")

                Text("Position the probes 2 inches apart on the first limb at a consistent anatomical location. Maintain the same spacing and height for all captures in the session.")
                    .foregroundStyle(.white.opacity(0.78))

                bullet("Probe spacing should remain fixed at 2 inches.")
                bullet("Use the same marked location for repeat measurements.")
                bullet("The patient should remain still and relaxed.")
                bullet("This assessment identifies asymmetry patterns and supports follow-up decisions.")

                Button("Begin Baseline Series") {
                    baselineCaptures.removeAll()
                    comparisonCaptures.removeAll()
                    currentStep = .baseline
                }
                .buttonStyle(ActionButtonStyle(fill: .cyan))
                .disabled(!bleManager.isConnected)
            }
        }
    }

    private var baselineCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Step 2: Primary Site")

                Text("Collect three measurements at the primary site without changing probe placement.")
                    .foregroundStyle(.white.opacity(0.78))

                captureSummary(title: "Primary-Site Measurements", values: baselineCaptures)

                Button("Record Primary Measurement") {
                    captureForCurrentStep()
                }
                .buttonStyle(ActionButtonStyle(fill: .cyan))
                .disabled(!bleManager.isConnected || baselineCaptures.count >= captureTarget)

                Button("Continue To Comparison Site") {
                    currentStep = .comparison
                }
                .buttonStyle(ActionButtonStyle(fill: .green))
                .disabled(baselineCaptures.count < captureTarget)
            }
        }
    }

    private var comparisonCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Step 3: Comparison Site")

                Text("Move to the matched location on the opposite limb. Preserve the same 2-inch spacing and collect three measurements.")
                    .foregroundStyle(.white.opacity(0.78))

                captureSummary(title: "Comparison-Site Measurements", values: comparisonCaptures)

                Button("Record Comparison Measurement") {
                    captureForCurrentStep()
                }
                .buttonStyle(ActionButtonStyle(fill: .cyan))
                .disabled(!bleManager.isConnected || comparisonCaptures.count >= captureTarget)

                Button("Continue To Clinical Questions") {
                    currentStep = .symptoms
                }
                .buttonStyle(ActionButtonStyle(fill: .green))
                .disabled(comparisonCaptures.count < captureTarget)
            }
        }
    }

    private var symptomCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Step 4: Clinical Context")

                Text("Document symptoms and risk factors to contextualize the measurement pattern and determine whether formal vascular evaluation should be considered.")
                    .foregroundStyle(.white.opacity(0.78))

                Toggle("Calf pain while walking that improves with rest", isOn: $symptomClaudication)
                Toggle("One foot feels colder than the other", isOn: $symptomColdFoot)
                Toggle("Non-healing foot or toe wound", isOn: $symptomWound)
                Toggle("Smoking history", isOn: $riskSmoking)
                Toggle("Diabetes", isOn: $riskDiabetes)
                Toggle("High cholesterol", isOn: $riskCholesterol)

                Button("Generate Assessment") {
                    currentStep = .result
                }
                .buttonStyle(ActionButtonStyle(fill: .green))
                .disabled(baselineCaptures.count < captureTarget || comparisonCaptures.count < captureTarget)
            }
            .toggleStyle(SwitchToggleStyle(tint: .cyan))
        }
    }

    private var resultCard: some View {
        let summary = buildAssessment()

        return GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Step 5: Assessment")

                Text(summary.title)
                    .font(.title2.bold())
                    .foregroundStyle(summary.color)

                Text(summary.message)
                    .foregroundStyle(.white.opacity(0.84))

                infoRow("Baseline Mean", formatMv(baselineMean), valueColor: .white)
                infoRow("Comparison Mean", formatMv(comparisonMean), valueColor: .white)
                infoRow("Difference", formatMv(comparisonMean - baselineMean), valueColor: summary.color)
                infoRow("Percent Change", String(format: "%+.1f%%", percentDifference), valueColor: summary.color)

                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Clinical Note")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.88))
                        Text("This result is intended to support screening workflow and referral decisions. It should be interpreted alongside symptoms, risk profile, and formal vascular testing when indicated.")
                            .foregroundStyle(.white.opacity(0.68))
                    }
                }

                HStack(spacing: 12) {
                    Button("Edit Clinical Questions") {
                        currentStep = .symptoms
                    }
                    .buttonStyle(ActionButtonStyle(fill: .orange))

                    Button("Start New Session") {
                        resetWorkflow()
                    }
                    .buttonStyle(ActionButtonStyle(fill: .cyan))
                }
            }
        }
    }

    @ViewBuilder
    private func captureSummary(title: String, values: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            if values.isEmpty {
                Text("No captures yet.")
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    infoRow("Capture \(index + 1)", formatMv(value), valueColor: .white)
                }
                if values.count > 1 {
                    infoRow("Mean", formatMv(values.mean), valueColor: .cyan)
                    infoRow("Range", formatMv(values.maxValue - values.minValue), valueColor: .green)
                }
            }
        }
    }

    private func captureForCurrentStep() {
        bleManager.captureP2P { value in
            switch currentStep {
            case .baseline:
                guard baselineCaptures.count < captureTarget else { return }
                baselineCaptures.append(value)
            case .comparison:
                guard comparisonCaptures.count < captureTarget else { return }
                comparisonCaptures.append(value)
            default:
                break
            }
        }
    }

    private var baselineMean: Double {
        baselineCaptures.mean
    }

    private var comparisonMean: Double {
        comparisonCaptures.mean
    }

    private var percentDifference: Double {
        guard baselineMean != 0 else { return 0 }
        return ((comparisonMean - baselineMean) / baselineMean) * 100.0
    }

    private func buildAssessment() -> AssessmentSummary {
        let riskCount = [symptomClaudication, symptomColdFoot, symptomWound, riskSmoking, riskDiabetes, riskCholesterol]
            .filter { $0 }
            .count

        if symptomWound {
            return AssessmentSummary(
                title: "Prompt Clinical Evaluation Recommended",
                message: "A non-healing wound elevates concern regardless of the impedance pattern. Escalate for formal clinical assessment.",
                color: .red
            )
        }

        if abs(percentDifference) >= 20.0 && riskCount >= 2 {
            return AssessmentSummary(
                title: "Elevated Vascular Risk Pattern",
                message: "A meaningful inter-limb asymmetry is present alongside symptom or risk indicators. Consider formal vascular follow-up, including ABI, if clinically appropriate.",
                color: .orange
            )
        }

        if abs(percentDifference) >= 20.0 {
            return AssessmentSummary(
                title: "Asymmetry Detected",
                message: "A measurable inter-limb difference is present. Repeat the acquisition to confirm consistency. If asymmetry persists, consider follow-up evaluation.",
                color: .yellow
            )
        }

        return AssessmentSummary(
            title: "No Significant Asymmetry Detected",
            message: "The inter-limb difference is limited in this session. This does not exclude disease; persistent symptoms should still prompt formal vascular testing.",
            color: .green
        )
    }

    private func resetWorkflow() {
        baselineCaptures.removeAll()
        comparisonCaptures.removeAll()
        symptomClaudication = false
        symptomColdFoot = false
        symptomWound = false
        riskSmoking = false
        riskDiabetes = false
        riskCholesterol = false
        currentStep = .setup
        bleManager.clearHistory()
    }

    private func formatMv(_ value: Double) -> String {
        String(format: "%.1f mV", value)
    }
}

struct AssessmentSummary {
    let title: String
    let message: String
    let color: Color
}

struct AppBackground: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.07, blue: 0.11),
                    Color(red: 0.06, green: 0.10, blue: 0.16),
                    Color(red: 0.02, green: 0.04, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                RadialGradient(
                    colors: [
                        Color.cyan.opacity(0.16),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 280
                )
            )
            .ignoresSafeArea()

            content
        }
    }
}

extension View {
    func appBackground() -> some View {
        modifier(AppBackground())
    }
}

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 10)
    }
}

struct ActionButtonStyle: ButtonStyle {
    let fill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                fill.opacity(configuration.isPressed ? 0.70 : 1.0),
                                fill.opacity(configuration.isPressed ? 0.58 : 0.82)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .foregroundStyle(.black)
    }
}

private func screenHeader(eyebrow: String, title: String, subtitle: String) -> some View {
    VStack(spacing: 10) {
        Text(eyebrow.uppercased())
            .font(.caption.weight(.bold))
            .tracking(2)
            .foregroundStyle(.cyan.opacity(0.9))

        Text(title)
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .foregroundStyle(.white)

        Text(subtitle)
            .font(.headline.weight(.medium))
            .foregroundStyle(.white.opacity(0.76))
    }
    .padding(.top, 8)
}

private func sectionTitle(_ text: String) -> some View {
    Text(text)
        .font(.title3.bold())
        .foregroundStyle(.white)
}

private func infoRow(_ title: String, _ value: String, valueColor: Color) -> some View {
    HStack(alignment: .top) {
        Text(title)
            .foregroundStyle(.white.opacity(0.75))
        Spacer()
        Text(value)
            .multilineTextAlignment(.trailing)
            .fontWeight(.semibold)
            .foregroundStyle(valueColor)
    }
}

private func bullet(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Circle()
            .fill(Color.cyan)
            .frame(width: 6, height: 6)
            .padding(.top, 6)
        Text(text)
            .foregroundStyle(.white.opacity(0.78))
    }
}

struct CapturePayload {
    let captureCount: Int
    let latestP2P: Double
    let delta: Double
    let history: [Double]
}

@MainActor
final class BLEDeviceManager: NSObject, ObservableObject {
    @Published private(set) var connectionStatus = "Tap Connect to search"
    @Published private(set) var bluetoothStateText = "Starting"
    @Published private(set) var connectedDeviceLabel = "Not connected"
    @Published private(set) var packetCount = 0
    @Published private(set) var latestPayload: CapturePayload?

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var dataCharacteristic: CBCharacteristic?
    private var controlCharacteristic: CBCharacteristic?
    private var wantsConnection = false
    private var scanTimeoutTask: DispatchWorkItem?
    private var pendingCaptureWorkItem: DispatchWorkItem?
    private var pendingCaptureThreshold: Int?
    private var pendingCaptureCompletion: ((Double) -> Void)?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    var isConnected: Bool {
        peripheral?.state == .connected && dataCharacteristic != nil
    }

    var canTapPrimaryButton: Bool {
        !isConnected && !centralManager.isScanning
    }

    var primaryButtonTitle: String {
        if isConnected {
            return "Connected"
        }
        if centralManager.isScanning {
            return "Searching..."
        }
        return "Connect"
    }

    var latestP2PText: String {
        guard let value = latestPayload?.latestP2P else { return "--" }
        return String(format: "%.2f mV", value)
    }

    var captureCount: Int {
        latestPayload?.captureCount ?? 0
    }

    func connect() {
        wantsConnection = true

        guard centralManager.state == .poweredOn else {
            connectionStatus = "Waiting for Bluetooth"
            return
        }

        if let peripheral, peripheral.state == .connected {
            connectionStatus = "Already connected"
            return
        }

        packetCount = 0
        latestPayload = nil
        connectionStatus = "Scanning for \(bleDeviceName)"
        connectedDeviceLabel = "Searching"
        startScan()
    }

    func disconnect() {
        wantsConnection = false
        scanTimeoutTask?.cancel()
        pendingCaptureWorkItem?.cancel()
        guard let peripheral else { return }
        centralManager.stopScan()
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func captureP2P(completion: ((Double) -> Void)? = nil) {
        let previousCount = latestPayload?.captureCount ?? 0
        pendingCaptureWorkItem?.cancel()
        pendingCaptureThreshold = previousCount
        pendingCaptureCompletion = completion
        sendControlCommand("capture")
        connectionStatus = "Capturing on device"
        waitForFreshCapture(after: previousCount, attempt: 0)
    }

    func refresh() {
        sendControlCommand("sync")
    }

    func clearHistory() {
        sendControlCommand("clear")
    }

    private func waitForFreshCapture(after previousCount: Int, attempt: Int) {
        if let payload = latestPayload, payload.captureCount > previousCount {
            finishPendingCapture(with: payload.latestP2P)
            return
        }

        guard attempt < 12 else {
            connectionStatus = "Waiting for updated device reading"
            pendingCaptureThreshold = nil
            pendingCaptureCompletion = nil
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            if let peripheral = self.peripheral, let dataCharacteristic = self.dataCharacteristic {
                peripheral.readValue(for: dataCharacteristic)
            }

            self.waitForFreshCapture(after: previousCount, attempt: attempt + 1)
        }

        pendingCaptureWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: workItem)
    }

    private func finishPendingCapture(with value: Double) {
        pendingCaptureWorkItem?.cancel()
        pendingCaptureWorkItem = nil
        let completion = pendingCaptureCompletion
        pendingCaptureThreshold = nil
        pendingCaptureCompletion = nil
        connectionStatus = "Capture data received"
        completion?(value)
    }

    private func startScan() {
        centralManager.stopScan()
        scanTimeoutTask?.cancel()
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        let timeoutTask = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.centralManager.isScanning {
                self.centralManager.stopScan()
                self.connectionStatus = "Device not found"
                self.connectedDeviceLabel = "Not connected"
            }
        }

        scanTimeoutTask = timeoutTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeoutTask)
    }

    private func handlePayload(_ payload: String) {
        let parts = payload
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ",")

        guard parts.count == 9,
              let captureCount = Int(parts[0]),
              let latestP2P = Double(parts[1]),
              let delta = Double(parts[2]),
              let historyCount = Int(parts[3]) else {
            return
        }

        var history: [Double] = []
        for index in 0..<min(historyCount, 5) {
            let partIndex = 4 + index
            guard partIndex < parts.count, let value = Double(parts[partIndex]) else {
                break
            }
            history.append(value)
        }

        latestPayload = CapturePayload(
            captureCount: captureCount,
            latestP2P: latestP2P,
            delta: delta,
            history: history
        )
        packetCount += 1

        if let threshold = pendingCaptureThreshold, captureCount > threshold {
            finishPendingCapture(with: latestP2P)
        } else {
            connectionStatus = "Capture data received"
        }
    }

    private func sendControlCommand(_ command: String) {
        guard let peripheral, let controlCharacteristic else { return }
        guard let data = command.data(using: .utf8) else { return }
        peripheral.writeValue(data, for: controlCharacteristic, type: .withResponse)
    }
}

extension BLEDeviceManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .unknown:
                bluetoothStateText = "Unknown"
            case .resetting:
                bluetoothStateText = "Resetting"
            case .unsupported:
                bluetoothStateText = "Unsupported"
                connectionStatus = "BLE unsupported on this device"
            case .unauthorized:
                bluetoothStateText = "Unauthorized"
                connectionStatus = "Bluetooth permission denied"
            case .poweredOff:
                bluetoothStateText = "Powered Off"
                connectionStatus = "Turn Bluetooth on"
            case .poweredOn:
                bluetoothStateText = "Powered On"
                if wantsConnection && !isConnected && !central.isScanning {
                    connectionStatus = "Scanning for \(bleDeviceName)"
                    connectedDeviceLabel = "Searching"
                    startScan()
                }
            @unknown default:
                bluetoothStateText = "Unknown"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
            guard advertisedName == bleDeviceName || peripheral.name == bleDeviceName else {
                return
            }

            scanTimeoutTask?.cancel()
            central.stopScan()
            self.peripheral = peripheral
            connectedDeviceLabel = peripheral.name ?? bleDeviceName
            connectionStatus = "Connecting to \(connectedDeviceLabel)"
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            scanTimeoutTask?.cancel()
            connectionStatus = "Discovering services"
            connectedDeviceLabel = peripheral.name ?? bleDeviceName
            peripheral.discoverServices([bleServiceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectionStatus = error?.localizedDescription ?? "Connection failed"
            connectedDeviceLabel = "Not connected"
            self.peripheral = nil
            dataCharacteristic = nil
            controlCharacteristic = nil
            if wantsConnection {
                startScan()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectionStatus = error == nil ? "Disconnected" : "Disconnected: \(error!.localizedDescription)"
            connectedDeviceLabel = "Not connected"
            self.peripheral = nil
            dataCharacteristic = nil
            controlCharacteristic = nil
            if wantsConnection {
                connectionStatus = "Reconnecting"
                startScan()
            }
        }
    }
}

extension BLEDeviceManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard error == nil else {
                connectionStatus = error?.localizedDescription ?? "Service discovery failed"
                return
            }

            guard let service = peripheral.services?.first(where: { $0.uuid == bleServiceUUID }) else {
                connectionStatus = "Service not found"
                return
            }

            connectionStatus = "Discovering characteristics"
            peripheral.discoverCharacteristics([bleDataCharacteristicUUID, bleControlCharacteristicUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard error == nil else {
                connectionStatus = error?.localizedDescription ?? "Characteristic discovery failed"
                return
            }

            dataCharacteristic = service.characteristics?.first(where: { $0.uuid == bleDataCharacteristicUUID })
            controlCharacteristic = service.characteristics?.first(where: { $0.uuid == bleControlCharacteristicUUID })

            guard let dataCharacteristic else {
                connectionStatus = "Data characteristic not found"
                return
            }

            connectionStatus = "Connected"
            peripheral.setNotifyValue(true, for: dataCharacteristic)
            peripheral.readValue(for: dataCharacteristic)
            refresh()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard error == nil else {
                connectionStatus = error?.localizedDescription ?? "Read failed"
                return
            }

            guard characteristic.uuid == bleDataCharacteristicUUID,
                  let data = characteristic.value,
                  let payload = String(data: data, encoding: .utf8) else {
                return
            }

            handlePayload(payload)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard error == nil else {
                connectionStatus = error?.localizedDescription ?? "Write failed"
                return
            }

            if let dataCharacteristic {
                peripheral.readValue(for: dataCharacteristic)
            }
        }
    }
}

extension Array where Element == Double {
    var mean: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }

    var maxValue: Double {
        max() ?? 0
    }

    var minValue: Double {
        min() ?? 0
    }
}
