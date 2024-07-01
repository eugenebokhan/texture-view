# TextureView

TextureView is a Swift package that provides an efficient way to display Metal textures in iOS applications. It offers a customizable UIView subclass that can render Metal textures with various content modes and supports additional render commands.

## Features

- Display Metal textures in a UIView
- Support for different texture content modes (resize, aspect fill, aspect fit)
- Customizable pixel format
- Automatic drawable resizing
- Support for additional render commands
- Metal performance optimizations

## Requirements

- iOS 13.0+
- Swift 5.9+

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(
        url: "https://github.com/eugenebokhan/TextureView.git",
        .upToNextMajor(from: "1.1.0")
    )
]
```

## Usage

### Basic Setup

1. Import the module:

```swift
import TextureView
```

2. Create a TextureView instance:

```swift
let device = MTLCreateSystemDefaultDevice()!
let textureView = try TextureView(device: device)
```

3. Add the view to your view hierarchy:

```swift
view.addSubview(textureView)
```

4. Set a texture to display:

```swift
textureView.texture = yourMTLTexture
```

### Customization

#### Texture Content Mode

You can change how the texture is displayed within the view:

```swift
textureView.textureContentMode = .aspectFit
```

Available modes are:
- `.resize`: Stretches or shrinks the texture to fill the view
- `.aspectFill`: Scales the texture to fill the view while maintaining aspect ratio
- `.aspectFit`: Scales the texture to fit within the view while maintaining aspect ratio

#### Pixel Format

Change the pixel format of the view's drawable:

```swift
try textureView.setPixelFormat(.bgra8Unorm_srgb)
```

#### Auto Resize Drawable

Enable or disable automatic resizing of the drawable when the view's bounds change:

```swift
textureView.autoResizeDrawable = false
```

### Drawing

To draw the texture, call the `draw` method within your render loop:

```swift
let commandBuffer = commandQueue.makeCommandBuffer()!
textureView.draw(in: commandBuffer)
commandBuffer.commit()
```

You can also provide additional render commands:

```swift
textureView.draw(
    additionalRenderCommands: { encoder in
        // Your additional render commands here
    }, 
    in: commandBuffer
)
```

## Advanced Usage

### Performance Considerations

- The view uses `CAMetalLayer` for efficient rendering.
- It supports the use of Metal fences for synchronization.
- The drawable is reused when possible to improve performance.

## License

TextureView is licensed under [MIT license](LICENSE).
