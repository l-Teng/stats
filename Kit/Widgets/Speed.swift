//
//  Speed.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 24/05/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa

public class SpeedWidget: WidgetWrapper {
    private var icon: String = "dots"
    private var valueState: Bool = true
    private var unitsState: Bool = true
    private var monochromeState: Bool = false
    private var valueColorState: String = "none"
    private var iconColorState: String = "default"
    private var valueAlignmentState: String = "right"
    private var modeState: String = "twoRows"
    private var iconAlignmentState: String = "left"
    private var displayValueState: String = "oi"
    
    private var inputColorState: SColor = .secondBlue
    private var outputColorState: SColor = .secondRed
    
    private var symbols: (input: String, output: String) = ("I", "O")
    private var words: (input: String, output: String) = ("Input", "Output")
    
    private var inputValue: Int64 = 0
    private var outputValue: Int64 = 0
    
    private var width: CGFloat = 40
    
    private var valueColorView: NSPopUpButton? = nil
    private var valueAlignmentView: NSPopUpButton? = nil
    private var iconAlignmentView: NSPopUpButton? = nil
    private var iconColorView: NSPopUpButton? = nil
    private var displayModeView: NSPopUpButton? = nil
    
    // MARK: - Network menu-bar speed formatting (Huorong-style)
    // Fixed-width display so the status item does not jump when digits change.
    // Format always keeps one decimal: "2.0 K/s", "12.3 K/s", "8.7 M/s".
    // No reserved arrow slot — width is text-only regardless of pictogram.
    
    private let networkValueFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    private let networkUnitFont = NSFont.systemFont(ofSize: 8, weight: .regular)
    /// Widest expected line with units: "999.9 K/s" (covers K/s and M/s)
    private let networkFixedTemplateWithUnits = "999.9 K/s"
    private let networkFixedTemplateNoUnits = "999.9"
    /// Crop empty space on the left only (right edge of text stays); does not shrink the right side.
    private let networkLeftTrim: CGFloat = 4
    
    private var isNetworkModule: Bool {
        self.title == ModuleType.network.stringValue
    }
    
    /// Pure black (light) / pure white (dark).
    private var networkMonoColor: NSColor {
        let isDark = self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? NSColor.white : NSColor.black
    }
    
    /// Fixed text column width — independent of the current speed value.
    private var networkFixedTextWidth: CGFloat {
        if self.unitsState {
            let attr = NSMutableAttributedString(string: self.networkFixedTemplateWithUnits, attributes: [
                .font: self.networkValueFont
            ])
            attr.addAttribute(
                .font,
                value: self.networkUnitFont,
                range: NSRange(location: attr.length - 3, length: 3)
            )
            return ceil(attr.size().width) - 2
        }
        let size = (self.networkFixedTemplateNoUnits as NSString).size(withAttributes: [
            .font: self.networkValueFont
        ])
        return ceil(size.width) - 2
    }
    
    private func networkSpeedParts(_ bytes: Int64) -> (number: String, unit: String) {
        // B/s → KB/s via /1000; switch to MB when > 1000 KB/s (÷1024)
        let kb = Double(max(bytes, 0)) / 1000.0
        let value: Double
        let unit: String
        if kb > 1000 {
            value = kb / 1024.0
            unit = " M/s"
        } else {
            value = kb
            unit = " K/s"
        }
        // Huorong-style: always one decimal place so string length stays stable
        return (String(format: "%.1f", value), unit)
    }
    
    private func networkSpeedAttributedString(_ bytes: Int64, color: NSColor) -> NSAttributedString {
        let parts = self.networkSpeedParts(bytes)
        let full = self.unitsState ? (parts.number + parts.unit) : parts.number
        
        let paragraph = NSMutableParagraphStyle()
        // Right-align inside the fixed column so shorter numbers do not shift the block
        paragraph.alignment = .right
        
        let attr = NSMutableAttributedString(string: full, attributes: [
            .font: self.networkValueFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
        if self.unitsState, attr.length >= 3 {
            attr.addAttribute(
                .font,
                value: self.networkUnitFont,
                range: NSRange(location: attr.length - 3, length: 3)
            )
        }
        return attr
    }
    
    private func speedAttributedString(_ bytes: Int64, color: NSColor, fontSize: CGFloat) -> NSAttributedString {
        if self.isNetworkModule {
            return self.networkSpeedAttributedString(bytes, color: color)
        }
        
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = self.valueAlignment
        let text = Units(bytes: bytes).getReadableSpeed(
            base: base,
            unit: self.speedUnit,
            omitUnits: !self.unitsState
        )
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }
    
    private func measureAttributedWidth(_ string: NSAttributedString) -> CGFloat {
        ceil(string.size().width)
    }
    
    private var inputColor: (String) -> NSColor {{ state in
        if state == "none" { return .textColor }
        var color = self.monochromeState ? MonochromeColor.blue : (self.inputColorState.additional as? NSColor ?? NSColor.systemBlue)
        if self.inputValue < 1024 {
            if state == "transparent" {
                color = .clear
            } else if state == "default" {
                color = .textColor
            }
        }
        return color
    }}
    private var outputColor: (String) -> NSColor {{ state in
        if state == "none" { return .textColor }
        var color = self.monochromeState ? MonochromeColor.red : (self.outputColorState.additional as? NSColor ?? NSColor.red)
        if self.outputValue < 1024 {
            if state == "transparent" {
                color = .clear
            } else if state == "default" {
                color = .textColor
            }
        }
        return color
    }}
    
    private var valueAlignment: NSTextAlignment {
        get {
            if let alignmentPair = Alignments.first(where: { $0.key == self.valueAlignmentState }) {
                return alignmentPair.additional as? NSTextAlignment ?? .left
            }
            return .left
        }
    }
    
    private var base: DataSizeBase {
        DataSizeBase(rawValue: Store.shared.string(key: "\(self.title)_base", defaultValue: "byte")) ?? .byte
    }
    private var speedUnit: String {
        networkSpeedUnit(from: Store.shared.string(key: "\(self.title)_speedUnit", defaultValue: NetworkSpeedUnitAuto)).key
    }
    
    public init(title: String, config: NSDictionary?, preview: Bool = false) {
        let widgetTitle: String = title
        if config != nil {
            if let symbols = config!["Symbols"] as? NSDictionary {
                if let i = symbols["Input"] as? String { self.symbols.input = i }
                if let o = symbols["Output"] as? String { self.symbols.output = o }
            }
            if let icon = config!["Icon"] as? String { self.icon = icon }
            if let words = config!["Words"] as? NSDictionary {
                if let i = words["Input"] as? String { self.words.input = i }
                if let o = words["Output"] as? String { self.words.output = o }
            }
        }
        
        super.init(.speed, title: widgetTitle, frame: CGRect(
            x: 0,
            y: Constants.Widget.margin.y,
            width: width,
            height: Constants.Widget.height - (2*Constants.Widget.margin.y)
        ))
        self.canDrawConcurrently = true
        
        if !preview {
            self.valueState = Store.shared.bool(key: "\(self.title)_\(self.type.rawValue)_value", defaultValue: self.valueState)
            self.icon = Store.shared.string(key: "\(self.title)_\(self.type.rawValue)_icon", defaultValue: self.icon)
            self.unitsState = Store.shared.bool(key: "\(self.title)_\(self.type.rawValue)_units", defaultValue: self.unitsState)
            self.monochromeState = Store.shared.bool(key: "\(self.title)_\(self.type.rawValue)_monochrome", defaultValue: self.monochromeState)
            self.valueColorState = Store.shared.string(key: "\(self.title)_\(self.type.rawValue)_valueColor", defaultValue: self.valueColorState)
            if self.valueColorState == "0" {
                self.valueColorState = "none"
            }
            self.inputColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_\(self.type.rawValue)_downloadColor", defaultValue: self.inputColorState.key))
            self.outputColorState = SColor.fromString(Store.shared.string(key: "\(self.title)_\(self.type.rawValue)_uploadColor", defaultValue: self.outputColorState.key))
            self.valueAlignmentState = Store.shared.string(key: "\(self.title)_\(self.type.rawValue)_valueAlignment", defaultValue: self.valueAlignmentState)
            self.modeState = Store.shared.string(key: "\(self.title)_\(self.type.rawValue)_mode", defaultValue: self.modeState)
            self.iconAlignmentState = Store.shared.string(key: "\(self.title)_\(self.type.rawValue)_iconAlignment", defaultValue: self.iconAlignmentState)
            self.iconColorState = Store.shared.string(key: "\(self.title)_\(self.type.rawValue)_iconColor", defaultValue: self.iconColorState)
            self.displayValueState = Store.shared.string(key: "\(self.title)_\(self.type.rawValue)_displayValue", defaultValue: self.displayValueState)
        }
        
        if preview {
            self.inputValue = 8947141
            self.outputValue = 478678
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        var width: CGFloat = 0
        switch self.modeState {
        case "oneRow":
            width = self.drawOneRow()
        case "twoRows":
            width = self.drawTwoRows()
        default:
            width = 0
        }
        
        self.setWidth(width)
    }
    
    // MARK: - one row
    
    private func drawOneRow() -> CGFloat {
        var width: CGFloat = Constants.Widget.margin.x
        
        if self.displayValueState.first == "i" {
            width = self.drawRowItem(
                initWidth: width,
                symbol: self.symbols.input,
                iconColor: self.inputColor(self.iconColorState),
                value: self.inputValue,
                valueColor: self.inputColor(self.valueColorState)
            )
        } else {
            width = self.drawRowItem(
                initWidth: width,
                symbol: self.symbols.output,
                iconColor: self.outputColor(self.iconColorState),
                value: self.outputValue,
                valueColor: self.outputColor(self.valueColorState)
            )
        }
        
        if self.displayValueState.count > 1 {
            width += Constants.Widget.spacing*3
            if self.displayValueState.last == "i" {
                width = self.drawRowItem(
                    initWidth: width,
                    symbol: self.symbols.input,
                    iconColor: self.inputColor(self.iconColorState),
                    value: self.inputValue,
                    valueColor: self.inputColor(self.valueColorState)
                )
            } else {
                width = self.drawRowItem(
                    initWidth: width,
                    symbol: self.symbols.output,
                    iconColor: self.outputColor(self.iconColorState),
                    value: self.outputValue,
                    valueColor: self.outputColor(self.valueColorState)
                )
            }
        }
        
        return width + Constants.Widget.margin.x
    }
    
    private func drawRowItem(initWidth: CGFloat, symbol: String, iconColor: NSColor, value: Int64, valueColor: NSColor) -> CGFloat {
        var width = initWidth
        // Network: pure black/white for icons and values
        let resolvedIconColor = self.isNetworkModule ? self.networkMonoColor : iconColor
        let resolvedValueColor = self.isNetworkModule ? self.networkMonoColor : valueColor
        
        if self.iconAlignmentState == "left" {
            switch self.icon {
            case "dots":
                width += self.drawDot(CGPoint(x: width, y: 0), color: resolvedIconColor)
            case "arrows":
                width += self.drawArrow(CGPoint(x: width, y: 0), symbol: symbol, color: resolvedIconColor)
            case "chars":
                width += self.drawChar(CGPoint(x: width, y: 0), symbol: symbol, color: resolvedIconColor)
            default: break
            }
            width += self.valueState && self.icon != "none" ? 2 : 0
        }
        
        if self.valueState {
            width += self.drawValue(value, offset: CGPoint(x: width, y: 0), color: resolvedValueColor)
        }
        
        if self.iconAlignmentState == "right" {
            if self.valueState {
                width += 2
            }
            switch self.icon {
            case "dots":
                width += self.drawDot(CGPoint(x: width, y: 0), color: resolvedIconColor)
            case "arrows":
                width += self.drawArrow(CGPoint(x: width, y: 0), symbol: symbol, color: resolvedIconColor)
            case "chars":
                width += self.drawChar(CGPoint(x: width, y: 0), symbol: symbol, color: resolvedIconColor)
            default: break
            }
        }
        
        return width
    }
    
    private func drawValue(_ value: Int64, offset: CGPoint, color: NSColor) -> CGFloat {
        // Network always pure B&W + fixed width; other modules use the passed color
        let drawColor = self.isNetworkModule ? self.networkMonoColor : color
        let attr = self.speedAttributedString(value, color: drawColor, fontSize: self.isNetworkModule ? 9 : 11)
        let leftTrim = self.isNetworkModule ? self.networkLeftTrim : 0
        let rowWidth: CGFloat = self.isNetworkModule
            ? self.networkFixedTextWidth
            : max(self.measureAttributedWidth(attr) + 2, self.unitsState ? 58 : 32)
        let height: CGFloat = self.frame.height
        let size: CGFloat = 10
        
        // Network: crop left only — draw shifted left so right edge of text stays put
        let rect = CGRect(
            x: offset.x - leftTrim,
            y: (height-size)/2 + offset.y + 1,
            width: rowWidth,
            height: size
        )
        attr.draw(with: rect)
        
        return rowWidth - leftTrim
    }
    
    private func drawDot(_ offset: CGPoint, color: NSColor) -> CGFloat {
        var size: CGFloat = 8
        var height: CGFloat = self.frame.height
        
        if self.modeState == "twoRows" {
            size = 6
            height /= 2
        }
        
        var circle = NSBezierPath()
        circle = NSBezierPath(ovalIn: CGRect(x: offset.x, y: (height-size)/2 + offset.y, width: size, height: size))
        color.set()
        circle.fill()
        
        return size
    }
    
    private func drawArrow(_ offset: CGPoint, symbol: String, color: NSColor) -> CGFloat {
        let height = self.frame.height
        let size = height * 0.8
        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 1
        let lineWidth: CGFloat = 1
        let arrowSize: CGFloat = 3 + (scaleFactor/2)
        let x = arrowSize + (lineWidth / 2)
        let y = (height - size)/2
        
        var start: CGPoint = CGPoint(x: offset.x + x, y: y)
        var end: CGPoint = CGPoint(x: offset.x + x, y: size + y)
        if symbol == "D" || symbol == "R" {
            start = CGPoint(x: offset.x + x, y: size + y)
            end = CGPoint(x: offset.x + x, y: y)
        } else if symbol == "U" || symbol == "W" {
            start = CGPoint(x: offset.x + x, y: y)
            end = CGPoint(x: offset.x + x, y: size + y)
        }
        
        let arrow = NSBezierPath()
        arrow.addArrow(
            start: start,
            end: end,
            pointerLineLength: arrowSize,
            arrowAngle: CGFloat(Double.pi / 5)
        )
        
        color.set()
        arrow.lineWidth = lineWidth
        arrow.stroke()
        arrow.close()
        
        return arrowSize
    }
    
    private func drawChar(_ offset: CGPoint, symbol: String, color: NSColor) -> CGFloat {
        let rowHeight: CGFloat = self.frame.height
        let height: CGFloat = 10
        let inputAttributes = [
            NSAttributedString.Key.font: NSFont.systemFont(ofSize: 12, weight: .regular),
            NSAttributedString.Key.foregroundColor: color,
            NSAttributedString.Key.paragraphStyle: NSMutableParagraphStyle()
        ]
        let rect = CGRect(x: offset.x, y: offset.y + ((rowHeight-height)/2) + 1, width: 10, height: height)
        let str = NSAttributedString.init(string: symbol, attributes: inputAttributes)
        str.draw(with: rect)
        
        return 10
    }
    
    // MARK: - two rows
    
    private func drawTwoRows() -> CGFloat {
        // Network: Huorong-style fixed-width text only (no arrow width reservation).
        // Dots/chars still use a small icon slot when selected.
        
        let showArrows = self.isNetworkModule && self.icon == "arrows"
        // Arrows do not reserve horizontal space — only dots/chars do
        let hasIcon = self.icon != "none" && !showArrows
        let iconSlot: CGFloat = hasIcon ? 7 : 0
        let iconOnLeft = hasIcon && self.iconAlignmentState != "right"
        let textX: CGFloat = iconOnLeft ? iconSlot : 0
        
        var width: CGFloat = 0
        
        if self.valueState {
            let inputColor = self.isNetworkModule ? self.networkMonoColor : self.inputColor(self.valueColorState)
            let outputColor = self.isNetworkModule ? self.networkMonoColor : self.outputColor(self.valueColorState)
            
            let inputAttr = self.speedAttributedString(self.inputValue, color: inputColor, fontSize: 9)
            let outputAttr = self.speedAttributedString(self.outputValue, color: outputColor, fontSize: 9)
            
            // Network: fixed column width from template — never depends on current value
            let rowWidth: CGFloat = self.isNetworkModule
                ? self.networkFixedTextWidth
                : max(
                    max(self.measureAttributedWidth(inputAttr), self.measureAttributedWidth(outputAttr)) + 1,
                    self.unitsState ? 48 : 30
                )
            let rowHeight: CGFloat = self.frame.height / 2
            
            // displayValue "oi" = output(upload) top / input(download) bottom
            let inputY: CGFloat = self.displayValueState == "io" ? rowHeight + 1 : 1
            let outputY: CGFloat = self.displayValueState == "io" ? 1 : rowHeight + 1
            
            // Network: crop left only — draw shifted left so right edge of text is unchanged
            let leftTrim = self.isNetworkModule ? self.networkLeftTrim : 0
            let drawX = Constants.Widget.margin.x + textX - leftTrim
            
            inputAttr.draw(with: CGRect(
                x: drawX,
                y: inputY,
                width: rowWidth,
                height: rowHeight
            ))
            outputAttr.draw(with: CGRect(
                x: drawX,
                y: outputY,
                width: rowWidth,
                height: rowHeight
            ))
            
            width = textX + rowWidth - leftTrim
            if hasIcon && !iconOnLeft {
                width += iconSlot
            }
        } else if hasIcon {
            width = iconSlot
        }
        
        // Arrows: draw without expanding width (no reserved slot)
        if showArrows {
            self.drawLemonArrows()
            return width
        }
        
        switch self.icon {
        case "dots":
            self.drawDots(width)
        case "chars":
            self.drawChars(width)
        default: break
        }
        
        return width
    }
    
    /// Compact filled chevrons — pure black/white; drawn only when pictogram is "arrows".
    /// Does not contribute to widget width (no reserved slot).
    private func drawLemonArrows() {
        let half = self.frame.height / 2
        let color = self.networkMonoColor
        let x: CGFloat = 0
        let arrowW: CGFloat = 5
        let arrowH: CGFloat = 3.5
        
        let topY = half + (half - arrowH) / 2 + 0.5
        let bottomY = (half - arrowH) / 2
        
        color.set()
        
        // ▲ upload
        let up = NSBezierPath()
        up.move(to: CGPoint(x: x + arrowW / 2, y: topY + arrowH))
        up.line(to: CGPoint(x: x, y: topY))
        up.line(to: CGPoint(x: x + arrowW, y: topY))
        up.close()
        up.fill()
        
        // ▼ download
        let down = NSBezierPath()
        down.move(to: CGPoint(x: x + arrowW / 2, y: bottomY))
        down.line(to: CGPoint(x: x, y: bottomY + arrowH))
        down.line(to: CGPoint(x: x + arrowW, y: bottomY + arrowH))
        down.close()
        down.fill()
    }
    
    private func drawDots(_ width: CGFloat) {
        let rowHeight: CGFloat = self.frame.height / 2
        let size: CGFloat = 6
        let y: CGFloat = (rowHeight-size)/2
        let x: CGFloat = self.iconAlignmentState == "left" ? Constants.Widget.margin.x : Constants.Widget.margin.x+(width-6)
        let inputY: CGFloat = self.displayValueState == "io" ? 10.5 : y-0.2
        let outputdY: CGFloat = self.displayValueState == "io" ? y-0.2 : 10.5
        
        let inColor = self.isNetworkModule ? self.networkMonoColor : self.inputColor(self.iconColorState)
        let outColor = self.isNetworkModule ? self.networkMonoColor : self.outputColor(self.iconColorState)
        
        var inputCircle = NSBezierPath()
        inputCircle = NSBezierPath(ovalIn: CGRect(x: x, y: inputY, width: size, height: size))
        inColor.set()
        inputCircle.fill()
        
        var outputCircle = NSBezierPath()
        outputCircle = NSBezierPath(ovalIn: CGRect(x: x, y: outputdY, width: size, height: size))
        outColor.set()
        outputCircle.fill()
    }
    
    private func drawArrows(_ width: CGFloat) {
        let arrowAngle = CGFloat(Double.pi / 5)
        let half = self.frame.size.height / 2
        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 1
        let lineWidth: CGFloat = 1
        let arrowSize: CGFloat = 3 + (scaleFactor/2)
        var x = Constants.Widget.margin.x + arrowSize + (lineWidth / 2)
        if self.iconAlignmentState == "right" {
            x += (width-7)
        }
        
        let inputYStart: CGFloat = self.displayValueState == "io" ? self.frame.size.height : half - Constants.Widget.spacing/2
        let inputYEnd: CGFloat = self.displayValueState == "io" ? (half + Constants.Widget.spacing/2)+1 : 1
        
        let outputYStart: CGFloat = self.displayValueState == "io" ? 0 : half + Constants.Widget.spacing/2
        let uploadYEnd: CGFloat = self.displayValueState == "io" ? (half - Constants.Widget.spacing/2)-1 : self.frame.size.height-1
        
        let inputArrow = NSBezierPath()
        inputArrow.addArrow(
            start: CGPoint(x: x, y: inputYStart),
            end: CGPoint(x: x, y: inputYEnd),
            pointerLineLength: arrowSize,
            arrowAngle: arrowAngle
        )
        
        self.inputColor(self.iconColorState).set()
        inputArrow.lineWidth = lineWidth
        inputArrow.stroke()
        inputArrow.close()
        
        let outputArrow = NSBezierPath()
        outputArrow.addArrow(
            start: CGPoint(x: x, y: outputYStart),
            end: CGPoint(x: x, y: uploadYEnd),
            pointerLineLength: arrowSize,
            arrowAngle: arrowAngle
        )
        
        self.outputColor(self.iconColorState).set()
        outputArrow.lineWidth = lineWidth
        outputArrow.stroke()
        outputArrow.close()
    }
    
    private func drawChars(_ width: CGFloat) {
        let rowHeight: CGFloat = self.frame.height / 2
        let inputY: CGFloat = self.displayValueState == "io" ? rowHeight+1 : 1
        let outputY: CGFloat = self.displayValueState == "io" ? 1 : rowHeight+1
        let x: CGFloat = self.iconAlignmentState == "left" ? Constants.Widget.margin.x : Constants.Widget.margin.x+(width-6)
        let inColor = self.isNetworkModule ? self.networkMonoColor : self.inputColor(self.iconColorState)
        let outColor = self.isNetworkModule ? self.networkMonoColor : self.outputColor(self.iconColorState)
        
        let inputAttributes = [
            NSAttributedString.Key.font: NSFont.systemFont(ofSize: 9, weight: .regular),
            NSAttributedString.Key.foregroundColor: inColor,
            NSAttributedString.Key.paragraphStyle: NSMutableParagraphStyle()
        ]
        var rect = CGRect(x: x, y: inputY, width: 8, height: rowHeight)
        var str = NSAttributedString.init(string: self.symbols.input, attributes: inputAttributes)
        str.draw(with: rect)
        
        let outputAttributes = [
            NSAttributedString.Key.font: NSFont.systemFont(ofSize: 9, weight: .regular),
            NSAttributedString.Key.foregroundColor: outColor,
            NSAttributedString.Key.paragraphStyle: NSMutableParagraphStyle()
        ]
        rect = CGRect(x: x, y: outputY, width: 8, height: rowHeight)
        str = NSAttributedString.init(string: self.symbols.output, attributes: outputAttributes)
        str.draw(with: rect)
    }
    
    // MARK: - settings
    
    public override func settings() -> NSView {
        let view = SettingsContainerView()
        
        let valueAlignment = selectView(
            action: #selector(self.toggleValueAlignment),
            items: Alignments,
            selected: self.valueAlignmentState
        )
        valueAlignment.isEnabled = self.valueState
        self.valueAlignmentView = valueAlignment
        
        let iconAlignment = selectView(
            action: #selector(self.toggleIconAlignment),
            items: Alignments.filter({ $0.key != "center" }),
            selected: self.iconAlignmentState
        )
        iconAlignment.isEnabled = self.icon != "none"
        self.iconAlignmentView = iconAlignment
        
        let iconColor = selectView(
            action: #selector(self.toggleIconColor),
            items: SpeedPictogramColor.filter({ $0.key != "none" }),
            selected: self.iconColorState
        )
        iconColor.isEnabled = self.icon != "none"
        self.iconColorView = iconColor
        
        let valueColor = selectView(
            action: #selector(self.toggleValueColor),
            items: SpeedPictogramColor,
            selected: self.valueColorState
        )
        valueColor.isEnabled = self.valueState
        self.valueColorView = valueColor
        
        let displayMode = selectView(
            action: #selector(self.changeDisplayMode),
            items: SensorsWidgetMode.filter({ $0.key == "oneRow" || $0.key == "twoRows"}),
            selected: self.modeState
        )
        displayMode.isEnabled = self.displayValueState.count > 1
        self.displayModeView = displayMode
        
        let sensorWidgetValue = SensorsWidgetValue.map { v in
            var value = v.value.replacingOccurrences(of: "input", with: localizedString(self.words.input), options: .literal, range: nil)
            value = value.replacingOccurrences(of: "output", with: localizedString(self.words.output), options: .literal, range: nil)
            return KeyValue_t(key: v.key, value: value)
        }
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Value"), component: selectView(
                action: #selector(self.changeDisplayValue),
                items: sensorWidgetValue,
                selected: self.displayValueState
            )),
            PreferencesRow(localizedString("Display mode"), component: displayMode)
        ]))
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Pictogram"), component: selectView(
                action: #selector(self.toggleIcon),
                items: SpeedPictogram,
                selected: self.icon
            )),
            PreferencesRow(localizedString("Colorize"), component: iconColor),
            PreferencesRow(localizedString("Alignment"), component: iconAlignment)
        ]))
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Value"), component: switchView(
                action: #selector(self.toggleValue),
                state: self.valueState
            )),
            PreferencesRow(localizedString("Colorize value"), component: valueColor),
            PreferencesRow(localizedString("Alignment"), component: valueAlignment),
            PreferencesRow(localizedString("Units"), component: switchView(
                action: #selector(self.toggleUnits),
                state: self.unitsState
            ))
        ]))
        
        view.addArrangedSubview(PreferencesSection([
            PreferencesRow(localizedString("Monochrome accent"), component: switchView(
                action: #selector(self.toggleMonochrome),
                state: self.monochromeState
            )),
            PreferencesRow(localizedString("Color of download"), component: colorSelectView(
                action: #selector(self.toggleInputColor),
                items: SColor.allColors,
                selected: self.inputColorState.key
            )),
            PreferencesRow(localizedString("Color of upload"), component: colorSelectView(
                action: #selector(self.toggleOutputColor),
                items: SColor.allColors,
                selected: self.outputColorState.key
            ))
        ]))
        
        return view
    }
    
    @objc private func changeDisplayValue(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.displayValueState = key
        
        if key.count == 1 {
            if self.modeState != "oneRow" {
                self.modeState = "oneRow"
                Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_mode", value: self.modeState)
            }
            self.displayModeView?.selectItem(at: 0)
        }
        self.displayModeView?.isEnabled = key.count > 1
        
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_displayValue", value: key)
        self.display()
    }
    
    @objc private func changeDisplayMode(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.modeState = key
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_mode", value: key)
        self.display()
    }
    
    @objc private func toggleValue(_ sender: NSControl) {
        self.valueState = controlState(sender)
        
        self.valueColorView?.isEnabled = self.valueState
        self.valueAlignmentView?.isEnabled = self.valueState
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_value", value: self.valueState)
        self.display()
    }
    
    @objc private func toggleUnits(_ sender: NSControl) {
        self.unitsState = controlState(sender)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_units", value: self.unitsState)
        self.display()
    }
    
    @objc private func toggleIcon(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.icon = key
        self.iconColorView?.isEnabled = self.icon != "none"
        self.iconAlignmentView?.isEnabled = self.icon != "none"
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_icon", value: key)
        self.display()
    }
    
    @objc private func toggleMonochrome(_ sender: NSControl) {
        self.monochromeState = controlState(sender)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_monochrome", value: self.monochromeState)
        self.display()
    }
    
    @objc private func toggleValueColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        if let newColor = SpeedPictogramColor.first(where: { $0.key == key }) {
            self.valueColorState = newColor.key
        }
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_valueColor", value: key)
        self.display()
    }
    
    @objc private func toggleOutputColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.outputColorState = SColor.fromString(key, defaultValue: self.outputColorState)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_uploadColor", value: self.outputColorState.key)
        self.display()
    }
    @objc private func toggleInputColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        self.inputColorState = SColor.fromString(key, defaultValue: self.inputColorState)
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_downloadColor", value: self.inputColorState.key)
        self.display()
    }
    
    public func setValue(input: Int64, output: Int64) {
        var updated: Bool = false
        
        if self.inputValue != input {
            self.inputValue = abs(input)
            updated = true
        }
        if self.outputValue != output {
            self.outputValue = abs(output)
            updated = true
        }
        
        if updated {
            DispatchQueue.main.async(execute: {
                self.display()
            })
        }
    }
    
    @objc private func toggleValueAlignment(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        if let newAlignment = Alignments.first(where: { $0.key == key }) {
            self.valueAlignmentState = newAlignment.key
        }
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_valueAlignment", value: key)
        self.display()
    }
    
    @objc private func toggleIconAlignment(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        if let newAlignment = Alignments.first(where: { $0.key == key }) {
            self.iconAlignmentState = newAlignment.key
        }
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_iconAlignment", value: key)
        self.display()
    }
    
    @objc private func toggleIconColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        if let newColor = SpeedPictogramColor.first(where: { $0.key == key }) {
            self.iconColorState = newColor.key
        }
        Store.shared.set(key: "\(self.title)_\(self.type.rawValue)_iconColor", value: key)
        self.display()
    }
}
