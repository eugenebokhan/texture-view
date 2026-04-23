import Metal
import SwiftUI

#if os(iOS) || targetEnvironment(macCatalyst)

public struct TextureViewRepresentable: UIViewRepresentable {
    public let texture: MTLTexture?
    public var contentMode: TextureContentMode

    @Environment(\.displayScale) private var displayScale

    public init(
        texture: MTLTexture?,
        contentMode: TextureContentMode = .aspectFit
    ) {
        self.texture = texture
        self.contentMode = contentMode
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> TextureView {
        let device = texture?.device ?? MTLCreateSystemDefaultDevice()!
        let view = try! TextureView(device: device)
        context.coordinator.updateCommandQueue(for: device)
        view.commandQueue = context.coordinator.commandQueue
        view.preferredDrawableScale = displayScale
        view.textureContentMode = contentMode
        return view
    }

    public func updateUIView(_ view: TextureView, context: Context) {
        context.coordinator.updateCommandQueue(for: view.device)
        view.commandQueue = context.coordinator.commandQueue
        view.preferredDrawableScale = displayScale
        view.textureContentMode = contentMode
        view.layoutIfNeeded()
        view.texture = texture
        guard texture != nil,
            let commandBuffer = context.coordinator.commandQueue?.makeCommandBuffer()
        else { return }
        view.draw(in: commandBuffer)
        commandBuffer.commit()
    }

    public final class Coordinator {
        private var deviceRegistryID: UInt64?
        fileprivate var commandQueue: MTLCommandQueue?

        fileprivate func updateCommandQueue(for device: MTLDevice) {
            guard self.deviceRegistryID != device.registryID || self.commandQueue == nil else { return }
            self.deviceRegistryID = device.registryID
            self.commandQueue = device.makeCommandQueue()
        }
    }
}

#elseif os(macOS)

public struct TextureViewRepresentable: NSViewRepresentable {
    public let texture: MTLTexture?
    public var contentMode: TextureContentMode

    @Environment(\.displayScale) private var displayScale

    public init(
        texture: MTLTexture?,
        contentMode: TextureContentMode = .aspectFit
    ) {
        self.texture = texture
        self.contentMode = contentMode
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> TextureView {
        let device = texture?.device ?? MTLCreateSystemDefaultDevice()!
        let view = try! TextureView(device: device)
        context.coordinator.updateCommandQueue(for: device)
        view.commandQueue = context.coordinator.commandQueue
        view.preferredDrawableScale = displayScale
        view.textureContentMode = contentMode
        return view
    }

    public func updateNSView(_ view: TextureView, context: Context) {
        context.coordinator.updateCommandQueue(for: view.device)
        view.commandQueue = context.coordinator.commandQueue
        view.preferredDrawableScale = displayScale
        view.textureContentMode = contentMode
        view.layoutSubtreeIfNeeded()
        view.texture = texture
        guard texture != nil,
            let commandBuffer = context.coordinator.commandQueue?.makeCommandBuffer()
        else { return }
        view.draw(in: commandBuffer)
        commandBuffer.commit()
    }

    public final class Coordinator {
        private var deviceRegistryID: UInt64?
        fileprivate var commandQueue: MTLCommandQueue?

        fileprivate func updateCommandQueue(for device: MTLDevice) {
            guard self.deviceRegistryID != device.registryID || self.commandQueue == nil else { return }
            self.deviceRegistryID = device.registryID
            self.commandQueue = device.makeCommandQueue()
        }
    }
}

#endif
