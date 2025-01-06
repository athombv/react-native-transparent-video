//
//  ChromaKeyFilter.swift
//  MyTransparentVideoExample
//
//  Created by Quentin on 27/10/2017.
//  Copyright © 2017 Quentin Fasquel. All rights reserved.
//

import CoreImage

typealias AlphaFrameFilterError = AlphaFrameFilter.Error

final class AlphaFrameFilter: CIFilter {

    enum Error: Swift.Error {
        /// Thrown when `CIBlendWithMask` filter is not found in `builtInFilter` rendering mode.
        case buildInFilterNotFound
        /// Thrown when the extents of `inputImage` and `maskImage` are not compatible.
        case incompatibleExtents
        /// Thrown when kernel initialization fails in `colorKernel` or `metalKernel` rendering modes.
        case invalidKernel
        /// Thrown when either `inputImage` or `maskImage` is missing.
        case invalidParameters
        /// Thrown in unexpected situations when the output image is `nil`.
        case unknown
    }

    private(set) var inputImage: CIImage?
    private(set) var maskImage: CIImage?
    private(set) var outputError: Swift.Error?

    private let renderingMode: RenderingMode

    required init(renderingMode: RenderingMode) {
        self.renderingMode = renderingMode
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var outputImage: CIImage? {
        // Validate input and mask images before rendering
        guard let inputImage = inputImage, let maskImage = maskImage else {
            outputError = Error.invalidParameters
            return nil
        }

        // Ensure both images have the same extent
        guard inputImage.extent == maskImage.extent else {
            outputError = Error.incompatibleExtents
            return nil
        }

        outputError = nil
        return render(using: renderingMode, inputImage: inputImage, maskImage: maskImage)
    }

    func process(_ inputImage: CIImage, mask maskImage: CIImage) throws -> CIImage {
        self.inputImage = inputImage
        self.maskImage = maskImage

        guard let outputImage = self.outputImage else {
            throw outputError ?? Error.unknown
        }

        return outputImage
    }

    // MARK: - Rendering

    enum RenderingMode {
        case builtInFilter
        case colorKernel
        case metalKernel
    }

    private static var colorKernel: CIColorKernel? = {
        // Deprecated API: init(source:) in iOS 12.0, silent due to preprocessor macro `CI_SILENCE_GL_DEPRECATION`
        return CIColorKernel(source: """
kernel vec4 alphaFrame(__sample s, __sample m) {
    return vec4( s.rgb, m.r );
}
""")
    }()

    private static var metalKernelError: Swift.Error?
    private static var metalKernel: CIKernel? = {
        do {
            return try CIKernel(functionName: "alphaFrame")
        } catch {
            metalKernelError = error
            return nil
        }
    }()

    private func render(using renderingMode: RenderingMode, inputImage: CIImage, maskImage: CIImage) -> CIImage? {
        switch renderingMode {

        case .builtInFilter:
            guard let filter = CIFilter(name: "CIBlendWithMask") else {
                outputError = Error.buildInFilterNotFound
                return nil
            }

            let outputExtent = inputImage.extent
            let backgroundImage = CIImage(color: .clear).cropped(to: outputExtent)
            filter.setValue(backgroundImage, forKey: kCIInputBackgroundImageKey)
            filter.setValue(inputImage, forKey: kCIInputImageKey)
            filter.setValue(maskImage, forKey: kCIInputMaskImageKey)
            return filter.outputImage

        case .colorKernel:
            // Check for valid kernel before using it
            guard let colorKernel = Self.colorKernel else {
                outputError = Error.invalidKernel
                return nil
            }

            let outputExtent = inputImage.extent
            let arguments = [inputImage, maskImage]
            return colorKernel.apply(extent: outputExtent, arguments: arguments)

        case .metalKernel:
            // Check for valid kernel before applying
            guard let metalKernel = Self.metalKernel else {
                outputError = Self.metalKernelError ?? Error.invalidKernel
                return nil
            }

            let outputExtent = inputImage.extent
            let roiCallback: CIKernelROICallback = { _, rect in rect }
            let arguments = [inputImage, maskImage]
            return metalKernel.apply(extent: outputExtent, roiCallback: roiCallback, arguments: arguments)
        }
    }
}
