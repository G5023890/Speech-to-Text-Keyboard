// VITypography.swift
// VoiceInputApp – Design System Typography
//
// Goals:
// - Apple-like vertical rhythm
// - Stable sizes for settings screens
// - Keep it minimal: only what we actually use

import SwiftUI

enum VITypography {

    // MARK: - Titles / Section headers

    /// Used for page titles like "Настройки" (if you render one in-content)
    static let pageTitle: Font = .system(size: 20, weight: .semibold)

    /// Used for SettingsSection titles like "Общие", "Модель", "Качество"
    static let sectionTitle: Font = .system(size: 13, weight: .semibold)

    // MARK: - Rows / Body

    /// Default row label font (left side of SettingsRow)
    static let rowLabel: Font = .system(size: 13, weight: .regular)

    /// Right side value (picker value, shortcut, etc.)
    static let rowValue: Font = .system(size: 13, weight: .regular)

    /// Secondary helper text below a row (small note)
    static let rowHint: Font = .system(size: 11, weight: .regular)

    // MARK: - Stats

    /// Used for big values inside StatsCard
    static let statsValue: Font = .system(size: 20, weight: .semibold)

    /// Small header inside StatsCard ("Сегодня", "Неделя")
    static let statsTitle: Font = .system(size: 11, weight: .semibold)

    /// Subtitle inside StatsCard (e.g. "934 слова")
    static let statsSubtitle: Font = .system(size: 11, weight: .regular)

    // MARK: - Monospaced (Shortcuts / Technical tokens)

    static let monoCapsule: Font = .system(size: 12, weight: .medium, design: .monospaced)
}