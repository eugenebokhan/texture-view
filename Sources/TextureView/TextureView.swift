#if os(iOS) || targetEnvironment(macCatalyst)

import MetalTools
import simd

@available(macOS, unavailable)
public class TextureView: UIView {

    // MARK: - Type Definitions

    public enum TextureContentMode {
        case resize
        case aspectFill
        case aspectFit
    }

    public var texture: MTLTexture? = nil {
        didSet {
            if let texture, texture.size != oldValue?.size {
                self.recalculateProjectionMatrix(using: texture.size)
            }
        }
    }

    public var device: MTLDevice { self.library.device }
    public var pixelFormat: MTLPixelFormat { self.layer.pixelFormat }
    public var colorSpace: CGColorSpace? {
        get { self.layer.colorspace }
        set { self.layer.colorspace = newValue }
    }

    public var autoResizeDrawable: Bool = true {
        didSet {
            if self.autoResizeDrawable {
                self.setNeedsLayout()
            }
        }
    }

    public var drawableSize: CGSize {
        get { return self.layer.drawableSize }
        set { self.layer.drawableSize = newValue }
    }

    public var textureContentMode: TextureContentMode = .aspectFill {
        didSet {
            if let texture = self.texture,
               self.textureContentMode != oldValue {
                self.recalculateProjectionMatrix(using: texture.size)
            }
        }
    }

    private let library: MTLLibrary
    private var renderPipelineState: MTLRenderPipelineState
    private let renderPassDescriptor = MTLRenderPassDescriptor()
    private var textureTransform = matrix_identity_float3x3

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

        if self.autoResizeDrawable {
            var size = self.bounds.size
            size.width *= self.contentScaleFactor
            size.height *= self.contentScaleFactor

            self.layer.drawableSize = size
        }
    }

    override public var layer: CAMetalLayer {
        return super.layer as! CAMetalLayer
    }

    override public class var layerClass: AnyClass {
        return CAMetalLayer.self
    }

    // MARK: - Setup

    private func commonInit() {
        self.layer.device = self.device
        self.layer.framebufferOnly = true

        self.renderPassDescriptor.colorAttachments[0].loadAction = .clear
        self.renderPassDescriptor.colorAttachments[0].clearColor = .clear

        self.backgroundColor = .clear
    }

    public func setPixelFormat(_ pixelFormat: MTLPixelFormat) throws {
        self.renderPipelineState = try Self.renderStateWithLibrary(
            self.library,
            pixelFormat: pixelFormat
        )
        self.layer.pixelFormat = pixelFormat
    }

    // MARK: - Helpers

    private func recalculateProjectionMatrix(using textureSize: MTLSize) {
        let drawableAspectRatio: Float = .init(self.layer.drawableSize.width)
                                       / .init(self.layer.drawableSize.height)
        let textureAspectRatio: Float = .init(textureSize.width)
                                      / .init(textureSize.height)
        let normalizationValue = drawableAspectRatio / textureAspectRatio

        let normalizedTextureWidth: Float
        let normalizedTextureHeight: Float

        switch self.textureContentMode {
        case .resize:
            normalizedTextureWidth = 1.0
            normalizedTextureHeight = 1.0
        case .aspectFill:
            normalizedTextureWidth = normalizationValue < 1.0
                                                        ? 1.0 / normalizationValue
                                                        : 1.0
            normalizedTextureHeight = normalizationValue < 1.0
                                                         ? 1.0
                                                         : normalizationValue
        case .aspectFit:
            normalizedTextureWidth = normalizationValue > 1.0
                                                        ? 1 / normalizationValue
                                                        : 1.0
            normalizedTextureHeight = normalizationValue > 1.0
                                                         ? 1.0
                                                         : normalizationValue
        }

        self.textureTransform[0][0] = normalizedTextureWidth
        self.textureTransform[1][1] = normalizedTextureHeight
    }

    private func normlizedTextureSize(from textureSize: MTLSize) -> SIMD2<Float> {
        let drawableAspectRatio: Float = .init(self.layer.drawableSize.width)
                                       / .init(self.layer.drawableSize.height)
        let textureAspectRatio: Float = .init(textureSize.width)
                                      / .init(textureSize.height)
        let normlizedTextureWidth = drawableAspectRatio < textureAspectRatio
                                  ? 1.0
                                  : drawableAspectRatio / textureAspectRatio
        let normlizedTextureHeight = drawableAspectRatio > textureAspectRatio
                                   ? 1.0
                                   : drawableAspectRatio / textureAspectRatio
        return .init(x: normlizedTextureWidth,
                     y: normlizedTextureHeight)
    }

    // MARK: Draw

    /// Draw a texture
    ///
    /// - Note: This method should be called on main thread only.
    ///
    /// - Parameters:
    ///   - texture: texture to draw
    ///   - additionalRenderCommands: render commands to execute after texture draw.
    ///   - fence: metal fence.
    ///   - commandBuffer: command buffer to put the work in.
    public func draw(
        additionalRenderCommands: ((MTLRenderCommandEncoder) -> Void)? = nil,
        fence: MTLFence? = nil,
        in commandBuffer: MTLCommandBuffer
    ) {
        // From https://developer.apple.com/documentation/quartzcore/cametallayer#3385893
        // “The layer reuses a drawable only if it isn’t onscreen and there are no strong references to it.”
        autoreleasepool {
            guard let texture = self.texture,
                  let drawable = self.layer.nextDrawable()
            else { return }

            self.renderPassDescriptor.colorAttachments[0].texture = drawable.texture

            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.renderPassDescriptor)
            else { return }

            self.draw(texture: texture,
                      in: drawable,
                      additionalRenderCommands: additionalRenderCommands,
                      using: renderEncoder,
                      fence: fence)
            renderEncoder.endEncoding()

            commandBuffer.present(drawable)
        }
    }

    private func draw(texture: MTLTexture,
                      in drawable: CAMetalDrawable,
                      additionalRenderCommands: ((MTLRenderCommandEncoder) -> Void)? = nil,
                      using renderEncoder: MTLRenderCommandEncoder,
                      fence: MTLFence? = nil) {
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

    // MARK - Pipeline State Init

    public static let vertexFunctionName = "textureViewVertex"
    public static let fragmentFunctionName = "textureViewFragment"

    private static func renderStateWithLibrary(_ library: MTLLibrary,
                                               pixelFormat: MTLPixelFormat) throws -> MTLRenderPipelineState {
        let renderStateDescriptor = MTLRenderPipelineDescriptor()
        renderStateDescriptor.label = "Texture View"
        renderStateDescriptor.vertexFunction = library.makeFunction(name: Self.vertexFunctionName)
        renderStateDescriptor.fragmentFunction = library.makeFunction(name: Self.fragmentFunctionName)
        renderStateDescriptor.colorAttachments[0].pixelFormat = pixelFormat
        renderStateDescriptor.colorAttachments[0].isBlendingEnabled = false

        return try library.device.makeRenderPipelineState(descriptor: renderStateDescriptor)
    }

}

#endif
