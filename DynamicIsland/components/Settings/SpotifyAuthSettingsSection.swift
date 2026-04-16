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

import AppKit
import Defaults
import SwiftUI

struct SpotifyAuthSettingsSection: View {
    @Default(.spotifySPDCCookie) private var spotifySPDCCookie
    @ObservedObject private var spotifyAuthManager = SpotifyAuthManager.shared

    private var hasCookie: Bool {
        !SpotifyAuthManager.sanitizeCookie(spotifySPDCCookie).isEmpty
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Paste the `sp_dc` cookie from your logged-in Spotify web session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("sp_dc cookie", text: $spotifySPDCCookie, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .lineLimit(2...4)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(spotifyAuthManager.isAuthenticated ? Color.green : (hasCookie ? Color.orange : Color.secondary))
                    .frame(width: 8, height: 8)

                Text(spotifyAuthManager.sessionStatusText)
                    .foregroundStyle(.secondary)
            }

            if let authErrorMessage = spotifyAuthManager.authErrorMessage, !authErrorMessage.isEmpty {
                Text(authErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Paste from Clipboard") {
                    pasteCookieFromClipboard()
                }

                Button(spotifyAuthManager.isAuthorizing ? "Validating..." : "Validate Cookie") {
                    spotifySPDCCookie = SpotifyAuthManager.sanitizeCookie(spotifySPDCCookie)
                    Task {
                        await spotifyAuthManager.validateSession()
                    }
                }
                .disabled(!hasCookie || spotifyAuthManager.isAuthorizing)

                Button("Clear") {
                    spotifySPDCCookie = ""
                    spotifyAuthManager.clearSession()
                }
                .disabled(!hasCookie && !spotifyAuthManager.isAuthenticated)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("How to get it:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("1. Open Spotify in a browser and log in")
                    .font(.caption)
                Text("2. Developer Tools -> Application/Storage -> Cookies -> https://open.spotify.com")
                    .font(.caption)
                Text("3. Copy the value of `sp_dc` and paste it here")
                    .font(.caption)

                HStack(spacing: 12) {
                    Link("Open Spotify Web Player", destination: URL(string: "https://open.spotify.com")!)
                    Link("Method source", destination: URL(string: "https://github.com/Paxsenix0/Spotify-Canvas-API")!)
                }
                .font(.caption)
            }
            .padding(.top, 2)
        } header: {
            Text("Spotify Canvas Session")
        } footer: {
            Text("Atoll uses the local `sp_dc` cookie only to request Spotify's internal web-player token and fetch the matching Canvas for the current track.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func pasteCookieFromClipboard() {
        guard let clipboardText = NSPasteboard.general.string(forType: .string) else { return }
        spotifySPDCCookie = SpotifyAuthManager.sanitizeCookie(clipboardText)
    }
}
