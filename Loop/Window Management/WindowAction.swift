//
//  WindowAction.swift
//  Loop
//
//  Created by Kai Azim on 2023-10-28.
//

import Defaults
import OSLog
import SwiftUI

struct WindowAction: Codable, Identifiable, Hashable, Equatable, Defaults.Serializable {
    var id: UUID

    init(
        _ direction: WindowDirection,
        keybind: Set<CGKeyCode>,
        name: String? = nil,
        unit: CustomWindowActionUnit? = nil,
        anchor: CustomWindowActionAnchor? = nil,
        width: Double? = nil,
        height: Double? = nil,
        xPoint: Double? = nil,
        yPoint: Double? = nil,
        positionMode: CustomWindowActionPositionMode? = nil,
        sizeMode: CustomWindowActionSizeMode? = nil,
        cycle: [WindowAction]? = nil
    ) {
        self.id = UUID()
        self.direction = direction
        self.keybind = keybind
        self.name = name
        self.unit = unit
        self.anchor = anchor
        self.width = width
        self.height = height
        self.positionMode = positionMode
        self.xPoint = xPoint
        self.yPoint = yPoint
        self.sizeMode = sizeMode
        self.cycle = cycle
    }

    init(_ direction: WindowDirection) {
        self.init(direction, keybind: [])
    }

    init(_ name: String? = nil, _ cycle: [WindowAction], _ keybind: Set<CGKeyCode> = []) {
        self.init(.cycle, keybind: keybind, name: name, cycle: cycle)
    }

    init(_ cycle: [WindowAction]) {
        self.init(nil, cycle)
    }

    var direction: WindowDirection
    var keybind: Set<CGKeyCode>

    // MARK: CUSTOM KEYBINDS

    var name: String?
    var unit: CustomWindowActionUnit?
    var anchor: CustomWindowActionAnchor?
    var sizeMode: CustomWindowActionSizeMode?
    var width: Double?
    var height: Double?
    var positionMode: CustomWindowActionPositionMode?
    var xPoint: Double?
    var yPoint: Double?

    var cycle: [WindowAction]?

    static let commonID = UUID()
    // Removes ID, keybind and name. This is useful when checking for equality between an otherwise identical keybind and radial menu action.
    func stripNonResizingProperties() -> WindowAction {
        var strippedAction = self
        strippedAction.id = WindowAction.commonID
        strippedAction.keybind = []
        strippedAction.name = nil

        if let cycle {
            strippedAction.cycle = cycle.map { $0.stripNonResizingProperties() }
        }

        return strippedAction
    }

    func getName() -> String {
        var result = ""

        if direction == .custom {
            result = if let name, !name.isEmpty {
                name
            } else {
                .init(localized: .init("Custom Keybind", defaultValue: "Custom Keybind"))
            }
        } else if direction == .cycle {
            result = if let name, !name.isEmpty {
                name
            } else {
                .init(localized: .init("Custom Cycle", defaultValue: "Custom Cycle"))
            }
        } else {
            result = direction.name
        }

        return result
    }

    var willManipulateExistingWindowFrame: Bool {
        direction.willAdjustSize || direction.willShrink || direction.willGrow || direction.willMove
    }

    static func getAction(for keybind: Set<CGKeyCode>) -> WindowAction? {
        for item in Defaults[.keybinds] where item.keybind == keybind {
            return item
        }
        return nil
    }

    func radialMenuAngle(window: Window?) -> Angle? {
        guard
            direction.frameMultiplyValues != nil,
            direction.hasRadialMenuAngle
        else {
            return nil
        }

        let frame = CGRect(origin: .zero, size: .init(width: 1, height: 1))
        let targetWindowFrame = getFrame(window: window, bounds: frame, disablePadding: true)
        let angle = frame.center.angle(to: targetWindowFrame.center)
        let result: Angle = .radians(angle) * -1

        return result.normalized()
    }

    /// Returns the frame for the specified window action within a given boundary.
    /// - Parameters:
    ///   - window: the window to be manipulated.
    ///   - bounds: the boundary within which the window should be manipulated.
    ///   - disablePadding: whether to disable padding. `true` when calculating non-AX-usage frames, such as for angle calculations in radial menu or in config UI.
    ///   - screen: the screen on which the bounds are located. Only used to determine if padding should be applied (see `getBounds()`).
    ///   - isPreview: ensures that when manipulating the preview window, the last target frame does not affect the actual resizing of the window.
    /// - Returns: the calculated frame for the specified window action.
    func getFrame(window: Window?, bounds: CGRect, disablePadding: Bool = false, screen: NSScreen? = nil, isPreview: Bool = false) -> CGRect {
        let noFrameActions: [WindowDirection] = [.noAction, .cycle, .minimize, .hide]
        guard !noFrameActions.contains(direction) else {
            return NSRect(origin: bounds.center, size: .zero)
        }

        if !willManipulateExistingWindowFrame {
            LoopManager.sidesToAdjust = nil
        }

        var bounds: CGRect = getBounds(from: bounds, disablePadding: disablePadding, screen: screen)
        var result: CGRect = calculateTargetFrame(direction, window, bounds, isPreview)

        if !disablePadding {
            // Convert rects to integers as that's what the AX API works with to move windows
            bounds = bounds.integerRect()
            result = result.integerRect()

            // If window can't be resized, center it within the already-resized frame.
            if let window, window.isResizable == false {
                result = window.frame.size
                    .center(inside: result)
                    .pushInside(bounds)
            }

            // Apply padding between windows
            if direction != .undo, direction != .initialFrame {
                result = applyInnerPadding(result, bounds)
            }

            // Store the last target frame. This is used when growing/shrinking windows
            // We only store it when disablePadding is false, as otherwise, it is going to be the preview window using this frame.
            LoopManager.lastTargetFrame = result
        }

        if result.size.width < 0 || result.size.height < 0 {
            result = CGRect(origin: bounds.center, size: .zero)
        }

        return result
    }
}

// MARK: - Window Frame Calculations

private extension WindowAction {
    func getBounds(from originalBounds: CGRect, disablePadding: Bool, screen: NSScreen?) -> CGRect {
        // Get padded bounds only if padding can be applied
        if !disablePadding && Defaults[.enablePadding],
           Defaults[.paddingMinimumScreenSize] == .zero || screen?.diagonalSize ?? .zero > Defaults[.paddingMinimumScreenSize] {
            getPaddedBounds(originalBounds)
        } else {
            originalBounds
        }
    }

    func calculateTargetFrame(_ direction: WindowDirection, _ window: Window?, _ bounds: CGRect, _ isPreview: Bool) -> CGRect {
        var result: CGRect = .zero

        if direction.frameMultiplyValues != nil {
            result = applyFrameMultiplyValues(bounds)

        } else if direction.willAdjustSize {
            // Return final frame of preview
            if Defaults[.previewVisibility], !isPreview {
                return LoopManager.lastTargetFrame
            }

            let frameToResizeFrom = LoopManager.lastTargetFrame

            result = calculateSizeAdjustment(frameToResizeFrom, bounds)

        } else if direction.willShrink || direction.willGrow {
            // Return final frame of preview
            if Defaults[.previewVisibility], !isPreview {
                return LoopManager.lastTargetFrame
            }

            // This allows for control over each side
            let frameToResizeFrom = LoopManager.lastTargetFrame

            // calculateSizeAdjustment() will read LoopManager.sidesToAdjust, but we compute them here
            switch direction {
            case .shrinkTop, .growTop:
                LoopManager.sidesToAdjust = .top
            case .shrinkBottom, .growBottom:
                LoopManager.sidesToAdjust = .bottom
            case .shrinkLeft, .growLeft:
                LoopManager.sidesToAdjust = .leading
            default:
                LoopManager.sidesToAdjust = .trailing
            }

            result = calculateSizeAdjustment(frameToResizeFrom, bounds)

        } else if direction.willMove {
            // Return final frame of preview
            if Defaults[.previewVisibility], !isPreview {
                return LoopManager.lastTargetFrame
            }

            let frameToResizeFrom = LoopManager.lastTargetFrame

            result = calculatePositionAdjustment(frameToResizeFrom)

        } else if direction == .custom {
            result = calculateCustomFrame(window, bounds)

        } else if direction == .center {
            result = calculateCenterFrame(window, bounds)

        } else if direction == .macOSCenter {
            result = calculateMacOSCenterFrame(window, bounds)

        } else if direction == .undo, let window {
            result = getLastActionFrame(window, bounds)

        } else if direction == .initialFrame, let window {
            result = getInitialFrame(window)
        } else if direction == .maximizeHeight, let window {
            result = CGRect(
                x: window.frame.minX,
                y: bounds.minY,
                width: window.frame.width,
                height: bounds.height
            )
        } else if direction == .maximizeWidth, let window {
            result = CGRect(
                x: bounds.minX,
                y: window.frame.minY,
                width: bounds.width,
                height: window.frame.height
            )
        }

        return result
    }

    func applyFrameMultiplyValues(_ bounds: CGRect) -> CGRect {
        guard let frameMultiplyValues = direction.frameMultiplyValues else {
            return .zero
        }

        return CGRect(
            x: bounds.origin.x + (bounds.width * frameMultiplyValues.minX),
            y: bounds.origin.y + (bounds.height * frameMultiplyValues.minY),
            width: bounds.width * frameMultiplyValues.width,
            height: bounds.height * frameMultiplyValues.height
        )
    }

    func calculateCustomFrame(_ window: Window?, _ bounds: CGRect) -> CGRect {
        var result = CGRect(origin: bounds.origin, size: .zero)

        // SIZE
        if let sizeMode, sizeMode == .preserveSize, let window {
            result.size = window.size

        } else if let sizeMode, sizeMode == .initialSize, let window {
            if let initialFrame = WindowRecords.getInitialFrame(for: window) {
                result.size = initialFrame.size
            }

        } else { // sizeMode would be custom
            switch unit {
            case .pixels:
                if window == nil {
                    let mainScreen = NSScreen.main ?? NSScreen.screens[0]
                    result.size.width = (CGFloat(width ?? .zero) / mainScreen.frame.width) * bounds.width
                    result.size.height = (CGFloat(height ?? .zero) / mainScreen.frame.height) * bounds.height
                } else {
                    result.size.width = width ?? .zero
                    result.size.height = height ?? .zero
                }
            default:
                if let width {
                    result.size.width = bounds.width * (width / 100.0)
                }

                if let height {
                    result.size.height = bounds.height * (height / 100.0)
                }
            }
        }

        // POSITION
        if let positionMode, positionMode == .coordinates {
            switch unit {
            case .pixels:
                if window == nil {
                    let mainScreen = NSScreen.main ?? NSScreen.screens[0]
                    result.origin.x = (CGFloat(xPoint ?? .zero) / mainScreen.frame.width) * bounds.width
                    result.origin.y = (CGFloat(yPoint ?? .zero) / mainScreen.frame.height) * bounds.height
                } else {
                    // Note that bounds are ignored deliberately here
                    result.origin.x += xPoint ?? .zero
                    result.origin.y += yPoint ?? .zero
                }
            default:
                if let xPoint {
                    result.origin.x += bounds.width * (xPoint / 100.0)
                }

                if let yPoint {
                    result.origin.y += bounds.height * (yPoint / 100.0)
                }
            }
        } else { // positionMode would be generic
            switch anchor {
            case .top:
                result.origin.x = bounds.midX - result.width / 2
            case .topRight:
                result.origin.x = bounds.maxX - result.width
            case .right:
                result.origin.x = bounds.maxX - result.width
                result.origin.y = bounds.midY - result.height / 2
            case .bottomRight:
                result.origin.x = bounds.maxX - result.width
                result.origin.y = bounds.maxY - result.height
            case .bottom:
                result.origin.x = bounds.midX - result.width / 2
                result.origin.y = bounds.maxY - result.height
            case .bottomLeft:
                result.origin.y = bounds.maxY - result.height
            case .left:
                result.origin.y = bounds.midY - result.height / 2
            case .center:
                result.origin.x = bounds.midX - result.width / 2
                result.origin.y = bounds.midY - result.height / 2
            case .macOSCenter:
                let yOffset = WindowEngine.getMacOSCenterYOffset(result.height, screenHeight: bounds.height)
                result.origin.x = bounds.midX - result.width / 2
                result.origin.y = (bounds.midY - result.height / 2) + yOffset
            default:
                break
            }
        }

        return result
    }

    func calculateCenterFrame(_ window: Window?, _ bounds: CGRect) -> CGRect {
        let windowSize: CGSize = if let window {
            window.size
        } else {
            .init(width: bounds.width / 2, height: bounds.height / 2)
        }

        return CGRect(
            origin: CGPoint(
                x: bounds.midX - (windowSize.width / 2),
                y: bounds.midY - (windowSize.height / 2)
            ),
            size: windowSize
        )
    }

    func calculateMacOSCenterFrame(_ window: Window?, _ bounds: CGRect) -> CGRect {
        let windowSize: CGSize = if let window {
            window.size
        } else {
            .init(width: bounds.width / 2, height: bounds.height / 2)
        }

        let yOffset = WindowEngine.getMacOSCenterYOffset(
            windowSize.height,
            screenHeight: bounds.height
        )

        return CGRect(
            origin: CGPoint(
                x: bounds.midX - (windowSize.width / 2),
                y: bounds.midY - (windowSize.height / 2) + yOffset
            ),
            size: windowSize
        )
    }

    func getLastActionFrame(_ window: Window, _ bounds: CGRect) -> CGRect {
        if let previousAction = WindowRecords.getLastAction(for: window) {
            print("Last action was \(previousAction.direction) (name: \(previousAction.name ?? "nil"))")
            return previousAction.getFrame(window: window, bounds: bounds)
        } else {
            print("Didn't find frame to undo; using current frame")
            return window.frame
        }
    }

    func getInitialFrame(_ window: Window) -> CGRect {
        if let initialFrame = WindowRecords.getInitialFrame(for: window) {
            return initialFrame
        } else {
            print("Didn't find initial frame; using current frame")
            return window.frame
        }
    }

    func calculateSizeAdjustment(_ frameToResizeFrom: CGRect, _ bounds: CGRect) -> CGRect {
        var result = frameToResizeFrom
        let totalBounds: Edge.Set = [.top, .bottom, .leading, .trailing]
        let step = Defaults[.sizeIncrement] * ((direction == .larger || direction.willGrow) ? -1 : 1)

        let padding = Defaults[.padding]
        let previewPadding = Defaults[.previewPadding]
        let totalHorizontalPadding = padding.left + padding.right
        let totalVerticalPadding = padding.totalTopPadding + padding.bottom
        let minWidth = totalHorizontalPadding + previewPadding + 100
        let minHeight = totalVerticalPadding + previewPadding + 100

        if LoopManager.sidesToAdjust == nil {
            let edgesTouchingBounds = frameToResizeFrom.getEdgesTouchingBounds(bounds)
            LoopManager.sidesToAdjust = totalBounds.subtracting(edgesTouchingBounds)
        }

        if let edgesToInset = LoopManager.sidesToAdjust {
            if edgesToInset.isEmpty || edgesToInset.contains(totalBounds) {
                result = result.inset(
                    by: step,
                    minSize: .init(
                        width: minWidth,
                        height: minHeight
                    )
                )
            } else {
                result = result.padding(edgesToInset, step)

                if result.width < minWidth {
                    result.size.width = minWidth
                    result.origin.x = frameToResizeFrom.midX - minWidth / 2
                }

                if result.height < minHeight {
                    result.size.height = minHeight
                    result.origin.y = frameToResizeFrom.midY - minHeight / 2
                }
            }
        }

        if result.size.approximatelyEqual(to: LoopManager.lastTargetFrame.size, tolerance: 2) {
            result = LoopManager.lastTargetFrame
        }

        return result
    }

    func calculatePositionAdjustment(_ frameToResizeFrom: CGRect) -> CGRect {
        var result = frameToResizeFrom

        if direction == .moveUp {
            result.origin.y -= Defaults[.sizeIncrement]
        } else if direction == .moveDown {
            result.origin.y += Defaults[.sizeIncrement]
        } else if direction == .moveRight {
            result.origin.x += Defaults[.sizeIncrement]
        } else if direction == .moveLeft {
            result.origin.x -= Defaults[.sizeIncrement]
        }

        return result
    }

    // This will apply padding to the bounds of the frame
    func getPaddedBounds(_ bounds: CGRect) -> CGRect {
        let padding = Defaults[.padding]

        var bounds = bounds
        bounds = bounds.padding(.top, padding.totalTopPadding)
        bounds = bounds.padding(.bottom, padding.bottom)
        bounds = bounds.padding(.leading, padding.left)
        bounds = bounds.padding(.trailing, padding.right)

        return bounds
    }

    // This will apply padding within the frame, in between windows
    func applyInnerPadding(_ windowFrame: CGRect, _ bounds: CGRect, _ screen: NSScreen? = nil) -> CGRect {
        guard !direction.willMove else {
            return windowFrame
        }

        var croppedWindowFrame = windowFrame.intersection(bounds)

        let paddingMinimumScreenSize = Defaults[.paddingMinimumScreenSize]
        if paddingMinimumScreenSize != .zero,
           screen?.diagonalSize ?? .zero < paddingMinimumScreenSize {
            return windowFrame
        }

        guard
            !willManipulateExistingWindowFrame,
            Defaults[.enablePadding]
        else {
            return croppedWindowFrame
        }

        let padding = Defaults[.padding]
        let halfPadding = padding.window / 2

        if direction == .macOSCenter,
           windowFrame.height >= bounds.height {
            croppedWindowFrame.origin.y = bounds.minY
            croppedWindowFrame.size.height = bounds.height
        }

        if direction == .center || direction == .macOSCenter {
            return croppedWindowFrame
        }

        if abs(croppedWindowFrame.minX - bounds.minX) > 1 {
            croppedWindowFrame = croppedWindowFrame.padding(.leading, halfPadding)
        }

        if abs(croppedWindowFrame.maxX - bounds.maxX) > 1 {
            croppedWindowFrame = croppedWindowFrame.padding(.trailing, halfPadding)
        }

        if abs(croppedWindowFrame.minY - bounds.minY) > 1 {
            croppedWindowFrame = croppedWindowFrame.padding(.top, halfPadding)
        }

        if abs(croppedWindowFrame.maxY - bounds.maxY) > 1 {
            croppedWindowFrame = croppedWindowFrame.padding(.bottom, halfPadding)
        }

        return croppedWindowFrame
    }
}
