/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Objective-C++ implementation bridging AudioProcessor to Swift.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

#import "AudioBridge.h"
#import "AudioProcessor.hpp"

@implementation AudioBridge {
    AudioProcessor *processor;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        processor = new AudioProcessor();
    }
    return self;
}

- (void)processBuffer:(const float *)buffer count:(int)count {
    processor->process(buffer, count);
}

- (simd_float4)getSmoothedMagnitudes {
    // Calls getBand() which does memory_order_relaxed atomic loads —
    // no heap allocation, safe to call from the render thread
    return simd_make_float4(
        processor->getBand(0),
        processor->getBand(1),
        processor->getBand(2),
        processor->getBand(3)
    );
}

- (void)dealloc {
    delete processor;
}

@end
