//
//  AlphaFrameFilter.metal
//  MyTransparentVideoExample
//
//  Created by Quentin Fasquel on 22/03/2020.
//

#include <metal_stdlib>
#include <CoreImage/CoreImage.h> // Includes CIKernelMetalLib.h

using namespace metal;
using namespace coreimage;

extern "C" {

/**
 * Alpha blending filter that combines a source texture with a mask.
 * Opacity is floored to zero if below a fixed threshold (0.5).
 */
float4 alphaFrame(texture2d<float, access::sample> source,
                  texture2d<float, access::sample> mask,
                  sampler s) {
    // Sample the source and mask textures
    float4 color = source.sample(s, source.sample_position());
    float opacity = mask.sample(s, mask.sample_position()).r;

    // Apply the fixed opacity threshold (0.5)
    float flooredOpacity = select(0.0f, opacity, opacity > 0.5f);

    // Return the final color with adjusted alpha
    return float4(color.rgb, flooredOpacity);
}
}
