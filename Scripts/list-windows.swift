#!/usr/bin/env swift
// Lists MacIsland windows (layer, alpha, bounds) via CGWindowList — handy to check the viewport without screenshots.
import AppKit
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == "MacIsland" {
    let b = w[kCGWindowBounds as String] as! [String: CGFloat]
    print("pid:", w[kCGWindowOwnerPID as String] ?? 0, "layer:", w[kCGWindowLayer as String] ?? 0, "alpha:", w[kCGWindowAlpha as String] ?? 0, "onscreen:", w[kCGWindowIsOnscreen as String] ?? false, "bounds(x,y,w,h):", b["X"]!, b["Y"]!, b["Width"]!, b["Height"]!)
}
