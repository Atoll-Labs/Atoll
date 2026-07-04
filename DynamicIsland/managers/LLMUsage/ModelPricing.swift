/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

/// Utility to resolve LLM model pricing dynamically
struct ModelPricing {
    /// Resolves prompt and completion rates for a given model
    /// Rates are per 1M tokens or as defined by the pricing.json structure
    static func resolveRates(for modelId: String) -> (prompt: Double, completion: Double) {
        // Try to get dynamic rates from the manager
        if let dynamicRates = ModelPricingManager.shared.getPricing(for: modelId) {
            return dynamicRates
        }
        
        // Hardcoded fallbacks for known models if manager is not yet populated
        switch modelId {
        case "anthropic/claude-3-opus":
            return (0.000015, 0.000075)
        case "anthropic/claude-3-5-sonnet", "claude-3-5-sonnet":
            return (0.000003, 0.000015)
        case "anthropic/claude-3-haiku", "claude-3-haiku":
            return (0.00000025, 0.00000125)
        case "openai/gpt-4o", "gpt-4o":
            return (0.000005, 0.000015)
        case "openai/gpt-4o-mini", "gpt-4o-mini":
            return (0.00000015, 0.0000006)
        default:
            // Default low-cost fallback
            return (0.000002, 0.000002)
        }
    }
}
