/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Objective-C bridge to expose C++ AudioProcessor to Swift.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

#import <Foundation/Foundation.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioBridge : NSObject

- (void)processBuffer:(const float *)buffer count:(int)count;

// Reads atomically from the processor — safe to call from any thread
- (simd_float4)getSmoothedMagnitudes;

@end

NS_ASSUME_NONNULL_END
