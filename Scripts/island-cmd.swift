#!/usr/bin/env swift
// Sends a DEBUG command to a running MacIsland (Debug build only).
// Example: swift Scripts/island-cmd.swift open
import Foundation
let command = CommandLine.arguments.dropFirst().joined(separator: " ")
guard !command.isEmpty else {
    print("usage: island-cmd.swift <open|close|toggle|tab:shelf|media:toggle|activity:volume|timer:start:90|dump>")
    exit(1)
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.macisland.debug.command"),
    object: nil,
    userInfo: ["command": command],
    deliverImmediately: true
)
print("sent: \(command)")
