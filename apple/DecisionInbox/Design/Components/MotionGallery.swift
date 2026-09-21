#if DEBUG
import SwiftUI
import RiveRuntime

/// Synthetic native QA route. No account, network or mailbox work is started.
struct MotionGallery: View {
    @State private var phase = 0
    @State private var progress = 50.0
    @State private var showArt = true
    @State private var reduced = false
    @State private var report = "Checking native asset…"
    private var motion: Bool { !reduced && !ProcessInfo.processInfo.arguments.contains("-motionReduced") }
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("MARGIN STUDIO").typeStyle(Style.kicker)
                Text("Native Rive verification").typeStyle(Style.body)
                Text(report).font(.caption.monospaced()).foregroundStyle(.secondary)
                if showArt {
                    HStack {
                        PaperIllustration(art: .receipt, phase: min(phase, 3), pull: progress, motion: motion).frame(width: 144,height: 100)
                        PaperIllustration(art: .closing, phase: min(phase, 2), motion: motion).frame(width:144,height:100)
                    }
                    PaperIllustration(art: .reading, phase: phase, motion: motion).frame(width:280,height:160)
                }
                Picker("State", selection: $phase) {
                    Text("Original").tag(0); Text("Working").tag(1)
                    Text("Result").tag(2); Text("Needs you").tag(3);Text("Empty").tag(4)
                }.pickerStyle(.segmented)
                Slider(value: $progress, in: 0...100).accessibilityLabel("Pull distance")
                Toggle("Static composition", isOn: $reduced)
                Toggle("Mount illustrations", isOn: $showArt)
                Button("Interrupt → return") {
                    Task {
                        phase = 1
                        try? await Task.sleep(for: .milliseconds(90))
                        phase = 3
                        try? await Task.sleep(for: .milliseconds(90))
                        phase = 0
                    }
                }
                Text("Synthetic inputs only. A drawing never establishes a mailbox outcome.").typeStyle(Style.bodySmall)
            }.padding(24)
        }
        .background(Ink.surface)
        .task {
            if let flag = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-motionPhase=") }), let value = Int(flag.split(separator: "=").last ?? "") { phase = value }
            report = await PaperRuntimeProbe.run()
            if ProcessInfo.processInfo.arguments.contains("-motionCycle") {
                for value in [1, 3, 0, 2, 4] {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    phase = value
                }
                for _ in 0..<5 {
                    showArt = false
                    do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                    showArt = true
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                }
                print("[paper-motion] gallery interruption and mount cycle finished")
            }
        }
    }
}

@MainActor
private enum PaperRuntimeProbe {
    private final class WeakRive { weak var value: Rive?; init(_ value: Rive) { self.value = value } }
    static func run() async -> String {
        do {
            let worker = try await Worker()
            let file = try await RiveRuntime.File(source: .local("margin-studio", .main), worker: worker)
            var checks = 0
            var retired: [WeakRive] = []
            for art in PaperArt.allCases {
                for _ in 0..<4 {
                    let board = try await file.createArtboard(art.rawValue)
                    let configuration = try await Rive(file: file, artboard: board)
                    guard let data = configuration.viewModelInstance else { throw ProbeError.missingData }
                    for value in [0, 1, 3, 0, 2] {
                        data.setValue(of: NumberProperty(path: "phase"), to: Float(value))
                        configuration.stateMachine.advance(by: 0.1)
                        let actual = try await data.value(of: NumberProperty(path: "phase"))
                        guard actual == Float(value) else { throw ProbeError.binding }
                        checks += 1
                    }
                    data.setValue(of: NumberProperty(path: "pull"), to: 73)
                    guard try await data.value(of: NumberProperty(path: "pull")) == 73 else { throw ProbeError.binding }
                    data.setValue(of: BoolProperty(path: "active"), to: false)
                    guard try await data.value(of: BoolProperty(path: "active")) == false else { throw ProbeError.binding }
                    checks += 2
                    retired.append(WeakRive(configuration))
                }
            }
            try await Task.sleep(for: .milliseconds(200))
            guard retired.allSatisfy({ $0.value == nil }) else { throw ProbeError.retainedHost }
            let result = "PASS: \(checks) native bindings; \(retired.count) hosts released"
            print("[paper-motion] \(result)")
            return result
        } catch {
            let result = "FAIL: \(error)"
            print("[paper-motion] \(result)")
            return result
        }
    }
    private enum ProbeError: Error { case missingData, binding, retainedHost }
}
#endif
