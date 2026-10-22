import AppKit
import CoreAudio

/// Main-thread owner of capture, renderer, and the independent AirPlay service.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let engine=SyncEngine()
    private let devices=AudioDevices()
    private let service=OwnToneService()
    private let client=OwnToneClient()
    private var window:NSWindow!
    private var status=NSTextField(labelWithString:"准备设备…")
    private var detail=NSTextField(wrappingLabelWithString:"")
    private var button=NSButton(title:"开始共同播放",target:nil,action:nil)
    private var refreshButton=NSButton(title:"刷新设备",target:nil,action:nil)
    private var outputList=NSStackView()
    private let modePicker=NSSegmentedControl()
    private var deviceScroll:DeviceListScrollView!
    private let notice=NSTextField(wrappingLabelWithString:"")
    private var mode:PlaybackMode = .relay
    private var nativeRouteUID:String?
    private var routeListener:AudioObjectPropertyListenerBlock?
    private var localRows:[String:SpeakerRow]=[:]
    private var remoteRows:[String:SpeakerRow]=[:]
    private var timer:Timer?
    private var item:NSStatusItem!
    private var busy=false
    private var refreshing=false
    private let lifecycle=PlaybackLifecycle()
    private let flow=AudioFlowMonitor()
    private var operation:Task<Void,Never>?
    private var activeRemote:Set<String>=[]
    private var backendFailCount=0
    private var remoteVolumes:[String:Int]=[:]
    private var volumeWork:DispatchWorkItem?
    private let preferences=UserDefaults.standard
    private var selectedRemote:Set<String>=[]
    private var selectedLocal:Set<String>=[]

    func applicationDidFinishLaunching(_ notification:Notification) {
        mode=PlaybackMode(rawValue:preferences.string(forKey:"playbackMode") ?? "")
            ?? (devices.isAirPlay(devices.defaultOutputDevice()) ? .nativeAirPlay:.relay)
        selectedRemote=Set(preferences.stringArray(forKey:"selectedRemote") ?? [])
        selectedLocal=Set(preferences.stringArray(forKey:"selectedLocal") ?? [])
        makeMenu();makeWindow();refreshLocal();updateModeUI();installRouteListener()
        engine.onStopped={ [weak self] reason in self?.stopPlayback(message:reason) }
        engine.onOutputLost={ [weak self] uid in
            guard let self else{return}
            self.selectedLocal.remove(uid);self.localRows[uid]?.check.state = .off
            self.stopPlayback(message:"本地扬声器已断开，已恢复普通播放。")
        }
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(willSleep),name:NSWorkspace.willSleepNotification,object:nil)
        timer=Timer.scheduledTimer(withTimeInterval:2,repeats:true){ [weak self] _ in
            guard let self else{return}
            Task { @MainActor in await self.refreshRemote() }
            self.checkFlow()
        }
        Task { @MainActor in await self.refreshRemote() }
        showWindow()
    }
    func applicationWillTerminate(_ notification:Notification) {
        timer?.invalidate();_ = lifecycle.beginStop();operation?.cancel();engine.stop();service.stop()
        if let listener=routeListener {
            var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultOutputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&address,DispatchQueue.main,listener)
        }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{false}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{showWindow();return true}
    @objc private func willSleep(){stopPlayback(message:"Mac 即将休眠，已停止共同播放。唤醒后可重新开始。")}

    private func makeMenu(){
        let main=NSMenu();let appItem=NSMenuItem();main.addItem(appItem)
        let appMenu=NSMenu();appMenu.addItem(withTitle:"关于 Mac HomePod 同播",action:#selector(about),keyEquivalent:"")
        appMenu.addItem(.separator());appMenu.addItem(withTitle:"退出",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appItem.submenu=appMenu;NSApp.mainMenu=main
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        item.button?.image=NSImage(systemSymbolName:"hifispeaker.2",accessibilityDescription:"Mac HomePod 同播")
        let menu=NSMenu();menu.addItem(withTitle:"打开控制面板",action:#selector(openPanel),keyEquivalent:"")
        menu.addItem(withTitle:"停止共同播放",action:#selector(menuStop),keyEquivalent:"")
        menu.addItem(.separator());menu.addItem(withTitle:"退出",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"")
        item.menu=menu
    }
    private func makeWindow(){
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:520,height:470),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title="Mac HomePod 同播";window.minSize=NSSize(width:480,height:460)
        window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true
        window.isMovableByWindowBackground=true;window.center();window.delegate=self
        let background=NSVisualEffectView()
        background.material = .underWindowBackground;background.blendingMode = .behindWindow
        window.contentView=background
        let root=NSStackView();root.orientation = .vertical;root.alignment = .leading;root.spacing=12
        root.translatesAutoresizingMaskIntoConstraints=false;background.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo:background.leadingAnchor,constant:20),
            root.trailingAnchor.constraint(equalTo:background.trailingAnchor,constant:-20),
            root.topAnchor.constraint(equalTo:background.topAnchor,constant:40),
            root.bottomAnchor.constraint(equalTo:background.bottomAnchor,constant:-18)
        ])
        let header=NSStackView();header.orientation = .horizontal;header.spacing=10
        let icon=NSImageView()
        icon.wantsLayer=true;icon.layer?.cornerRadius=10;icon.layer?.masksToBounds=true
        icon.image=Bundle.main.image(forResource:"AppIcon") ?? NSImage(systemSymbolName:"hifispeaker.2.fill",accessibilityDescription:nil)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant:46).isActive=true;icon.heightAnchor.constraint(equalToConstant:46).isActive=true
        header.addArrangedSubview(icon)
        let titles=NSStackView();titles.orientation = .vertical;titles.alignment = .leading;titles.spacing=3
        let title=NSTextField(labelWithString:"Mac HomePod 同播");title.font = .systemFont(ofSize:20,weight:.semibold)
        let subtitle=NSTextField(labelWithString:"让两处声音，落在同一拍。")
        subtitle.font = .systemFont(ofSize:11);subtitle.textColor = .secondaryLabelColor
        titles.addArrangedSubview(title);titles.addArrangedSubview(subtitle)
        header.addArrangedSubview(titles);header.addArrangedSubview(NSView())
        let help=NSButton(image:NSImage(systemSymbolName:"questionmark.circle",accessibilityDescription:"使用说明")!,target:self,action:#selector(showHelp))
        help.isBordered=false;help.toolTip="使用说明";help.setAccessibilityLabel("使用说明")
        header.addArrangedSubview(help)
        root.addArrangedSubview(header);header.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true

        let modeGlass=GlassPanel(radius:16)
        modePicker.segmentCount=2;modePicker.setLabel("共同播放",forSegment:0);modePicker.setLabel("原生 AirPlay 跟随",forSegment:1)
        modePicker.trackingMode = .selectOne;modePicker.segmentStyle = .rounded
        modePicker.target=self;modePicker.action=#selector(modeChanged);modePicker.setAccessibilityLabel("播放模式")
        modePicker.translatesAutoresizingMaskIntoConstraints=false;modeGlass.content.addSubview(modePicker)
        NSLayoutConstraint.activate([
            modePicker.leadingAnchor.constraint(equalTo:modeGlass.content.leadingAnchor,constant:5),
            modePicker.trailingAnchor.constraint(equalTo:modeGlass.content.trailingAnchor,constant:-5),
            modePicker.topAnchor.constraint(equalTo:modeGlass.content.topAnchor,constant:5),
            modePicker.bottomAnchor.constraint(equalTo:modeGlass.content.bottomAnchor,constant:-5)
        ])
        root.addArrangedSubview(modeGlass);modeGlass.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
        modeGlass.heightAnchor.constraint(equalToConstant:38).isActive=true

        let heading=NSStackView();heading.orientation = .horizontal
        let label=NSTextField(labelWithString:"输出设备");label.font = .systemFont(ofSize:12,weight:.semibold);label.textColor = .secondaryLabelColor
        heading.addArrangedSubview(label);heading.addArrangedSubview(NSView())
        refreshButton.title="";refreshButton.image=NSImage(systemSymbolName:"arrow.clockwise",accessibilityDescription:"刷新设备")
        refreshButton.isBordered=false;refreshButton.toolTip="刷新设备";refreshButton.setAccessibilityLabel("刷新设备")
        refreshButton.target=self;refreshButton.action=#selector(refreshTapped);heading.addArrangedSubview(refreshButton)
        root.addArrangedSubview(heading);heading.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
        outputList.orientation = .vertical;outputList.alignment = .leading;outputList.spacing=8
        deviceScroll=DeviceListScrollView(stack:outputList)
        root.addArrangedSubview(deviceScroll)
        deviceScroll.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
        deviceScroll.heightAnchor.constraint(greaterThanOrEqualToConstant:120).isActive=true
        deviceScroll.setContentHuggingPriority(.defaultLow,for:.vertical)
        notice.textColor = .secondaryLabelColor;notice.font = .systemFont(ofSize:11)
        notice.maximumNumberOfLines=2
        root.addArrangedSubview(notice);notice.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true

        let footer=GlassPanel(radius:18)
        let footerRow=NSStackView();footerRow.orientation = .horizontal;footerRow.spacing=12
        status.font = .systemFont(ofSize:12,weight:.medium)
        status.lineBreakMode = .byTruncatingTail;status.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        footerRow.addArrangedSubview(status);footerRow.addArrangedSubview(NSView())
        button.target=self;button.action=#selector(toggle);button.bezelStyle = .rounded;button.controlSize = .large
        button.bezelColor = .systemBlue;button.contentTintColor = .white
        button.widthAnchor.constraint(greaterThanOrEqualToConstant:126).isActive=true
        footerRow.addArrangedSubview(button)
        footerRow.translatesAutoresizingMaskIntoConstraints=false;footer.content.addSubview(footerRow)
        NSLayoutConstraint.activate([
            footerRow.leadingAnchor.constraint(equalTo:footer.content.leadingAnchor,constant:14),
            footerRow.trailingAnchor.constraint(equalTo:footer.content.trailingAnchor,constant:-10),
            footerRow.centerYAnchor.constraint(equalTo:footer.content.centerYAnchor)
        ])
        root.addArrangedSubview(footer);footer.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
        footer.heightAnchor.constraint(equalToConstant:58).isActive=true
        let bottom=NSStackView();bottom.orientation = .horizontal;bottom.alignment = .top;bottom.spacing=8
        detail.font = .systemFont(ofSize:10);detail.textColor = .secondaryLabelColor;detail.maximumNumberOfLines=2
        detail.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        bottom.addArrangedSubview(detail)
        let log=NSButton(image:NSImage(systemSymbolName:"doc.text.magnifyingglass",accessibilityDescription:"查看日志")!,target:self,action:#selector(showLog))
        log.isBordered=false;log.toolTip="查看日志";log.setAccessibilityLabel("查看日志");bottom.addArrangedSubview(log)
        root.addArrangedSubview(bottom);bottom.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
    }
    private func refreshLocal(){
        let available=devices.allOutputDevices().filter { device in
            !devices.isAirPlay(device.id) && !device.name.contains("HomeSoundsSync")
        }
        for device in available.sorted(by: { $0.uid == "BuiltInSpeakerDevice" && $1.uid != "BuiltInSpeakerDevice" }) where localRows[device.uid]==nil {
            let row=SpeakerRow(id:device.uid,name:device.name,remote:false,target:self)
            row.check.action=#selector(localChanged);row.volume.action=#selector(localVolumeChanged);row.delay?.action=#selector(delayChanged)
            row.volume.doubleValue=preferences.object(forKey:"volume."+device.uid) as? Double ?? 0.6
            row.delay?.doubleValue=savedDelay(device.uid)
            if selectedLocal.isEmpty,localRows.isEmpty {selectedLocal.insert(device.uid)}
            row.check.state=selectedLocal.contains(device.uid) ? .on:.off
            row.updateDelay();row.updateVolume();localRows[device.uid]=row;append(row)
        }
        deviceScroll.needsLayout=true
        let uids=Set(available.map(\.uid))
        for uid in Array(localRows.keys) where !uids.contains(uid) {
            if let row=localRows.removeValue(forKey:uid){outputList.removeArrangedSubview(row.container);row.container.removeFromSuperview()}
        }
    }
    private func append(_ row:SpeakerRow){
        outputList.addArrangedSubview(row.container)
        row.container.widthAnchor.constraint(equalTo:outputList.widthAnchor).isActive=true
        deviceScroll.needsLayout=true
    }
    private func savedDelay(_ uid:String)->Double {
        preferences.object(forKey:mode.delayKey(for:uid)) as? Double
            ?? (mode == .nativeAirPlay ? 1250:Double(OwnToneService.bufferDurationMS))
    }
    private func updateModeUI(){
        modePicker.selectedSegment=mode == .relay ? 0:1
        for row in remoteRows.values{row.container.isHidden = !mode.usesBackend}
        deviceScroll.needsLayout=true
        for (uid,row) in localRows{row.delay?.doubleValue=savedDelay(uid);row.updateDelay()}
        notice.stringValue=mode == .nativeAirPlay
            ? "先连接 HomePod，再开启本地跟随。Mac 提前就增加延迟，落后就减少。"
            : "由应用连接 HomePod，并延迟 Mac 声音。视频画面不会自动补偿。"
        button.title=mode == .nativeAirPlay ? "开始本地跟随":"开始共同播放"
    }
    @objc private func modeChanged(){
        guard !busy,!engine.running else{return}
        let token=lifecycle.beginStop();lifecycle.finishStop(token)
        volumeWork?.cancel()
        mode=modePicker.selectedSegment == 1 ? .nativeAirPlay:.relay
        preferences.set(mode.rawValue,forKey:"playbackMode")
        if !mode.usesBackend{service.stop()}
        updateModeUI();Task{@MainActor in await refreshRemote()}
    }
    private func refreshNative(){
        refreshLocal()
        guard !engine.running,!busy else{return}
        let route=devices.defaultOutputDevice()
        let ready=devices.isAirPlay(route)
        status.stringValue=ready ? "原生 AirPlay 已就绪":"请先原生连接 HomePod"
        status.textColor = ready ? .secondaryLabelColor:.systemOrange
        detail.stringValue=ready ? "系统输出：\(devices.name(of:route))；选择本地扬声器后开始跟随。"
            : "在 TV App／系统声音中选择 HomePod，并确认正常播放。此模式不会替你建立连接。"
    }
    private func installRouteListener(){
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultOutputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        let listener:AudioObjectPropertyListenerBlock = { [weak self] _,_ in self?.checkNativeRoute() }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&address,DispatchQueue.main,listener)==noErr{routeListener=listener}
    }
    private func checkNativeRoute(){
        guard engine.running,engine.mode == .nativeAirPlay else{return}
        let route=devices.defaultOutputDevice()
        if !devices.isAirPlay(route) || devices.uid(of:route) != nativeRouteUID {
            stopPlayback(message:"原生 AirPlay 输出已改变，已停止 Mac 跟随。")
        }
    }
    @MainActor private func refreshRemote() async {
        guard mode.usesBackend else{refreshNative();return}
        guard !refreshing else{return};refreshing=true;defer{refreshing=false}
        refreshLocal()
        let generation=lifecycle.generation
        do {
            try service.start()
            let outputs=try await client.airplayOutputs()
            guard mode.usesBackend,lifecycle.isCurrent(generation), !busy else{return}
            backendFailCount=0
            let ids=Set(outputs.map(\.id))
            for id in Array(remoteRows.keys) where !ids.contains(id) {
                if let row=remoteRows.removeValue(forKey:id){outputList.removeArrangedSubview(row.container);row.container.removeFromSuperview()}
                if engine.running && selectedRemote.contains(id){stopPlayback(message:"HomePod 已离线，已恢复普通播放。")}
            }
            for output in outputs {
                if remoteRows[output.id]==nil {
                    let row=SpeakerRow(id:output.id,name:output.name,remote:true,target:self)
                    row.check.action=#selector(remoteChanged);row.volume.action=#selector(remoteVolumeChanged)
                    remoteRows[output.id]=row;append(row)
                    remoteVolumes[output.id]=preferences.object(forKey:"remoteVolume."+output.id) as? Int ?? min(50,output.volume)
                }
                let row=remoteRows[output.id]!
                row.check.state=selectedRemote.contains(output.id) ? .on:.off
                row.volume.doubleValue=Double(remoteVolumes[output.id] ?? output.volume)/100;row.updateVolume()
                if engine.running && selectedRemote.contains(output.id) && !output.selected {
                    stopPlayback(message:"HomePod 未保持连接，已停止共同播放。请查看日志与访问设置。")
                }
            }
            if !engine.running && !busy {
                status.stringValue=outputs.isEmpty ? "尚未发现 HomePod":"设备就绪，选择设备后开始"
                status.textColor = .secondaryLabelColor
                detail.stringValue=outputs.isEmpty ? "确认 HomePod 与 Mac 在同一局域网，家庭 App 的扬声器访问设为“同一网络上的任何人”。":"已找到 \(outputs.count) 个 AirPlay 设备；先播放一段普通音频，再开始共同播放。"
            }
        }catch{
            guard mode.usesBackend,lifecycle.isCurrent(generation), !busy else{return}
            backendFailCount+=1
            if engine.running && backendFailCount>=3 {stopPlayback(message:"HomePod 后端失去响应，已恢复普通播放。")}
            if !engine.running && !busy {
                status.stringValue="正在连接 HomePod 后端…";status.textColor = .secondaryLabelColor
                detail.stringValue=service.isRunning ? "首次启动需要几秒；若持续没有设备，请检查同一网络和本地网络权限。":error.localizedDescription
                if let code=service.exitStatus{detail.stringValue="后端已退出（\(code)），请查看日志。"}
            }
        }
    }
    @objc private func refreshTapped(){Task{@MainActor in await refreshRemote()}}
    @objc private func localChanged(_ sender:NSButton){
        guard let id=sender.identifier?.rawValue else{return}
        if sender.state == .on{selectedLocal.insert(id)}else{selectedLocal.remove(id)}
        saveSelection();if engine.running || busy{stopPlayback(message:"输出选择已改变，点击开始重新连接。")}
    }
    @objc private func remoteChanged(_ sender:NSButton){
        guard let id=sender.identifier?.rawValue else{return}
        if sender.state == .on{selectedRemote.insert(id)}else{selectedRemote.remove(id)}
        saveSelection();if engine.running || busy{stopPlayback(message:"输出选择已改变，点击开始重新连接。")}
    }
    private func saveSelection(){preferences.set(Array(selectedLocal),forKey:"selectedLocal");preferences.set(Array(selectedRemote),forKey:"selectedRemote")}
    @objc private func localVolumeChanged(_ sender:NSSlider){
        guard let id=sender.identifier?.rawValue else{return}
        localRows[id]?.updateVolume();preferences.set(sender.doubleValue,forKey:"volume."+id);engine.setGain(uid:id,g:sender.doubleValue)
    }
    @objc private func remoteVolumeChanged(_ sender:NSSlider){
        guard let id=sender.identifier?.rawValue else{return}
        remoteRows[id]?.updateVolume();let value=Int(sender.doubleValue*100);remoteVolumes[id]=value;preferences.set(value,forKey:"remoteVolume."+id)
        guard mode.usesBackend,engine.running,selectedRemote.contains(id) else{return}
        volumeWork?.cancel()
        let generation=lifecycle.generation
        let work=DispatchWorkItem{[weak self] in
            guard let self else{return}
            Task{@MainActor in
                guard self.mode.usesBackend,self.engine.running,self.lifecycle.isCurrent(generation) else{return}
                do{try await self.client.setVolume(id:id,volume:value)}catch{if self.lifecycle.isCurrent(generation){self.detail.stringValue=error.localizedDescription}}
            }
        }
        volumeWork=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.15,execute:work)
    }
    @objc private func delayChanged(_ sender:NSSlider){
        guard let id=sender.identifier?.rawValue else{return}
        preferences.set(sender.doubleValue,forKey:mode.delayKey(for:id));localRows[id]?.updateDelay();engine.setDelay(uid:id,ms:sender.doubleValue)
    }
    @objc private func toggle(){
        guard !busy else{return}
        if engine.running{stopPlayback(message:mode == .nativeAirPlay ? "已停止 Mac 跟随，原生 AirPlay 继续播放。":"已停止，恢复 Mac 普通播放。");return}
        guard let token=lifecycle.beginStart() else{return}
        busy=true;button.isEnabled=false;modePicker.isEnabled=false
        operation=Task{@MainActor in await startPlayback(token:token)}
    }
    private func requireCurrent(_ token:Int) throws {
        guard lifecycle.isCurrent(token), !Task.isCancelled else{throw CancellationError()}
    }
    @MainActor private func startPlayback(token:Int) async {
        let locals=selectedLocal.intersection(Set(localRows.keys))
        let remotes=mode.usesBackend ? selectedRemote.intersection(Set(remoteRows.keys)):[]
        defer{
            if lifecycle.isCurrent(token){
                lifecycle.finishStart(token,running:engine.running)
                busy=false;button.isEnabled=true;modePicker.isEnabled = !engine.running
                button.title=engine.running ? (mode == .nativeAirPlay ? "停止本地跟随":"停止共同播放"):(mode == .nativeAirPlay ? "开始本地跟随":"开始共同播放")
            }
        }
        guard !locals.isEmpty,(!mode.usesBackend || !remotes.isEmpty) else{alert(mode.usesBackend ? "请选择至少一个本地扬声器和一个 HomePod。":"请选择至少一个本地扬声器。");return}
        activeRemote=remotes
        status.stringValue=mode == .nativeAirPlay ? "正在启动 Mac 本地跟随…":"正在连接所选设备…"
        do{
            try requireCurrent(token)
            if mode.usesBackend {
                try service.start()
                let available=try await client.airplayOutputs();try requireCurrent(token)
                for output in available{
                    let selected=remotes.contains(output.id)
                    if selected{
                        try await client.setVolume(id:output.id,volume:remoteVolumes[output.id] ?? 50)
                        try requireCurrent(token)
                    }
                    try await client.setSelected(id:output.id,on:selected);try requireCurrent(token)
                }
                let confirmed=try await client.airplayOutputs();try requireCurrent(token)
                guard remotes.allSatisfy({id in confirmed.contains{$0.id==id && $0.selected}}) else{throw OwnToneClient.ClientError.invalidResponse}
            } else {
                let route=devices.defaultOutputDevice()
                guard devices.isAirPlay(route) else{throw OwnToneService.ServiceError.launch("请先在 TV／系统声音中原生连接 HomePod。")}
                nativeRouteUID=devices.uid(of:route)
            }
            try requireCurrent(token);try engine.start(mode:mode)
            for id in locals{
                guard let row=localRows[id],let device=devices.deviceID(forUID:id) else{continue}
                try engine.addOutput(uid:id,deviceID:device,delayMs:row.delay?.doubleValue ?? Double(OwnToneService.bufferDurationMS),gain:row.volume.doubleValue)
            }
            guard !engine.activeOutputUIDs.isEmpty else{throw OwnToneService.ServiceError.launch("本地扬声器无法启动")}
            if mode == .nativeAirPlay {
                let route=devices.defaultOutputDevice()
                guard devices.isAirPlay(route),devices.uid(of:route)==nativeRouteUID else{throw OwnToneService.ServiceError.launch("原生 AirPlay 输出已改变，请重新连接后再跟随。")}
            }
            flow.begin(frames:engine.framesCaptured,bytes:engine.bytesSent,now:ProcessInfo.processInfo.systemUptime,requiresBackend:mode.usesBackend)
            status.stringValue=mode == .nativeAirPlay ? "等待捕获原生 AirPlay 音频…":"等待系统音频与 HomePod 接收…";status.textColor = .systemOrange
            detail.stringValue="首次使用请允许系统音频录制；然后播放一段普通音频。"
        }catch{
            guard lifecycle.isCurrent(token) else{return}
            engine.stop()
            for id in remotes{try? await client.setSelected(id:id,on:false);if !lifecycle.isCurrent(token){return}}
            activeRemote=[]
            nativeRouteUID=nil
            status.stringValue=mode == .nativeAirPlay ? "本地跟随未启动，原生连接未被接管。":"启动未完成，已恢复普通播放。";status.textColor = .systemOrange
            detail.stringValue=error.localizedDescription;alert(error.localizedDescription)
        }
    }
    private func stopPlayback(message:String){
        let token=lifecycle.beginStop()
        let previous=operation
        engine.stop();nativeRouteUID=nil;volumeWork?.cancel();button.title="正在停止…";button.isEnabled=false;modePicker.isEnabled=false;busy=true
        status.stringValue=message;status.textColor = .secondaryLabelColor;detail.stringValue=""
        let ids=activeRemote
        operation=Task{@MainActor in
            await previous?.value
            for id in ids{try? await client.setSelected(id:id,on:false)}
            guard lifecycle.isCurrent(token) else{return}
            activeRemote=[];lifecycle.finishStop(token);busy=false;button.isEnabled=true;modePicker.isEnabled=true
            button.title=mode == .nativeAirPlay ? "开始本地跟随":"开始共同播放"
        }
    }
    private func checkFlow(){
        checkNativeRoute()
        guard engine.running else{return}
        if let reason=engine.discontinuityReason{
            stopPlayback(message:"音频传输中断，已恢复普通播放。")
            detail.stringValue=reason;return
        }
        switch flow.evaluate(frames:engine.framesCaptured,bytes:engine.bytesSent,connected:engine.backendConnected,now:ProcessInfo.processInfo.systemUptime){
        case .flowing:
            status.stringValue=mode == .nativeAirPlay ? "Mac 本地跟随正在播放":"系统音频正在传输";status.textColor = .systemGreen
            detail.stringValue=mode == .nativeAirPlay ? "HomePod 由 TV／系统保持原生连接；Mac 提前就增加延迟，落后就减少。请以实际听音确认同步。":"请确认 HomePod 实际有声；若有回声，调节 Mac 的同步延迟。传输状态不等于已验证听音同步。"
        case .waiting:break
        case .stalled:
            stopPlayback(message:mode == .nativeAirPlay ? "音频捕获已停滞，已停止 Mac 跟随。":"系统音频或后端传输已停滞，已恢复普通播放。")
            detail.stringValue="确认系统音频录制权限已允许，播放普通音频后重试；受保护内容可能无法捕获。"
        }
    }
    private func showWindow(){window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
    @objc private func openPanel(){showWindow()}
    @objc private func menuStop(){stopPlayback(message:mode == .nativeAirPlay ? "已停止 Mac 跟随，原生 AirPlay 继续播放。":"已停止共同播放。")}
    @objc private func showLog(){NSWorkspace.shared.open(OwnToneService.logURL)}
    @objc private func about(){alert("Mac HomePod 同播 \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "")\n基于 HomeSounds Sync（MIT）。共同播放使用 OwnTone 后端；原生跟随只增加本地输出。\n本地构建版本，尚未公证。")}
    @objc private func showHelp(){alert("原生 AirPlay 跟随：\n1. 先在 TV／系统声音中选择 HomePod，确认有声且画面同步。\n2. 选择原生 AirPlay 跟随模式，勾选本地扬声器后开始。\n3. Mac 提前就增加延迟，落后就减少。两种模式分别记住延迟。\n停止跟随只停止本地副本；系统离开 AirPlay 输出时会自动停止跟随。\n\n共同播放：\nMac 声音输出保持本地扬声器；选择 Mac 和 HomePod 后开始，并允许系统音频录制和本地网络权限。软件连接 HomePod，此模式不会自动补偿视频画面。\n\n两种模式都需要系统音频录制权限；受保护内容或 App 内直接投送的音频可能无法捕获。")}
    private func alert(_ text:String){let alert=NSAlert();alert.messageText="Mac HomePod 同播";alert.informativeText=text;alert.addButton(withTitle:"知道了");alert.runModal()}
}

private final class SpeakerRow {
    let container=DeviceCard()
    let check:NSButton
    let volume=NSSlider(value:0.5,minValue:0,maxValue:1,target:nil,action:nil)
    let delay:NSSlider?
    private let delayLabel=NSTextField(labelWithString:"")
    private let volumeLabel=NSTextField(labelWithString:"")
    init(id:String,name:String,remote:Bool,target:AnyObject){
        check=NSButton(checkboxWithTitle:name,target:target,action:nil)
        check.identifier=NSUserInterfaceItemIdentifier(id);check.font = .systemFont(ofSize:12,weight:.medium)
        check.setAccessibilityLabel((remote ? "HomePod / AirPlay · ":"此 Mac · ")+name)
        check.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        check.cell?.lineBreakMode = .byTruncatingTail
        volume.target=target;volume.identifier=NSUserInterfaceItemIdentifier(id);volume.widthAnchor.constraint(equalToConstant:92).isActive=true
        volume.controlSize = .small;volume.setAccessibilityLabel(name+" 音量")
        volumeLabel.font = .monospacedDigitSystemFont(ofSize:10,weight:.regular);volumeLabel.textColor = .secondaryLabelColor
        volumeLabel.alignment = .right;volumeLabel.widthAnchor.constraint(equalToConstant:29).isActive=true
        container.orientation = .vertical;container.alignment = .leading;container.spacing=8
        container.edgeInsets=NSEdgeInsets(top:12,left:12,bottom:12,right:12)
        let line=NSStackView();line.orientation = .horizontal;line.spacing=8
        let symbol=remote ? "homepod.fill":(id == "BuiltInSpeakerDevice" ? "laptopcomputer":"speaker.wave.2.fill")
        let icon=NSImageView(image:NSImage(systemSymbolName:symbol,accessibilityDescription:nil) ?? NSImage())
        icon.contentTintColor = .systemBlue;icon.widthAnchor.constraint(equalToConstant:22).isActive=true
        line.addArrangedSubview(icon);line.addArrangedSubview(check);line.addArrangedSubview(NSView())
        line.addArrangedSubview(volume);line.addArrangedSubview(volumeLabel)
        container.addArrangedSubview(line);line.widthAnchor.constraint(equalTo:container.widthAnchor,constant:-24).isActive=true
        if remote{delay=nil}else{
            let slider=NSSlider(value:Double(OwnToneService.bufferDurationMS),minValue:0,maxValue:5000,target:target,action:nil)
            slider.identifier=NSUserInterfaceItemIdentifier(id);slider.setAccessibilityLabel(name+" 同步延迟");slider.controlSize = .small
            delay=slider
            let second=NSStackView();second.orientation = .horizontal;second.spacing=12
            delayLabel.font = .monospacedDigitSystemFont(ofSize:11,weight:.regular);delayLabel.textColor = .secondaryLabelColor
            delayLabel.widthAnchor.constraint(equalToConstant:106).isActive=true
            second.addArrangedSubview(delayLabel);second.addArrangedSubview(slider)
            container.addArrangedSubview(second);second.widthAnchor.constraint(equalTo:container.widthAnchor,constant:-24).isActive=true
        }
        updateVolume()
    }
    func updateDelay(){delayLabel.stringValue="延迟  \(Int(delay?.doubleValue ?? 0)) ms"}
    func updateVolume(){volumeLabel.stringValue="\(Int((volume.doubleValue*100).rounded()))%"}
}
