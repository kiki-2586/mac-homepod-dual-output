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
        selectedRemote=Set(preferences.stringArray(forKey:"selectedRemote") ?? [])
        selectedLocal=Set(preferences.stringArray(forKey:"selectedLocal") ?? [])
        makeMenu();makeWindow();refreshLocal()
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
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:650),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Mac HomePod 同播";window.minSize=NSSize(width:600,height:600);window.center();window.delegate=self
        let root=NSStackView();root.orientation = .vertical;root.alignment = .leading;root.spacing=16
        root.translatesAutoresizingMaskIntoConstraints=false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:24),root.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-24),root.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:22),root.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-22)])
        let title=NSTextField(labelWithString:"让 Mac 和 HomePod 一起播放")
        title.font = .systemFont(ofSize:23,weight:.semibold)
        root.addArrangedSubview(title)
        let subtitle=NSTextField(labelWithString:"音源：整个 Mac 的系统声音")
        subtitle.textColor = .secondaryLabelColor;root.addArrangedSubview(subtitle)
        let divider=NSBox();divider.boxType = .separator;root.addArrangedSubview(divider);divider.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
        let heading=NSStackView();heading.orientation = .horizontal
        let label=NSTextField(labelWithString:"输出设备");label.font = .systemFont(ofSize:15,weight:.semibold)
        heading.addArrangedSubview(label);heading.addArrangedSubview(NSView())
        refreshButton.target=self;refreshButton.action=#selector(refreshTapped);heading.addArrangedSubview(refreshButton)
        root.addArrangedSubview(heading);heading.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
        outputList.orientation = .vertical;outputList.alignment = .leading;outputList.spacing=12;outputList.translatesAutoresizingMaskIntoConstraints=false
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.drawsBackground=false;scroll.documentView=outputList
        root.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:190).isActive=true
        outputList.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor).isActive=true
        let notice=NSTextField(wrappingLabelWithString:"同步需要让 Mac 扬声器等待 HomePod 的缓冲，可用节拍微调延迟。看视频时画面不会自动延后。")
        notice.textColor = .secondaryLabelColor;notice.font = .systemFont(ofSize:12)
        root.addArrangedSubview(notice);notice.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
        status.font = .systemFont(ofSize:14,weight:.medium);root.addArrangedSubview(status)
        detail.font = .systemFont(ofSize:12);detail.textColor = .secondaryLabelColor
        root.addArrangedSubview(detail);detail.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
        let footer=NSStackView();footer.orientation = .horizontal;footer.spacing=10
        let help=NSButton(title:"使用说明",target:self,action:#selector(showHelp));footer.addArrangedSubview(help)
        let log=NSButton(title:"查看日志",target:self,action:#selector(showLog));footer.addArrangedSubview(log)
        footer.addArrangedSubview(NSView());button.target=self;button.action=#selector(toggle);button.bezelStyle = .rounded
        button.controlSize = .large;footer.addArrangedSubview(button)
        root.addArrangedSubview(footer);footer.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
    }
    private func refreshLocal(){
        let available=devices.allOutputDevices().filter { device in
            var address=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyTransportType,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            var transport:UInt32=0;var size=UInt32(MemoryLayout<UInt32>.size)
            _=AudioObjectGetPropertyData(device.id,&address,0,nil,&size,&transport)
            return transport != kAudioDeviceTransportTypeAirPlay && !device.name.contains("HomeSoundsSync")
        }
        for device in available.sorted(by: { $0.uid == "BuiltInSpeakerDevice" && $1.uid != "BuiltInSpeakerDevice" }) where localRows[device.uid]==nil {
            let row=SpeakerRow(id:device.uid,name:device.name,remote:false,target:self)
            row.check.action=#selector(localChanged);row.volume.action=#selector(localVolumeChanged);row.delay?.action=#selector(delayChanged)
            row.volume.doubleValue=preferences.object(forKey:"volume."+device.uid) as? Double ?? 0.6
            row.delay?.doubleValue=preferences.object(forKey:"delay."+device.uid) as? Double ?? Double(OwnToneService.bufferDurationMS)
            if selectedLocal.isEmpty,localRows.isEmpty {selectedLocal.insert(device.uid)}
            row.check.state=selectedLocal.contains(device.uid) ? .on:.off
            row.updateDelay();localRows[device.uid]=row;append(row)
        }
        let uids=Set(available.map(\.uid))
        for uid in Array(localRows.keys) where !uids.contains(uid) {
            if let row=localRows.removeValue(forKey:uid){outputList.removeArrangedSubview(row.container);row.container.removeFromSuperview()}
        }
    }
    private func append(_ row:SpeakerRow){
        outputList.addArrangedSubview(row.container)
        row.container.widthAnchor.constraint(equalTo:outputList.widthAnchor).isActive=true
    }
    @MainActor private func refreshRemote() async {
        guard !refreshing else{return};refreshing=true;defer{refreshing=false}
        refreshLocal()
        let generation=lifecycle.generation
        do {
            try service.start()
            let outputs=try await client.airplayOutputs()
            guard lifecycle.isCurrent(generation), !busy else{return}
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
                row.volume.doubleValue=Double(remoteVolumes[output.id] ?? output.volume)/100
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
            guard lifecycle.isCurrent(generation), !busy else{return}
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
        preferences.set(sender.doubleValue,forKey:"volume."+id);engine.setGain(uid:id,g:sender.doubleValue)
    }
    @objc private func remoteVolumeChanged(_ sender:NSSlider){
        guard let id=sender.identifier?.rawValue else{return}
        let value=Int(sender.doubleValue*100);remoteVolumes[id]=value;preferences.set(value,forKey:"remoteVolume."+id)
        guard engine.running,selectedRemote.contains(id) else{return}
        volumeWork?.cancel()
        let work=DispatchWorkItem{[weak self] in
            guard let self else{return}
            Task{@MainActor in do{try await self.client.setVolume(id:id,volume:value)}catch{self.detail.stringValue=error.localizedDescription}}
        }
        volumeWork=work;DispatchQueue.main.asyncAfter(deadline:.now()+0.15,execute:work)
    }
    @objc private func delayChanged(_ sender:NSSlider){
        guard let id=sender.identifier?.rawValue else{return}
        preferences.set(sender.doubleValue,forKey:"delay."+id);localRows[id]?.updateDelay();engine.setDelay(uid:id,ms:sender.doubleValue)
    }
    @objc private func toggle(){
        guard !busy else{return}
        if engine.running{stopPlayback(message:"已停止，恢复 Mac 普通播放。");return}
        guard let token=lifecycle.beginStart() else{return}
        busy=true;button.isEnabled=false
        operation=Task{@MainActor in await startPlayback(token:token)}
    }
    private func requireCurrent(_ token:Int) throws {
        guard lifecycle.isCurrent(token), !Task.isCancelled else{throw CancellationError()}
    }
    @MainActor private func startPlayback(token:Int) async {
        let locals=selectedLocal.intersection(Set(localRows.keys))
        let remotes=selectedRemote.intersection(Set(remoteRows.keys))
        defer{
            if lifecycle.isCurrent(token){
                lifecycle.finishStart(token,running:engine.running)
                busy=false;button.isEnabled=true;button.title=engine.running ? "停止共同播放":"开始共同播放"
            }
        }
        guard !locals.isEmpty,!remotes.isEmpty else{alert("请选择至少一个本地扬声器和一个 HomePod。");return}
        activeRemote=remotes
        status.stringValue="正在连接所选设备…"
        do{
            try requireCurrent(token);try service.start()
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
            try requireCurrent(token);try engine.start()
            for id in locals{
                guard let row=localRows[id],let device=devices.deviceID(forUID:id) else{continue}
                try engine.addOutput(uid:id,deviceID:device,delayMs:row.delay?.doubleValue ?? Double(OwnToneService.bufferDurationMS),gain:row.volume.doubleValue)
            }
            guard !engine.activeOutputUIDs.isEmpty else{throw OwnToneService.ServiceError.launch("本地扬声器无法启动")}
            flow.begin(frames:engine.framesCaptured,bytes:engine.bytesSent,now:ProcessInfo.processInfo.systemUptime)
            status.stringValue="等待系统音频与 HomePod 接收…";status.textColor = .systemOrange
            detail.stringValue="首次使用请允许系统音频录制；然后播放一段普通音频。"
        }catch{
            guard lifecycle.isCurrent(token) else{return}
            engine.stop()
            for id in remotes{try? await client.setSelected(id:id,on:false);if !lifecycle.isCurrent(token){return}}
            activeRemote=[]
            status.stringValue="启动未完成，已恢复普通播放。";status.textColor = .systemOrange
            detail.stringValue=error.localizedDescription;alert(error.localizedDescription)
        }
    }
    private func stopPlayback(message:String){
        let token=lifecycle.beginStop()
        let previous=operation
        engine.stop();volumeWork?.cancel();button.title="正在停止…";button.isEnabled=false;busy=true
        status.stringValue=message;status.textColor = .secondaryLabelColor;detail.stringValue=""
        let ids=activeRemote
        operation=Task{@MainActor in
            await previous?.value
            for id in ids{try? await client.setSelected(id:id,on:false)}
            guard lifecycle.isCurrent(token) else{return}
            activeRemote=[];lifecycle.finishStop(token);busy=false;button.isEnabled=true;button.title="开始共同播放"
        }
    }
    private func checkFlow(){
        guard engine.running else{return}
        if let reason=engine.discontinuityReason{
            stopPlayback(message:"音频传输中断，已恢复普通播放。")
            detail.stringValue=reason;return
        }
        switch flow.evaluate(frames:engine.framesCaptured,bytes:engine.bytesSent,connected:engine.backendConnected,now:ProcessInfo.processInfo.systemUptime){
        case .flowing:
            status.stringValue="系统音频正在传输";status.textColor = .systemGreen
            detail.stringValue="请确认 HomePod 实际有声；若有回声，调节 Mac 的同步延迟。传输状态不等于已验证听音同步。"
        case .waiting:break
        case .stalled:
            stopPlayback(message:"系统音频或后端传输已停滞，已恢复普通播放。")
            detail.stringValue="确认系统音频录制权限已允许，播放普通音频后重试；受保护内容可能无法捕获。"
        }
    }
    private func showWindow(){window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)}
    @objc private func openPanel(){showWindow()}
    @objc private func menuStop(){stopPlayback(message:"已停止共同播放。")}
    @objc private func showLog(){NSWorkspace.shared.open(OwnToneService.logURL)}
    @objc private func about(){alert("Mac HomePod 同播 0.1.0\n基于 HomeSounds Sync（MIT），使用独立 OwnTone 后端。\n本地构建版本，尚未公证。")}
    @objc private func showHelp(){alert("1. Mac 和 HomePod 连接同一局域网。\n2. 家庭 App → 家庭设置 → 扬声器与电视访问：同一网络上的任何人。\n3. macOS 声音输出保持 Mac 内置扬声器。\n4. 勾选 Mac 和 HomePod，点击开始，并允许系统音频录制和本地网络权限。\n5. 用节拍音乐微调 Mac 延迟：Mac 提前就增加延迟，Mac 落后就减少。\n\nAirPlay 缓冲会增加总延迟，视频画面不会自动补偿；受保护内容可能无法捕获。\n停止或退出后恢复普通声音，后台服务随应用退出。")}
    private func alert(_ text:String){let alert=NSAlert();alert.messageText="Mac HomePod 同播";alert.informativeText=text;alert.addButton(withTitle:"知道了");alert.runModal()}
}

private final class SpeakerRow {
    let container=NSStackView()
    let check:NSButton
    let volume=NSSlider(value:0.5,minValue:0,maxValue:1,target:nil,action:nil)
    let delay:NSSlider?
    private let delayLabel=NSTextField(labelWithString:"")
    init(id:String,name:String,remote:Bool,target:AnyObject){
        check=NSButton(checkboxWithTitle:(remote ? "HomePod / AirPlay · ":"此 Mac · ")+name,target:target,action:nil)
        check.identifier=NSUserInterfaceItemIdentifier(id)
        volume.target=target;volume.identifier=NSUserInterfaceItemIdentifier(id);volume.widthAnchor.constraint(equalToConstant:150).isActive=true
        volume.setAccessibilityLabel(name+" 音量")
        container.orientation = .vertical;container.alignment = .leading;container.spacing=6
        let line=NSStackView();line.orientation = .horizontal;line.spacing=12
        line.addArrangedSubview(check);line.addArrangedSubview(NSView());line.addArrangedSubview(volume)
        container.addArrangedSubview(line);line.widthAnchor.constraint(equalTo:container.widthAnchor).isActive=true
        if remote{delay=nil}else{
            let slider=NSSlider(value:Double(OwnToneService.bufferDurationMS),minValue:0,maxValue:5000,target:target,action:nil)
            slider.identifier=NSUserInterfaceItemIdentifier(id);slider.setAccessibilityLabel(name+" 同步延迟")
            delay=slider
            let second=NSStackView();second.orientation = .horizontal;second.spacing=12
            delayLabel.font = .systemFont(ofSize:11);delayLabel.textColor = .secondaryLabelColor
            delayLabel.widthAnchor.constraint(equalToConstant:158).isActive=true
            second.addArrangedSubview(delayLabel);second.addArrangedSubview(slider)
            container.addArrangedSubview(second);second.widthAnchor.constraint(equalTo:container.widthAnchor).isActive=true
        }
    }
    func updateDelay(){delayLabel.stringValue="Mac 同步延迟：\(Int(delay?.doubleValue ?? 0)) ms"}
}
