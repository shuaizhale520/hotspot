import AppKit
import IOKit.pwr_mgt
import Network
import ServiceManagement
import SwiftUI

@main
struct HotspotKeeperApp: App {
    @StateObject private var keeper = HotspotKeeper()

    var body: some Scene {
        MenuBarExtra {
            KeeperMenu(keeper: keeper)
        } label: {
            Label("热点保活", systemImage: keeper.isRunning ? "antenna.radiowaves.left.and.right" : "wifi")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class HotspotKeeper: ObservableObject {
    @Published var isRunning = false
    @Published var wifiAvailable = false
    @Published var interval = 60
    @Published var preventSleep = false {
        didSet { updateSleepAssertion() }
    }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var lastActivity = "尚未发送"
    @Published var detail = "已停止"

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "HotspotKeeper.NetworkMonitor")
    private var loopTask: Task<Void, Never>?
    private var sleepAssertion: IOPMAssertionID = 0
    private let keepAliveURL = URL(string: "https://captive.apple.com/hotspot-detect.html")!

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.wifiAvailable = path.status == .satisfied
                    && path.availableInterfaces.contains { $0.type == .wifi }
                if self.isRunning && !self.wifiAvailable {
                    self.detail = "等待 Wi-Fi 连接"
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        detail = wifiAvailable ? "正在保活" : "等待 Wi-Fi 连接"
        loopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if self.wifiAvailable {
                    await self.sendKeepAlive()
                } else {
                    self.detail = "等待 Wi-Fi 连接"
                }
                do {
                    let delay = self.wifiAvailable ? self.interval : min(self.interval, 5)
                    try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                } catch {
                    break
                }
            }
        }
        updateSleepAssertion()
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        isRunning = false
        detail = "已停止"
        updateSleepAssertion()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            detail = "登录启动设置失败：\(error.localizedDescription)"
        }
    }

    private func sendKeepAlive() async {
        var request = URLRequest(url: keepAliveURL)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        request.setValue("HotspotKeeper/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                detail = "收到无效响应"
                return
            }
            lastActivity = Date.now.formatted(date: .omitted, time: .shortened)
            detail = (200..<400).contains(response.statusCode)
                ? "保活正常（HTTP \(response.statusCode)）"
                : "请求返回 HTTP \(response.statusCode)"
        } catch {
            detail = "连接失败：\(error.localizedDescription)"
        }
    }

    private func updateSleepAssertion() {
        if isRunning && preventSleep {
            guard sleepAssertion == 0 else { return }
            let reason = "热点保活正在运行" as CFString
            IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoIdleSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &sleepAssertion
            )
        } else if sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
        }
    }
}

private struct KeeperMenu: View {
    @ObservedObject var keeper: HotspotKeeper

    private let intervals = [30, 60, 120, 300]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: keeper.isRunning ? "antenna.radiowaves.left.and.right" : "wifi")
                    .font(.system(size: 22))
                    .foregroundStyle(keeper.isRunning ? .green : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("热点保活").font(.headline)
                    Text(keeper.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Label(keeper.wifiAvailable ? "Wi-Fi 已连接" : "未检测到 Wi-Fi", systemImage: keeper.wifiAvailable ? "wifi" : "wifi.slash")
                .font(.subheadline)

            HStack {
                Text("最近保活")
                Spacer()
                Text(keeper.lastActivity).foregroundStyle(.secondary)
            }
            .font(.caption)

            Picker("保活间隔", selection: $keeper.interval) {
                ForEach(intervals, id: \.self) { seconds in
                    Text("每 \(seconds) 秒").tag(seconds)
                }
            }

            Toggle("运行时阻止 Mac 自动睡眠", isOn: $keeper.preventSleep)
            Toggle("登录时自动启动", isOn: Binding(
                get: { keeper.launchAtLogin },
                set: { keeper.setLaunchAtLogin($0) }
            ))

            Text("通过 Apple 连通性检测发送无内容的 HEAD 请求。Mac 睡眠或 Wi-Fi 断开时无法保活。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(keeper.isRunning ? "停止保活" : "开始保活") {
                    keeper.isRunning ? keeper.stop() : keeper.start()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}
