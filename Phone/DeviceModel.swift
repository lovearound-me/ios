import Foundation

/// Device protocol v1 on the model: values and «Проверить», the steps of a
/// setup over Bluetooth, and the Bluetooth-only toys this phone talks for.
extension AppModel {
    // MARK: Values

    /// A setting changed on a part's page: shown at once, sent a moment
    /// later, so a dragged slider sends once (the server takes 10 a minute
    /// per device). `.null` is back to the default.
    func setValue(_ id: String, _ part: DevicePart, _ setting: String, _ value: JSONValue) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
        var values = devices[i].values ?? [:]
        values[part.id, default: [:]][setting] = value == .null ? nil : value
        devices[i].values = values
        if demo != nil {
            demoApply(id)
            return
        }
        pendingValues[id, default: [:]][part.id, default: [:]][setting] = value
        sendValues(id, after: 0.6)
    }

    private func sendValues(_ id: String, after seconds: Double) {
        valueWaits[id]?.cancel()
        valueWaits[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            // Not this task's own work: a newer change cancels the wait, and
            // must not cancel a request on its way.
            Task { await self.flushValues(id) }
        }
    }

    /// Sends what waits for `id`, one request at a time.
    func flushValues(_ id: String) async {
        guard !valueFlights.contains(id) else {
            sendValues(id, after: 0.3)
            return
        }
        guard let sending = pendingValues.removeValue(forKey: id), !sending.isEmpty else { return }
        valueFlights.insert(id)
        defer { valueFlights.remove(id) }
        do {
            var updated = try await api.setDeviceValues(id, sending)
            // What changed meanwhile stays on top of the server's answer.
            for (part, settings) in pendingValues[id] ?? [:] {
                for (setting, value) in settings {
                    updated.values?[part]?[setting] = value == .null ? nil : value
                }
            }
            replace(updated)
            if updated.throughPhone { writeSettings(updated) }
        } catch let error as AuthError where error.endsSession {
            signOut()
        } catch let error as APIError where error.status == 429 {
            // Too many in a minute: the same values, with anything newer, a
            // little later.
            var merged = sending
            for (part, settings) in pendingValues[id] ?? [:] {
                merged[part, default: [:]].merge(settings) { _, newer in newer }
            }
            pendingValues[id] = merged
            sendValues(id, after: 6)
        } catch {
            show(tr("Не получилось сохранить"), failed: true)
            await loadDevices()
        }
    }

    /// «Проверить»: a heart on that one device, as it is set now.
    func preview(_ device: Device) async {
        if demo != nil {
            show(tr("Сердечко ушло на устройство"))
            return
        }
        valueWaits[device.id]?.cancel()
        await flushValues(device.id)
        if device.throughPhone {
            // The server can't reach a toy: this phone shows it itself.
            if toys.send(["type": "preview"], to: device.id) {
                show(tr("Сердечко ушло на устройство"))
            } else {
                show(tr("Игрушки нет рядом с телефоном"), failed: true)
            }
            return
        }
        do {
            try await api.previewDevice(device.id)
            show(tr("Сердечко ушло на устройство"))
        } catch let error as APIError where error.code == "offline" {
            show(tr("Устройство сейчас не в сети"), failed: true)
        } catch let error as APIError where error.code == "no_about" {
            show(tr("Устройство не рассказало, что в нём можно настроить"), failed: true)
        } catch let error as APIError where error.status == 429 {
            // Once a second: the tap before this one is still on its way.
        } catch {
            show(tr("Не получилось, попробуй ещё раз"), failed: true)
        }
    }

    func replace(_ device: Device) {
        if let i = devices.firstIndex(where: { $0.id == device.id }) {
            devices[i] = device
        } else {
            devices.append(device)
        }
    }

    /// A demo's device takes a change at once: the yellow line shows for a
    /// moment, then the green one.
    private func demoApply(_ id: String) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
        demoRevision += 1
        let rev = "demo\(demoRevision)"
        devices[i].rev = rev
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            if let j = devices.firstIndex(where: { $0.id == id }), devices[j].rev == rev { devices[j].applied = rev }
        }
    }

    // MARK: Setup over Bluetooth

    /// The Wi-Fi a board was given from this phone: the server never learns
    /// it, so only this phone can show it.
    func wifiName(_ id: String) -> String? {
        (defaults.dictionary(forKey: "deviceWifi") as? [String: String])?[id]
    }

    func rememberWifi(_ id: String, _ ssid: String?) {
        var names = defaults.dictionary(forKey: "deviceWifi") as? [String: String] ?? [:]
        names[id] = ssid
        defaults.set(names, forKey: "deviceWifi")
    }

    /// The board has joined Wi-Fi: only now is it made on the server, so a
    /// wrong password leaves nothing in the account. Its token goes to it
    /// over Bluetooth and is never shown.
    func makeBoard(name: String, about: [String: Any]) async throws -> (Device, String) {
        let wants = (about["wants"] as? [String] ?? ["receive"]).filter { ["receive", "send"].contains($0) }
        if demo != nil {
            var device = Demo.ring(id: UUID().uuidString, name: name)
            device.capabilities = wants
            device.requested_capabilities = wants
            device.online = false
            device.applied = nil
            devices.append(device)
            return (device, "dev_demo_7Hq2kLx9WbN4sP0aZr")
        }
        let (device, token) = try await api.addBluetoothBoard(name: name, capabilities: wants)
        replace(device)
        return (device, token)
    }

    /// Waits for the board's first connection to the server: `online` in
    /// the list, asked every two seconds (the `sync devices` hint refreshes
    /// the list too). False after `timeout`.
    func waitOnline(_ id: String, timeout: Double = 75) async -> Bool {
        if demo != nil {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if let i = devices.firstIndex(where: { $0.id == id }) {
                devices[i].online = true
                devices[i].applied = devices[i].rev
                devices[i].last_seen_at = ISO8601DateFormatter().string(from: Date())
            }
            return true
        }
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return false }
            await loadDevices()
            if devices.first(where: { $0.id == id })?.online == true { return true }
        }
        return false
    }

    /// A setup that didn't finish leaves nothing in the account.
    func dropUnfinished(_ id: String) async {
        if demo == nil { try? await api.deleteDevice(id) }
        devices.removeAll { $0.id == id }
        rememberWifi(id, nil)
    }

    /// A Bluetooth-only toy joins: made on the server without a token, its
    /// `about` posted for it, its settings written to it.
    func makeToy(name: String, about: [String: Any], peripheral: UUID) async throws -> Device {
        let wants = (about["wants"] as? [String] ?? ["receive"]).filter { ["receive", "send"].contains($0) }
        if demo != nil {
            let device = Demo.band(id: UUID().uuidString, name: name)
            devices.append(device)
            toys.adopt(peripheral, as: device.id)
            return device
        }
        let device = try await api.addToy(name: name, capabilities: wants)
        replace(device)
        toys.adopt(peripheral, as: device.id)
        do {
            let settings = try await api.putToyAbout(device.id, about: about)
            keepToyAbout(device.id, about)
            if !settings.isEmpty { toys.send(settings, to: device.id) }
        } catch {
            _ = toys.forget(device.id)
            await dropUnfinished(device.id)
            throw error
        }
        await loadDevices()
        return devices.first { $0.id == device.id } ?? device
    }

    // MARK: Bluetooth-only toys

    func listenToToys() {
        toys.onAbout = { [weak self] device, about in self?.toySaid(device, about) }
        toys.onNear = { [weak self] device in
            guard let self, let it = self.devices.first(where: { $0.id == device }) else { return }
            self.toyContacts[device] = nil  // a new link: the toy gets the list again
            self.writeSettings(it)
        }
        toys.onApplied = { [weak self] device, rev in self?.toyApplied(device, rev) }
        toys.onBattery = { [weak self] device, level in self?.toyBattery(device, level) }
        toys.onPress = { [weak self] device, part, gesture in self?.toyPressed(device, part, gesture) }
        toys.onSignal = { [weak self] device, to in self?.toySignal(device, to) }
    }

    /// The values the server keeps, written to the toy when it is near.
    func writeSettings(_ device: Device) {
        guard device.throughPhone, device.rev != nil else { return }
        toys.send(device.settingsMessage(), to: device.id)
        writeContacts(device)
    }

    /// A toy that sends and has a screen to pick on gets the people its
    /// book shows, as the server would give them to a board: only when the
    /// list changed. 40 at most, short labels: a message is 4 KB.
    func writeContacts(_ device: Device) {
        guard device.throughPhone, device.sends, toys.near.contains(device.id),
              (device.about?.parts ?? []).contains(where: { $0.known == .screen }) else { return }
        let people = device.people(of: contacts).prefix(40).map { person -> [String: Any] in
            let hex = Palette.all[((person.color ?? 0) % Palette.all.count + Palette.all.count) % Palette.all.count].color
            return ["id": person.id, "label": String(person.label.prefix(24)), "close": person.isClose,
                    "rgb": String(format: "#%06X", hex)]
        }
        let message: [String: Any] = ["type": "contacts", "contacts": Array(people)]
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]),
              toyContacts[device.id] != data else { return }
        toyContacts[device.id] = data
        toys.send(message, to: device.id)
    }

    /// The book or the people changed: the toys near get the new list.
    func writeContactsToToys() {
        for device in devices where device.throughPhone { writeContacts(device) }
    }

    /// «Отключить»: a toy erases its bond if it is near; either way iOS
    /// keeps its own, which only the person can remove.
    func forgetDevice(_ device: Device) {
        rememberWifi(device.id, nil)
        guard device.throughPhone else { return }
        let mine = toys.isMine(device.id)
        let heard = toys.forget(device.id)
        var abouts = defaults.dictionary(forKey: "toyAbout") as? [String: Data] ?? [:]
        abouts[device.id] = nil
        defaults.set(abouts, forKey: "toyAbout")
        if mine { toyGone = ToyGone(name: device.name, heard: heard) }
    }

    /// A heart came while the app is open: iOS shows no banner then, so it
    /// forwards nothing to a bonded toy, and the app writes the event
    /// itself. The phone's pause and quiet hours hold for its toys.
    func heartForToys() {
        guard demo == nil, receiveHere, !isPaused, !isQuiet else { return }
        let now = Date()
        guard now.timeIntervalSince(lastToyHeart) > 2 else { return }
        lastToyHeart = now
        for device in devices where device.throughPhone && device.receives && toys.near.contains(device.id) {
            toys.send(["type": "event", "event": ["type": "signal", "v": 1]], to: device.id)
        }
    }

    private func keepToyAbout(_ id: String, _ about: [String: Any]) {
        var abouts = defaults.dictionary(forKey: "toyAbout") as? [String: Data] ?? [:]
        abouts[id] = try? JSONSerialization.data(withJSONObject: about, options: [.sortedKeys])
        defaults.set(abouts, forKey: "toyAbout")
    }

    /// The toy says what it is made of at every connect; the server hears
    /// it only when it changed (a new firmware).
    private func toySaid(_ id: String, _ about: [String: Any]) {
        guard demo == nil, signedIn else { return }
        let said = try? JSONSerialization.data(withJSONObject: about, options: [.sortedKeys])
        let kept = (defaults.dictionary(forKey: "toyAbout") as? [String: Data])?[id]
        guard said != kept else { return }
        Task {
            guard let settings = try? await api.putToyAbout(id, about: about) else { return }
            keepToyAbout(id, about)
            if !settings.isEmpty { toys.send(settings, to: id) }
            await loadDevices()
        }
    }

    private func toyApplied(_ id: String, _ rev: String) {
        guard let i = devices.firstIndex(where: { $0.id == id }), devices[i].applied != rev else { return }
        devices[i].applied = rev
        guard demo == nil else { return }
        let battery = devices[i].battery
        Task { try? await api.postToyState(id, rev: rev, battery: battery) }
    }

    /// The battery, when it changed noticeably.
    private func toyBattery(_ id: String, _ level: Int) {
        guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
        if let old = devices[i].battery, abs(old - level) < 5 { return }
        devices[i].battery = level
        guard demo == nil else { return }
        Task { try? await api.postToyState(id, rev: nil, battery: level) }
    }

    /// A press on the toy woke the app: it sends as the button is set.
    /// A heart picked on a toy's screen: sent as the toy, and the server's
    /// answer goes back so its screen can say what happened.
    private func toySignal(_ id: String, _ to: Any) {
        guard demo == nil, signedIn, let device = devices.first(where: { $0.id == id }) else { return }
        guard device.sends else {
            toys.send(["type": "sent", "code": 403], to: id)
            return
        }
        Task {
            var code = 202
            do {
                try await api.signal(to: to)
            } catch APIError.status(let status, _) {
                code = status
            } catch {
                code = -1
            }
            toys.send(["type": "sent", "code": code], to: id)
        }
    }

    private func toyPressed(_ id: String, _ part: String, _ gesture: String) {
        guard demo == nil, signedIn, let device = devices.first(where: { $0.id == id }), device.sends else { return }
        let target = ButtonTarget(device.values?[part]?[gesture])
        guard target != .nothing else { return }
        Task { try? await api.signal(to: target.json.any) }
    }
}
