import MetalTools
import simd

public enum TextureContentMode {
    case resize
    case aspectFill
    case aspectFit
}

#if os(iOS) || targetEnvironment(macCatalyst)

public class TextureView: UIView {

    // MARK: - Properties

    public var texture: MTLTexture? = nil {
        didSet {
            if let texture, texture.size != oldValue?.size {
                self.recalculateProjectionMatrix(using: texture.size)
            }
        }
    }

    public var device: MTLDevice { self.library.device }
    public var pixelFormat: MTLPixelFormat { self.metalLayer.pixelFormat }
    public var colorSpace: CGColorSpace? {
        get { self.metalLayer.colorspace }
        set { self.metalLayer.colorspace = newValue }
    }

    public var autoResizeDrawable: Bool = true {
        didSet {
            if self.autoResizeDrawable {
                self.setNeedsLayout()
            }
        }
    }

    public var drawableSize: CGSize {
        get { self.metalLayer.drawableSize }
        set { self.metalLayer.drawableSize = newValue }
    }

    public var textureContentMode: TextureContentMode = .aspectFill {
        didSet {
            if let texture = self.texture,
                self.textureContentMode != oldValue
            {
                self.recalculateProjectionMatrix(using: texture.size)
            }
        }
    }

    var commandQueue: MTLCommandQueue?

    var preferredDrawableScale: CGFloat? {
        didSet {
            guard self.preferredDrawableScale != oldValue else { return }
            self.metalLayer.contentsScale = self.resolvedDrawableScale
            self.setNeedsLayout()
        }
    }

    private let library: MTLLibrary
    private var renderPipelineState: MTLRenderPipelineState
    private let renderPassDescriptor = MTLRenderPassDescriptor()
    private var textureTransform = matrix_identity_float3x3

    public var metalLayer: CAMetalLayer {
        super.layer as! CAMetalLayer
    }

    // MARK: - Life Cycle

    public init(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) throws {
        self.library = try device.makeDefaultLibrary(bundle: .module)
        self.renderPipelineState = try Self.renderStateWithLibrary(
            self.library,
            pixelFormat: pixelFormat
        )
        super.init(frame: .zero)
        self.commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        guard let device = MTLCreateSystemDefaultDevice(),
            let library = try? device.makeDefaultLibrary(bundle: .module),
            let renderPipelineState = try? Self.renderStateWithLibrary(
                library,
                pixelFormat: .bgra8Unorm
            )
        else { return nil }
        self.library = library
        self.renderPipelineState = renderPipelineState
        super.init(coder: aDecoder)
        self.commonInit()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        if self.autoResizeDrawable, self.updateDrawableSizeIfNeeded() {
            self.requestRedrawIfPossible()
        }
    }

    override public class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    // MARK: - Setup

    private func commonInit() {
        self.metalLayer.device = self.device
        self.metalLayer.framebufferOnly = true
        self.metalLayer.contentsScale = self.resolvedDrawableScale

        self.renderPassDescriptor.colorAttachments[0].loadAction = .clear
        self.renderPassDescriptor.colorAttachments[0].clearColor = .clear

        self.backgroundColor = .clear
    }

    public func setPixelFormat(_ pixelFormat: MTLPixelFormat) throws {
        self.renderPipelineState = try Self.renderStateWithLibrary(
            self.library,
            pixelFormat: pixelFormat
        )
        self.metalLayer.pixelFormat = pixelFormat
    }

    // MARK: - Draw

    public func draw(
        additionalRenderCommands: ((MTLRenderCommandEncoder) -> Void)? = nil,
        fence: MTLFence? = nil,
        in commandBuffer: MTLCommandBuffer
    ) {
        autoreleasepool {
            guard let texture = self.texture,
                let drawable = self.metalLayer.nextDrawable()
            else { return }

            self.renderPassDescriptor.colorAttachments[0].texture = drawable.texture

            guard
                let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                    descriptor: self.renderPassDescriptor)
            else { return }

            self.draw(
                texture: texture,
                additionalRenderCommands: additionalRenderCommands,
                using: renderEncoder,
                fence: fence)
            renderEncoder.endEncoding()

            commandBuffer.present(drawable)
        }
    }

    private func draw(
        texture: MTLTexture,
        additionalRenderCommands: ((MTLRenderCommandEncoder) -> Void)? = nil,
        using renderEncoder: MTLRenderCommandEncoder,
        fence: MTLFence? = nil
    ) {
        if let fence {
            renderEncoder.waitForFence(fence, before: .fragment)
        }

        renderEncoder.setCullMode(.none)
        renderEncoder.setRenderPipelineState(self.renderPipelineState)

        renderEncoder.set(vertexValue: textureTransform, at: 0)
        renderEncoder.setFragmentTextures(texture)

        renderEncoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4
        )

        additionalRenderCommands?(renderEncoder)
    }

    // MARK: - Helpers

    private func recalculateProjectionMatrix(using textureSize: MTLSize) {
        guard
            self.metalLayer.drawableSize.width > 0,
            self.metalLayer.drawableSize.height > 0,
            textureSize.width > 0,
            textureSize.height > 0
        else {
            self.textureTransform = matrix_identity_float3x3
            return
        }

        let drawableAspectRatio: Float =
            .init(self.metalLayer.drawableSize.width)
            / .init(self.metalLayer.drawableSize.height)
        let textureAspectRatio: Float =
            .init(textureSize.width)
            / .init(textureSize.height)
        let normalizationValue = drawableAspectRatio / textureAspectRatio

        let normalizedTextureWidth: Float
        let normalizedTextureHeight: Float

        switch self.textureContentMode {
        case .resize:
            normalizedTextureWidth = 1.0
            normalizedTextureHeight = 1.0
        case .aspectFill:
            normalizedTextureWidth =
                normalizationValue < 1.0
                ? 1.0 / normalizationValue
                : 1.0
            normalizedTextureHeight =
                normalizationValue < 1.0
                ? 1.0
                : normalizationValue
        case .aspectFit:
            normalizedTextureWidth =
                normalizationValue > 1.0
                ? 1 / normalizationValue
                : 1.0
            normalizedTextureHeight =
                normalizationValue > 1.0
                ? 1.0
                : normalizationValue
        }

        self.textureTransform[0][0] = normalizedTextureWidth
        self.textureTransform[1][1] = normalizedTextureHeight
    }

    private var resolvedDrawableScale: CGFloat {
        self.preferredDrawableScale ?? self.contentScaleFactor
    }

    @discardableResult
    private func updateDrawableSizeIfNeeded() -> Bool {
        self.metalLayer.contentsScale = self.resolvedDrawableScale

        var size = self.bounds.size
        size.width *= self.resolvedDrawableScale
        size.height *= self.resolvedDrawableScale

        guard self.metalLayer.drawableSize != size else { return false }

        self.metalLayer.drawableSize = size
        if let texture = self.texture {
            self.recalculateProjectionMatrix(using: texture.size)
        }
        return true
    }

    private func requestRedrawIfPossible() {
        guard let texture = self.texture,
            let commandQueue = self.commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        self.texture = texture
        self.draw(in: commandBuffer)
        commandBuffer.commit()
    }

    // MARK: - Pipeline State

    public static let vertexFunctionName = "textureViewVertex"
    public static let fragmentFunctionName = "textureViewFragment"

    private static func renderStateWithLibrary(
        _ library: MTLLibrary,
        pixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        let renderStateDescriptor = MTLRenderPipelineDescriptor()
        renderStateDescriptor.label = "Texture View"
        renderStateDescriptor.vertexFunction = library.makeFunction(
            name: Self.vertexFunctionName)
        renderStateDescriptor.fragmentFunction = library.makeFunction(
            name: Self.fragmentFunctionName)
        renderStateDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        renderStateDescriptor.colorAttachments[0].isBlendingEnabled = false
        return try library.device.makeRenderPipelineState(
            descriptor: renderStateDescriptor)
    }
}

#elseif os(macOS)

public class TextureView: NSView {

    // MARK: - Properties

    public var texture: MTLTexture? = nil {
        didSet {
            if let texture, texture.size != oldValue?.size {
                self.recalculateProjectionMatrix(using: texture.size)
            }
        }
    }

    public var device: MTLDevice { self.library.device }
    public var pixelFormat: MTLPixelFormat { self.metalLayer.pixelFormat }
    public var colorSpace: CGColorSpace? {
        get { self.metalLayer.colorspace }
        set { self.metalLayer.colorspace = newValue }
    }

    public var autoResizeDrawable: Bool = true {
        didSet {
            if self.autoResizeDrawable {
                self.needsLayout = true
            }
        }
    }

    public var drawableSize: CGSize {
        get { self.metalLayer.drawableSize }
        set { self.metalLayer.drawableSize = newValue }
    }

    public var textureContentMode: TextureContentMode = .aspectFill {
        didSet {
            if let texture = self.texture,
                self.textureContentMode != oldValue
            {
                self.recalculateProjectionMatrix(using: texture.size)
            }
        }
    }

    var commandQueue: MTLCommandQueue?

    var preferredDrawableScale: CGFloat? {
        didSet {
            guard self.preferredDrawableScale != oldValue else { return }
            self.metalLayer.contentsScale = self.resolvedDrawableScale
            self.needsLayout = true
        }
    }

    private let library: MTLLibrary
    private var renderPipelineState: MTLRenderPipelineState
    private let renderPassDescriptor = MTLRenderPassDescriptor()
    private var textureTransform = matrix_identity_float3x3

    public var metalLayer: CAMetalLayer {
        self.layer as! CAMetalLayer
    }

    // MARK: - Life Cycle

    public init(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) throws {
        self.library = try device.makeDefaultLibrary(bundle: .module)
        self.renderPipelineState = try Self.renderStateWithLibrary(
            self.library,
            pixelFormat: pixelFormat
        )
        super.init(frame: .zero)
        self.commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        guard let device = MTLCreateSystemDefaultDevice(),
            let library = try? device.makeDefaultLibrary(bundle: .module),
            let renderPipelineState = try? Self.renderStateWithLibrary(
                library,
                pixelFormat: .bgra8Unorm
            )
        else { return nil }
        self.library = library
        self.renderPipelineState = renderPipelineState
        super.init(coder: aDecoder)
        self.commonInit()
    }

    public override func makeBackingLayer() -> CALayer {
        CAMetalLayer()
    }

    public override func layout() {
        super.layout()

        if self.autoResizeDrawable, self.updateDrawableSizeIfNeeded() {
            self.requestRedrawIfPossible()
        }
    }

    // MARK: - Setup

    private func commonInit() {
        self.wantsLayer = true
        self.metalLayer.device = self.device
        self.metalLayer.framebufferOnly = true
        self.metalLayer.contentsScale = self.resolvedDrawableScale

        self.renderPassDescriptor.colorAttachments[0].loadAction = .clear
        self.renderPassDescriptor.colorAttachments[0].clearColor = .clear

        self.layer?.backgroundColor = .clear
    }

    public func setPixelFormat(_ pixelFormat: MTLPixelFormat) throws {
        self.renderPipelineState = try Self.renderStateWithLibrary(
            self.library,
            pixelFormat: pixelFormat
        )
        self.metalLayer.pixelFormat = pixelFormat
    }

    // MARK: - Draw

    public func draw(
        additionalRenderCommands: ((MTLRenderCommandEncoder) -> Void)? = nil,
        fence: MTLFence? = nil,
        in commandBuffer: MTLCommandBuffer
    ) {
        autoreleasepool {
            guard let texture = self.texture,
                let drawable = self.metalLayer.nextDrawable()
            else { return }

            self.renderPassDescriptor.colorAttachments[0].texture = drawable.texture

            guard
                let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                    descriptor: self.renderPassDescriptor)
            else { return }

            self.draw(
                texture: texture,
                additionalRenderCommands: additionalRenderCommands,
                using: renderEncoder,
                fence: fence)
            renderEncoder.endEncoding()

            commandBuffer.present(drawable)
        }
    }

    private func draw(
        texture: MTLTexture,
        additionalRenderCommands: ((MTLRenderCommandEncoder) -> Void)? = nil,
        using renderEncoder: MTLRenderCommandEncoder,
        fence: MTLFence? = nil
    ) {
        if let fence {
            renderEncoder.waitForFence(fence, before: .fragment)
        }

        renderEncoder.setCullMode(.none)
        renderEncoder.setRenderPipelineState(self.renderPipelineState)

        renderEncoder.set(vertexValue: textureTransform, at: 0)
        renderEncoder.setFragmentTextures(texture)

        renderEncoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4
        )

        additionalRenderCommands?(renderEncoder)
    }

    // MARK: - Helpers

    private func recalculateProjectionMatrix(using textureSize: MTLSize) {
        guard
            self.metalLayer.drawableSize.width > 0,
            self.metalLayer.drawableSize.height > 0,
            textureSize.width > 0,
            textureSize.height > 0
        else {
            self.textureTransform = matrix_identity_float3x3
            return
        }

        let drawableAspectRatio: Float =
            .init(self.metalLayer.drawableSize.width)
            / .init(self.metalLayer.drawableSize.height)
        let textureAspectRatio: Float =
            .init(textureSize.width)
            / .init(textureSize.height)
        let normalizationValue = drawableAspectRatio / textureAspectRatio

        let normalizedTextureWidth: Float
        let normalizedTextureHeight: Float

        switch self.textureContentMode {
        case .resize:
            normalizedTextureWidth = 1.0
            normalizedTextureHeight = 1.0
        case .aspectFill:
            normalizedTextureWidth =
                normalizationValue < 1.0
                ? 1.0 / normalizationValue
                : 1.0
            normalizedTextureHeight =
                normalizationValue < 1.0
                ? 1.0
                : normalizationValue
        case .aspectFit:
            normalizedTextureWidth =
                normalizationValue > 1.0
                ? 1 / normalizationValue
                : 1.0
            normalizedTextureHeight =
                normalizationValue > 1.0
                ? 1.0
                : normalizationValue
        }

        self.textureTransform[0][0] = normalizedTextureWidth
        self.textureTransform[1][1] = normalizedTextureHeight
    }

    private var resolvedDrawableScale: CGFloat {
        self.preferredDrawableScale
            ?? self.window?.backingScaleFactor
            ?? self.window?.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1.0
    }

    @discardableResult
    private func updateDrawableSizeIfNeeded() -> Bool {
        self.metalLayer.contentsScale = self.resolvedDrawableScale

        var size = self.bounds.size
        size.width *= self.resolvedDrawableScale
        size.height *= self.resolvedDrawableScale

        guard self.metalLayer.drawableSize != size else { return false }

        self.metalLayer.drawableSize = size
        if let texture = self.texture {
            self.recalculateProjectionMatrix(using: texture.size)
        }
        return true
    }

    private func requestRedrawIfPossible() {
        guard let texture = self.texture,
            let commandQueue = self.commandQueue,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        self.texture = texture
        self.draw(in: commandBuffer)
        commandBuffer.commit()
    }

    // MARK: - Pipeline State

    public static let vertexFunctionName = "textureViewVertex"
    public static let fragmentFunctionName = "textureViewFragment"

    private static func renderStateWithLibrary(
        _ library: MTLLibrary,
        pixelFormat: MTLPixelFormat
    ) throws -> MTLRenderPipelineState {
        let renderStateDescriptor = MTLRenderPipelineDescriptor()
        renderStateDescriptor.label = "Texture View"
        renderStateDescriptor.vertexFunction = library.makeFunction(
            name: Self.vertexFunctionName)
        renderStateDescriptor.fragmentFunction = library.makeFunction(
            name: Self.fragmentFunctionName)
        renderStateDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        renderStateDescriptor.colorAttachments[0].isBlendingEnabled = false
        return try library.device.makeRenderPipelineState(
            descriptor: renderStateDescriptor)
    }
}

#endif
