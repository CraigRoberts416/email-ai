import SwiftUI
import RiveRuntime

/// Illustrations never own a product outcome, a gesture recognizer, or text.
/// Every status/action stays native. Each visible host gets its own state
/// machine; the small immutable file and its worker are shared.
enum PaperArt: String, CaseIterable {
    case receipt = "Receipt", reading = "Reading", closing = "Closing"
}

private struct IllustrationMotionKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var illustrationMotionEnabled: Bool {
        get { self[IllustrationMotionKey.self] }
        set { self[IllustrationMotionKey.self] = newValue }
    }
}

@MainActor
private enum PaperFile {
    static var pending: Task<RiveRuntime.File, Error>?
    static func load() async throws -> RiveRuntime.File {
        if let pending { return try await pending.value }
        let task = Task { @MainActor in
            let worker = try await Worker()
            return try await RiveRuntime.File(source: .local("margin-studio", .main), worker: worker)
        }
        pending = task
        do { return try await task.value }
        catch { pending = nil; throw error }
    }
}

struct PaperIllustration: View {
    let art: PaperArt
    var phase: Int = 0
    /// Gesture distance, never estimated network progress.
    var pull: Double = 0
    var motion = true
    var inverted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.illustrationMotionEnabled) private var enabled
    @State private var visible = false
    @State private var intersectsWindow = true
    @State private var rive: Rive?
    @State private var paused = false
    @State private var renderFailed = false
    @State private var renderer = PaperRenderStatus()
    @State private var loadedGeneration = 0
    @State private var desiredPhase = 0
    @State private var desiredPull = 0.0

    private var shouldRender: Bool {
        visible && intersectsWindow && enabled && scenePhase == .active && !reduceMotion && motion
    }
    private var input: PaperInput { .init(phase: phase, pull: pull, generation: loadedGeneration) }
    private var loops: Bool { phase == 1 && art != .closing }

    var body: some View {
        Group {
            if let rive, shouldRender, !renderFailed, !renderer.failed {
                RiveUIViewRepresentable(rive: rive, delegate: renderer)
                    .frameRate(.fps(60))
                    .paused(paused)
                    .modifier(PaperInversion(inverted: inverted))
            } else {
                PaperStill(art: art, phase: phase)
                    .foregroundStyle(inverted ? Ink.onInverse : Ink.primary)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { desiredPhase = phase; desiredPull = pull; visible = true }
        .onDisappear { visible = false; rive = nil }
        .onGeometryChange(for: Bool.self) { proxy in
            // Bounds are used only as a visibility gate, never for animation.
            proxy.frame(in: .global).intersects(UIScreen.main.bounds)
        } action: { intersectsWindow = $0 }
        .task(id: shouldRender) {
            guard shouldRender else { rive = nil; return }
            renderFailed = false
            renderer.failed = false
            do {
                let file = try await PaperFile.load()
                let board = try await file.createArtboard(art.rawValue)
                let loaded = try await Rive(file: file, artboard: board)
                try Task.checkCancellation()
                guard shouldRender, loaded.viewModelInstance != nil else { return }
                loaded.viewModelInstance?.setValue(of: NumberProperty(path: "phase"), to: Float(desiredPhase))
                loaded.viewModelInstance?.setValue(of: NumberProperty(path: "pull"), to: Float(min(100, max(0, desiredPull))))
                loaded.viewModelInstance?.setValue(of: BoolProperty(path: "active"), to: true)
                // On re-entry, render the current pose instead of replaying
                // an entrance. A newly earned closing mark is the exception.
                if art != .closing || desiredPhase != 1 {
                    loaded.stateMachine.advance(by: 0)
                    loaded.stateMachine.advance(by: 1)
                }
                paused = false
                rive = loaded
                loadedGeneration += 1
            } catch is CancellationError {} catch {
                renderFailed = true
                #if DEBUG
                print("[paper-motion] asset fallback: \(error)")
                #endif
            }
        }
        .task(id: input) {
            desiredPhase = phase; desiredPull = pull
            guard let rive else { return }
            paused = false
            rive.viewModelInstance?.setValue(of: NumberProperty(path: "phase"), to: Float(phase))
            rive.viewModelInstance?.setValue(of: NumberProperty(path: "pull"), to: Float(min(100, max(0, pull))))
            guard !loops else { return }
            do { try await Task.sleep(for: .milliseconds(1100)) } catch { return }
            paused = true
        }
    }
}

private struct PaperInput: Equatable { let phase: Int; let pull: Double; let generation: Int }

private struct PaperInversion: ViewModifier {
    let inverted: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if inverted { content.colorInvert() } else { content }
    }
}

/// The host retains this because the runtime's delegate is weak.
@Observable @MainActor
private final class PaperRenderStatus: RiveUIViewDelegate {
    var failed = false
    nonisolated func view(_ view: RiveUIView, didReceiveError error: RiveUIViewError) {
        Task { @MainActor [weak self] in self?.failed = true }
    }
}

/// Drawn natively: zero timeline, GPU player, or repeated work in Reduce Motion.
/// The same paper/margin vocabulary remains even if the asset cannot load.
private struct PaperStill: View {
    let art: PaperArt
    let phase: Int
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 240, size.height / (art == .closing ? 128 : 160))
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: scale, y: scale)
            let ink = GraphicsContext.Shading.foreground
            if art == .closing {
                var baseline = Path(); baseline.move(to: .init(x: -48, y: 34)); baseline.addLine(to: .init(x: 48, y: 34))
                context.stroke(baseline, with: .color(.gray), lineWidth: 1)
                context.translateBy(x: 0, y: -3)
                if phase == 1 || phase == 2 {
                    context.fill(Path(ellipseIn: CGRect(x: -3.5, y: -3.5, width: 7, height: 7)), with: ink)
                } else {
                    for x: CGFloat in [-29, 29] {
                        var p = Path(); p.move(to: .init(x: x + (x < 0 ? 8 : -8), y: -18)); p.addLine(to: .init(x: x, y: -18)); p.addLine(to: .init(x: x, y: 18)); p.addLine(to: .init(x: x + (x < 0 ? 8 : -8), y: 18))
                        context.stroke(p, with: ink, style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
            } else {
                context.stroke(Path(roundedRect: CGRect(x: -42, y: -52, width: 84, height: 104), cornerRadius: 3), with: ink, lineWidth: 1.7)
                if art == .receipt && phase == 2 {
                    var p = Path();p.move(to: .init(x:-12,y:0));p.addLine(to:.init(x:-3,y:9));p.addLine(to:.init(x:14,y:-9))
                    context.stroke(p,with:ink,style:.init(lineWidth:2.5,lineCap:.round,lineJoin:.round))
                } else if phase == 3 || phase == 4 {
                    var p=Path();p.move(to:.init(x:14,y:-52));p.addLine(to:.init(x:25,y:-52));p.addLine(to:.init(x:25,y:-25));p.addLine(to:.init(x:19.5,y:-31));p.addLine(to:.init(x:14,y:-25));p.closeSubpath();context.fill(p,with:ink)
                } else {
                    let lines = art == .reading && phase == 2 ? 3 : 5
                    for i in 0..<lines {
                        let y = CGFloat(i)*12-26
                        var p=Path();p.move(to:.init(x:-17,y:y));p.addLine(to:.init(x:i % 2 == 0 ? 23 : 13,y:y));context.stroke(p,with:ink,lineWidth:1.8)
                    }
                    context.fill(Path(CGRect(x:-27,y:-29,width:2,height:53)),with:ink)
                }
            }
        }
    }
}
