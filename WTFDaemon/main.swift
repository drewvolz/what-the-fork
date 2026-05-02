// WTFDaemon/main.swift
import Foundation

let server = XPCEventServer()
let listener = NSXPCListener(machServiceName: XPCEventServer.serviceName)
listener.delegate = server
listener.resume()

print("WTFDaemon: XPC listener started on \(XPCEventServer.serviceName)")
RunLoop.main.run()
