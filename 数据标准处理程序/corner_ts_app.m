function corner_ts_app
% 角反射体 TS 处理界面。支持单频与频率扫描，每列对应一个原始脉冲。
project = fileparts(fileparts(mfilename('fullpath')));
raw = []; bp = []; mf = []; fs = []; folder = ''; result = [];
activeChannel = '';
clean = []; cleanPulses = []; cleanView = '脉冲维去背景';
scaleSettings = struct('wave',struct('mode','自动','limits',[]), ...
                       'ts',struct('mode','自动','limits',[]));
pickStart = []; gateLines = gobjects(0);

fig = uifigure('Name','角反射体试验 · TS 处理','WindowState','maximized');
layout = uigridlayout(fig,[1 2],'ColumnWidth',{355,'1x'},'Padding',[12 12 12 12]);
% 左栏的设置可以滚动，状态栏始终可见。
sidebar = uigridlayout(layout,[2 1],'RowHeight',{'1x',54},'Padding',[0 0 0 0],'RowSpacing',5);
rowHeights = repmat({27},1,31);
rowHeights([1 4 9 14 20 24 29]) = {24};
form = uigridlayout(sidebar,[31 3],'ColumnWidth',{132,'1x','1x'}, ...
    'RowHeight',rowHeights,'RowSpacing',4,'ColumnSpacing',6,'Padding',[6 4 8 4], ...
    'BackgroundColor',[0.98 0.985 0.99],'Scrollable','on');

sectionHeading(1,'数据与通道');
folderButton = uibutton(form,'Text','选择采集文件夹','ButtonPushedFcn',@loadFolder);
folderButton.Layout.Row = 2; folderButton.Layout.Column = [1 2];
channelMenu = uidropdown(form,'Items',{'通道'},'Enable','off','Tooltip','切换要读取和处理的通道', ...
    'ValueChangedFcn',@changeChannel);
channelMenu.Layout.Row = 2; channelMenu.Layout.Column = 3;
recordLabel = uilabel(form,'Text','尚未加载数据'); wide(recordLabel,3);

sectionHeading(4,'信号与滤波');
band = fields(5,'带通频带 / kHz',[15 45],@filterChanged);
chirp = fields(6,'LFM 起止 / kHz',[20 40],@filterChanged);
width = fields(7,'LFM 脉宽 / ms',0.1,@filterChanged);
bpButton = uibutton(form,'Text','带通滤波','ButtonPushedFcn',@filterData);
bpButton.Layout.Row = 8; bpButton.Layout.Column = 1;
mfButton = uibutton(form,'Text','匹配滤波','ButtonPushedFcn',@filterData);
mfButton.Layout.Row = 8; mfButton.Layout.Column = [2 3];

sectionHeading(9,'扫描范围与时间窗');
scan = fields(10,'扫描脉冲（首 / 末）',[1 1],@gateChanged);
angle = fields(11,'首末角度 / °',[0 360],@invalidate);
direct = fields(12,'直达波窗 / ms',[0 0],@gateChanged);
echo = fields(13,'回波窗 / ms',[0 0],@gateChanged);
sectionHeading(14,'固定横带背景抑制');
bgWindow = fields(15,'背景时间窗 / ms',[0 0],@backgroundChanged);
bgMode = uidropdown(form,'Items',{'脉冲维高通','参考脉冲均值相减'},'ValueChangedFcn',@backgroundModeChanged);
wide(bgMode,16);
cutoff = fields(17,'截止 / (周期/脉冲)',0.01,@backgroundChanged);
cutoff.Tooltip = '半功率截止频率，0.01 对应 100 次脉冲一个周期';
bgRef = fields(18,'背景参考脉冲（首/末）',[1 1],@backgroundChanged);
set(bgRef,'Enable','off');
bgButton = uibutton(form,'Text','应用到扫描脉冲','Enable','off','ButtonPushedFcn',@removeBackground);
wide(bgButton,19);

sectionHeading(20,'收发距离与直达波参考');
dist = fields(21,'距离 L / r（m）',[2.46 1.43],@invalidate);
dist(1).Tooltip = '发射换能器到目标的距离'; dist(2).Tooltip = '水听器到目标的距离';
mode = uidropdown(form,'Items',{'逐脉冲直达波参考','固定脉冲直达波参考'}, ...
    'ValueChangedFcn',@modeChanged); wide(mode,22);
ref = fields(23,'固定参考脉冲',1,@invalidate); ref.Enable = 'off';

sectionHeading(24,'目标强度计算');
freq = fields(25,'TS 频点 / kHz',30,@frequencyChanged);
sweepBand = fields(26,'扫频范围 / kHz',[20 40],@sweepChanged);
step = fields(27,'扫频间隔 / kHz',0.2,@sweepChanged);
singleButton = uibutton(form,'Text','计算单频 TS','ButtonPushedFcn',@calculate);
singleButton.Layout.Row = 28; singleButton.Layout.Column = 1;
sweepButton = uibutton(form,'Text','计算全频段 TS','ButtonPushedFcn',@calculateSweep);
sweepButton.Layout.Row = 28; sweepButton.Layout.Column = [2 3];

sectionHeading(29,'结果导出');
saveButton = uibutton(form,'Text','导出结果 MAT','Enable','off','ButtonPushedFcn',@saveResult);
saveButton.Layout.Row = 30; saveButton.Layout.Column = 1;
plotButton = uibutton(form,'Text','导出当前图 PNG + FIG','Enable','off','ButtonPushedFcn',@savePlot);
plotButton.Layout.Row = 30; plotButton.Layout.Column = [2 3];
bundle = uibutton(form,'Text','导出全部图表与数据','Enable','off','ButtonPushedFcn',@exportBundle);
wide(bundle,31);
footer = uigridlayout(sidebar,[1 2],'ColumnWidth',{'1x',78},'Padding',[4 4 4 4], ...
    'ColumnSpacing',4,'BackgroundColor',[0.91 0.95 0.96]);
status = uilabel(footer,'Text','请选择一次采集的日期时间文件夹。','WordWrap','on', ...
    'FontColor',[0.12 0.27 0.32],'BackgroundColor',[0.91 0.95 0.96]);
refreshButton = uibutton(footer,'Text','刷新视图','Tooltip','按当前选窗和色阶重绘本页', ...
    'Enable','off','ButtonPushedFcn',@refreshView);

tabs = uitabgroup(layout);
waveTab = uitab(tabs,'Title','波形与选窗'); resultTab = uitab(tabs,'Title','TS 结果');
barColor = [0.92 0.95 0.96]; ink = [0.12 0.28 0.33];
waveFrame = uigridlayout(waveTab,[1 1],'RowHeight',{'1x'},'ColumnWidth',{'1x'}, ...
    'Padding',[0 0 0 0]);
waveViewport = uipanel(waveFrame,'BorderType','none','AutoResizeChildren','off');
waveLayout = uigridlayout(waveViewport,[6 1],'RowHeight',{40,420,36,20,36,420}, ...
    'Padding',[12 10 12 10],'RowSpacing',4,'BackgroundColor','white','Scrollable','on');
bar = uigridlayout(waveLayout,[1 6],'ColumnWidth',{36,106,36,150,122,'1x'}, ...
    'Padding',[8 4 8 4],'ColumnSpacing',6,'BackgroundColor',barColor);
uilabel(bar,'Text','波形','FontWeight','bold','FontColor',ink);
view = uidropdown(bar,'Items',{'原始波形','带通波形','匹配滤波',cleanView},'ValueChangedFcn',@changeView);
uilabel(bar,'Text','选窗','FontWeight','bold','FontColor',ink);
pick = uidropdown(bar,'Items',{'点击查看脉冲','点两次选扫描范围','点两次选直达波窗','点两次选回波窗','点两次选背景窗'}, ...
    'ValueChangedFcn',@armPick);
uibutton(bar,'Text','显示整组波形图','ButtonPushedFcn',@drawMap, ...
    'BackgroundColor',[0.16 0.36 0.41],'FontColor','white');
map = uiaxes(waveLayout);
waveScale = scaleBar(waveLayout);
waveInfo = uilabel(waveLayout,'Text','','FontSize',11,'FontColor',ink);
traceBar = uigridlayout(waveLayout,[1 3],'ColumnWidth',{64,84,'1x'}, ...
    'Padding',[8 3 8 3],'ColumnSpacing',6,'BackgroundColor',barColor);
uilabel(traceBar,'Text','查看脉冲','FontWeight','bold','FontColor',ink);
pulse = uieditfield(traceBar,'numeric','Value',1,'RoundFractionalValues','on','Limits',[1 Inf], ...
    'ValueChangedFcn',@showTrace);
trace = uiaxes(waveLayout);
resultLayout = uigridlayout(resultTab,[5 1],'RowHeight',{40,'1x',0,0,54}, ...
    'Padding',[12 10 12 10],'RowSpacing',4,'BackgroundColor','white');
figureNames = {'单频 TS','带通回波时间–角度图','多频点 TS–角度曲线','多角度 TS–频率曲线', ...
    'TS 频率–角度谱','频带能量平均 TS–角度曲线','角度能量平均 TS–频率曲线'};
resultBar = uigridlayout(resultLayout,[1 3],'ColumnWidth',{52,230,'1x'}, ...
    'Padding',[8 4 8 4],'ColumnSpacing',6,'BackgroundColor',barColor);
uilabel(resultBar,'Text','结果图','FontWeight','bold','FontColor',ink);
figureChoice = uidropdown(resultBar,'Items',figureNames(1),'ValueChangedFcn',@showResult);
curve = uiaxes(resultLayout);
resultScale = scaleBar(resultLayout); resultScale.row.Visible = 'off';
resultInfo = uilabel(resultLayout,'Text','','FontSize',11,'FontColor',ink);
stats = uilabel(resultLayout,'Text','等待计算','WordWrap','on','FontColor',ink, ...
    'BackgroundColor',barColor);
xlabel(map,'原始脉冲序号'); ylabel(map,'时间 / ms');
xlabel(trace,'时间 / ms'); ylabel(trace,'幅值');
xlabel(curve,'角度 / °'); ylabel(curve,'TS / dB');
configurePreview(map); configurePreview(trace); configurePreview(curve);
pbaspect(trace,[2 1 1]);
waveViewport.SizeChangedFcn = @sizeWavePage;
sizeWavePage();
drawnow;
scroll(waveLayout,'top');
fig.WindowButtonUpFcn = @captureDraggedScale;
    function sizeWavePage(varargin)
        % 顶部操作栏、热图及其色阶说明占一屏；下一屏用于浏览单条脉冲。
        viewportPixels = getpixelposition(waveViewport);
        height = floor(viewportPixels(4));
        topRows = 40 + 36 + 20 + 3*waveLayout.RowSpacing;
        padding = sum(waveLayout.Padding([2 4]));
        heatHeight = max(240,height-padding-topRows);
        % 单脉冲波形占满整列，按 2:1 的宽高比安排高度。
        traceWidth = max(1,viewportPixels(3)-sum(waveLayout.Padding([1 3])));
        traceHeight = ceil(traceWidth/2);
        waveLayout.RowHeight = {40,heatHeight,36,20,36,traceHeight};
    end
    function refreshView(varargin)
        if isempty(raw), return; end
        captureDraggedScale();
        if tabs.SelectedTab==waveTab
            im = findobj(map,'Type','image');
            if ~isempty(im)
                waveInfo.Text = applyScale(map,im,scaleSettings.wave,true);
                syncScale(waveScale,map,scaleSettings.wave,'波形色阶');
                drawGates();
            end
            showTrace();
            status.Text = sprintf('已刷新 %s 的波形视图 · 脉冲 %d',activeChannel,pulse.Value);
        elseif ~isempty(result)
            showResult();
            status.Text = ['已刷新 ' result.channel ' · ' figureChoice.Value];
        else
            status.Text = '当前参数尚无 TS 结果，请先计算。';
        end
    end
    function wide(control,row)
        control.Layout.Row = row; control.Layout.Column = [1 3];
    end
    function sectionHeading(row,label)
        heading = uilabel(form,'Text',['  ' label],'FontWeight','bold', ...
            'FontColor',[0.10 0.28 0.34],'BackgroundColor',[0.87 0.92 0.94]);
        wide(heading,row);
    end
    function controls = scaleBar(parent)
        row = uigridlayout(parent,[1 8],'ColumnWidth',{64,90,32,68,32,68,92,'1x'}, ...
            'Padding',[8 3 8 3],'ColumnSpacing',5,'BackgroundColor',[0.96 0.97 0.98]);
        controls.row = row;
        controls.label = uilabel(row,'Text','波形色阶','FontWeight','bold','FontColor',ink);
        controls.mode = uidropdown(row,'Items',{'自动','完整范围','锁定'}, ...
            'ValueChangedFcn',@(src,~) editScale(src,false));
        uilabel(row,'Text','下限');
        controls.low = uieditfield(row,'numeric','Limits',[-Inf Inf]);
        uilabel(row,'Text','上限');
        controls.high = uieditfield(row,'numeric','Limits',[-Inf Inf],'Value',1);
        uibutton(row,'Text','应用并锁定','ButtonPushedFcn',@(src,~) editScale(src,true), ...
            'BackgroundColor',[0.86 0.91 0.93],'FontColor',ink);
    end
    function editScale(src,manual)
        if isequal(src.Parent,waveScale.row)
            controls = waveScale; group = 'wave'; ax = map;
        else
            controls = resultScale; ax = curve;
            if strcmp(figureChoice.Value,figureNames{5}), group = 'ts'; else, group = 'wave'; end
        end
        setting = scaleSettings.(group);
        if manual
            bounds = [controls.low.Value controls.high.Value];
            if any(~isfinite(bounds)) || bounds(1)>=bounds(2)
                uialert(fig,'请输入有限且下限小于上限的两个数值。','色阶范围');
                return
            end
            setting.mode = '锁定'; setting.limits = bounds;
        else
            setting.mode = controls.mode.Value;
            if strcmp(setting.mode,'锁定')
                if ~isappdata(ax,'scaleBounds') || isempty(getappdata(ax,'scaleBounds'))
                    controls.mode.Value = scaleSettings.(group).mode;
                    uialert(fig,'请先显示有效热图，或输入上下限后点击“应用并锁定”。','锁定当前色阶');
                    return
                end
                setting.limits = visibleScale(ax);
            else
                setting.limits = [];
            end
        end
        scaleSettings.(group) = setting;
        if ~isempty(result), result.colorScale = scaleSettings; end
        if strcmp(group,'wave')
            waveScale.mode.Value = setting.mode;
            im = findobj(map,'Type','image');
            if ~isempty(im)
                waveInfo.Text = applyScale(map,im,setting,true);
            end
            syncScale(waveScale,map,setting,'波形色阶');
        end
        if ~isempty(result) && any(strcmp(figureChoice.Value,figureNames([2 5])))
            showResult();
        end
    end
    function captureDraggedScale(varargin)
        % 在松开鼠标和重画/保存前核对实际色限；只处理主界面的热图。
        for ax = [map curve]
            previous = getappdata(ax,'scaleBounds');
            cb = getappdata(ax,'scaleBarHandle');
            if isempty(previous) || ~isgraphics(cb,'colorbar') || isempty(findobj(ax,'Type','image'))
                continue
            end
            bounds = visibleScale(ax);
            if isequal(bounds,previous) || any(~isfinite(bounds)) || bounds(1)>=bounds(2)
                continue
            end
            group = getappdata(ax,'scaleGroup');
            setting = struct('mode','锁定','limits',bounds);
            scaleSettings.(group) = setting;
            if ~isempty(result), result.colorScale = scaleSettings; end
            for preview = [map curve]
                im = findobj(preview,'Type','image');
                if isempty(im) || ~strcmp(getappdata(preview,'scaleGroup'),group), continue; end
                info = applyScale(preview,im,setting,strcmp(group,'wave'));
                if preview==map
                    waveInfo.Text = info; syncScale(waveScale,map,setting,'波形色阶');
                else
                    resultInfo.Text = info;
                    syncScale(resultScale,curve,setting,resultScale.label.Text);
                end
            end
        end
    end
    function syncScale(controls,ax,setting,label)
        controls.label.Text = label; controls.mode.Value = setting.mode;
        bounds = getappdata(ax,'scaleBounds');
        if strcmp(setting.mode,'锁定'), bounds = setting.limits; end
        if ~isempty(bounds)
            controls.low.Value = bounds(1); controls.high.Value = bounds(2);
        end
    end
    function handles = fields(row,label,values,callback)
        caption = uilabel(form,'Text',label); caption.Layout.Row = row; caption.Layout.Column = 1;
        handles = gobjects(1,numel(values));
        for j = 1:numel(values)
            h = uieditfield(form,'numeric','Value',values(j),'ValueChangedFcn',callback);
            h.Layout.Row = row; h.Layout.Column = j+1; handles(j) = h;
        end
    end
    function vals = numbers(handles)
        vals = arrayfun(@(h) h.Value,handles);
        assert(all(isfinite(vals)),'参数必须为有限数值。');
    end
    function invalidate(varargin)
        captureDraggedScale();
        resultScale.row.Visible = 'off'; resultInfo.Text = '';
        resultLayout.RowHeight = {40,'1x',0,0,54};
        result = []; bundle.Enable = 'off'; figureChoice.Items = figureNames(1);
        legend(curve,'off'); colorbar(curve,'off'); saveButton.Enable = 'off'; plotButton.Enable = 'off'; cla(curve);
        stats.Text = '等待按当前参数计算'; status.Text = '参数已更新。';
    end
    function modeChanged(varargin)
        ref.Enable = matlab.lang.OnOffSwitchState(strcmp(mode.Value,'固定脉冲直达波参考'));
        invalidate();
    end
    function filterChanged(src,~)
        if any(src==band)
            clean = []; cleanPulses = []; bgButton.Enable = 'off';
            if strcmp(view.Value,cleanView), view.Value = '带通波形'; end
            bp = []; invalidate(); staleView = '带通波形';
        else
            mf = []; staleView = '匹配滤波';
            if ~isempty(result)
                result.lfm_kHz = numbers(chirp); result.pulseWidth_ms = numbers(width);
            end
        end
        if strcmp(view.Value,staleView)
            view.Value = '原始波形'; resetPick(); clearMap(); showTrace();
        end
        status.Text = [staleView '参数已更新。'];
    end
    function clearMap()
        captureDraggedScale();
        cla(map); colorbar(map,'off'); setappdata(map,'scaleBounds',[]); waveInfo.Text = '';
        title(map,'点击「显示整组波形图」查看热图');
    end
    function gateChanged(varargin)
        if ~isempty(clean) && ~isequal(cleanPulses,numbers(scan)), backgroundChanged(); end
        invalidate(); drawGates(); showTrace();
    end
    function backgroundChanged(varargin)
        clean = []; cleanPulses = [];
        if strcmp(view.Value,cleanView)
            view.Value = '带通波形'; drawMap();
        else
            drawGates(); showTrace();
        end
    end
    function backgroundModeChanged(varargin)
        hp = strcmp(bgMode.Value,'脉冲维高通');
        cutoff.Enable = matlab.lang.OnOffSwitchState(hp);
        set(bgRef,'Enable',matlab.lang.OnOffSwitchState(~hp));
        backgroundChanged();
    end
    function removeBackground(varargin)
        try
            assert(~isempty(bp),'请先完成带通滤波。');
            bounds = numbers(scan);
            assert(all(bounds==fix(bounds)) && bounds(1)>=1 && bounds(2)<=size(bp,2) && ...
                bounds(2)>=bounds(1),'请选择有效的扫描脉冲范围。');
            rows = samplesIn(bgWindow); cols = bounds(1):bounds(2);
            if strcmp(bgMode.Value,'脉冲维高通')
                fc = numbers(cutoff);
                assert(fc>0 && fc<0.5,'截止频率须在 0 到 0.5 周期/脉冲之间，不含端点。');
                assert(numel(cols)>=2,'沿脉冲维高通至少需要两次脉冲。');
                filtered = pulseHighpass(bp(rows,cols),fc);
                description = sprintf('高通 %.4g 周期/脉冲',fc);
                if fc*numel(cols)<1
                    description = [description '（扫描段不足一个截止周期）'];
                end
            else
                refs = numbers(bgRef);
                assert(all(refs==fix(refs)) && refs(1)>=1 && refs(2)<=size(bp,2) && ...
                    refs(1)<=refs(2),'请选择有效的背景参考脉冲范围。');
                filtered = bp(rows,cols) - mean(bp(rows,refs(1):refs(2)),2);
                description = sprintf('已减去参考脉冲 %d–%d 的均值',refs);
            end
            clean = bp;
            clean(rows,cols) = filtered;
            cleanPulses = bounds;
            resetPick(); view.Value = cleanView; tabs.SelectedTab = waveTab; drawMap();
            status.Text = sprintf('%s · 脉冲 %d–%d · %.4g–%.4g ms', ...
                description,bounds,(rows([1 end])-1)*1000/fs);
        catch err
            uialert(fig,err.message,'固定横带背景抑制');
        end
    end
    function loadFolder(varargin)
        startDir = fullfile(project,'数据');
        if ~isfolder(startDir), startDir = pwd; end
        selected = uigetdir(startDir,'选择含 JSON 与 MAT 的采集文件夹');
        if isequal(selected,0), return; end
        try
            [~,id] = fileparts(selected);
            files = dir(fullfile(selected,[id '_*_ai*.mat']));
            pattern = ['^' regexptranslate('escape',id) '_[1-9]\d*_(ai\d+)\.mat$'];
            tokens = regexp({files.name},pattern,'tokens','once');
            tokens = tokens(~cellfun(@isempty,tokens));
            assert(~isempty(tokens),'目录中没有符合采集命名规则的通道 MAT 文件。');
            channels = unique(cellfun(@(t)t{1},tokens,'UniformOutput',false));
            [~,order] = sort(cellfun(@(c)str2double(c(3:end)),channels));
            channels = channels(order);
            index = 1;
            if numel(channels)>1
                [index,ok] = listdlg('PromptString','选择本次要读取的通道','SelectionMode','single', ...
                    'ListString',channels,'Name','处理通道');
                if ~ok, return; end
            end
            readChannel(selected,channels{index});
            channelMenu.Items = channels; channelMenu.Value = activeChannel; channelMenu.Enable = 'on';
        catch err
            uialert(fig,err.message,'读取失败');
        end
    end
    function changeChannel(src,~)
        try
            readChannel(folder,src.Value);
        catch err
            src.Value = activeChannel;
            uialert(fig,err.message,'切换通道失败');
        end
    end
    function readChannel(selected,channel)
        dlg = uiprogressdlg(fig,'Title','读取采集记录','Message','正在读取文件');
        cleanup = onCleanup(@() close(dlg));
        [~,id] = fileparts(selected);
        meta = jsondecode(fileread(fullfile(selected,[id '.json'])));
        rate = meta.SampleRate_Hz_; count = meta.CollectTimes;
        samples = round(meta.SingalTime_ms_*rate/1000);
        assert(rate>0 && samples>=2 && count>=1 && count==fix(count),'JSON 采集参数无效。');
        readTimer = tic;
        values = zeros(samples,count);
        for k = 1:count
            name = sprintf('%s_%d_%s.mat',id,k,channel);
            loaded = load(fullfile(selected,name)); names = fieldnames(loaded);
            assert(isscalar(names),'文件 %s 中的信号变量不唯一。',name);
            v = loaded.(names{1});
            assert(isnumeric(v) && isreal(v) && isvector(v) && numel(v)==samples && ...
                all(isfinite(v(:))),'文件 %s 的波形或采样点数异常。',name);
            values(:,k) = double(v(:));
            if mod(k,20)==0, dlg.Value = k/count; end
        end
        readSeconds = toc(readTimer);
        sameRecord = strcmp(folder,selected) && isequal(size(raw),size(values)) && isequal(fs,rate);
        raw = values; fs = rate; folder = selected; activeChannel = channel; bp = []; mf = [];
        clean = []; cleanPulses = []; bgButton.Enable = 'off';
        if ~sameRecord
            bgRef(1).Value = 1; bgRef(2).Value = count;
            scan(1).Value = 1; scan(2).Value = count; ref.Value = 1; pulse.Value = 1;
            for h = [direct echo bgWindow], h.Value = 0; end
            if strcmp(id,'20261031_151830') && count>=833 && samples>=4780
                scan(1).Value = 112; scan(2).Value = 833;
                gates = ([1050 2011 3362 4780]-1)*1000/fs;
                boxes = [direct echo];
                for k = 1:4, boxes(k).Value = gates(k); end
            end
        end
        resetPick(); invalidate(); view.Value = '原始波形';
        recordLabel.Text = sprintf('%s · %s · %d 脉冲 · %g kHz',id,channel,count,rate/1000);
        refreshButton.Enable = 'on';
        tabs.SelectedTab = waveTab; clearMap(); showTrace();
        status.Text = sprintf('已读取 %s 的 %d 个文件，用时 %.1f 秒。',channel,count,readSeconds);
    end
    function filterData(src,~)
        isBand = src==bpButton;
        dlg = uiprogressdlg(fig,'Title',src.Text,'Message','0%','Value',0);
        cleanup = onCleanup(@() close(dlg));
        try
            assert(~isempty(raw),'请先读取采集文件夹。');
            count = size(raw,2);
            if isBand
                b = numbers(band)*1000;
                assert(b(1)>0 && diff(b)>0 && b(2)<fs/2,'带通频带须递增且在奈奎斯特频率以内。');
            else
                f = numbers(chirp)*1000; duration = numbers(width)/1000;
                assert(f(1)>0 && diff(f)>0 && f(2)<fs/2,'LFM 频带须递增且在奈奎斯特频率以内。');
                assert(duration*fs>=1 && duration*fs<size(raw,1),'脉宽超出记录范围。');
                replica = LFM(f(1),f(2),fs,duration);
            end
            filtered = zeros(size(raw)); lastPct = -1;
            for k = 1:count
                if isBand
                    filtered(:,k) = bandpass(raw(:,k),b,fs);
                else
                    filtered(:,k) = matchedfilter(raw(:,k),replica,fs);
                end
                pct = floor(100*k/count);
                if pct~=lastPct
                    dlg.Value = k/count;
                    dlg.Message = sprintf('%s  %d%%  （%d / %d 次脉冲）',src.Text,pct,k,count);
                    drawnow limitrate nocallbacks
                    lastPct = pct;
                end
            end
            if isBand
                clean = []; cleanPulses = []; bgButton.Enable = 'on';
                bp = filtered; invalidate(); view.Value = '带通波形';
            else
                mf = filtered; view.Value = '匹配滤波';
            end
            resetPick(); tabs.SelectedTab = waveTab;
            dlg.Message = '100% · 正在显示滤波结果'; drawMap();
            status.Text = [src.Text '完成。'];
        catch err
            uialert(fig,err.message,'滤波失败');
        end
    end
    function resetPick()
        pickStart = []; pick.Value = '点击查看脉冲';
    end
    function changeView(varargin)
        resetPick();
        if strcmp(view.Value,cleanView) && isempty(clean)
            view.Value = '带通波形';
            if isempty(bp), view.Value = '原始波形'; end
            status.Text = '请先完成带通滤波，选择背景时间窗并点击「应用到扫描脉冲」。';
        elseif isempty(displayed()) && ~strcmp(view.Value,'原始波形')
            view.Value = '原始波形'; status.Text = '请先完成滤波。';
        end
        drawMap();
    end
    function armPick(varargin)
        pickStart = [];
        if strcmp(pick.Value,'点击查看脉冲'), return; end
        if isempty(bp), resetPick(); status.Text = '请先完成滤波。'; return; end
        if ~ismember(view.Value,{'带通波形',cleanView}), view.Value = '带通波形'; drawMap(); end
        status.Text = '请点两个边界。热图横轴选脉冲、纵轴选时间；单脉冲图横轴选时间。';
    end
    function values = displayed()
        switch view.Value
            case cleanView, values = clean;
            case '带通波形', values = bp;
            case '匹配滤波', values = mf;
            otherwise, values = raw;
        end
    end
    function drawMap(varargin)
        captureDraggedScale();
        values = displayed();
        if isempty(values), return; end
        last = (size(values,1)-1)*1000/fs;
        db = 20*log10(abs(values));
        im = imagesc(map,[1 size(values,2)],[0 last],db);
        title(map,''); im.ButtonDownFcn = @mapClick; map.YDir = 'normal'; colormap(map,jet(256));
        waveInfo.Text = applyScale(map,im,scaleSettings.wave,true);
        syncScale(waveScale,map,scaleSettings.wave,'波形色阶');
        xlim(map,[0.5 size(values,2)+0.5]); ylim(map,[0 last]);
        xlabel(map,'原始脉冲序号'); ylabel(map,'时间 / ms');
        configurePreview(map); disableDefaultInteractivity(map);
        drawGates(); showTrace();
    end
    function mapClick(~,event)
        point = event.IntersectionPoint;
        k = min(size(raw,2),max(1,round(point(1))));
        if strcmp(pick.Value,'点击查看脉冲')
            pulse.Value = k; showTrace(); return;
        end
        switch pick.Value
            case '点两次选扫描范围', target = scan; value = k;
            case '点两次选直达波窗', target = direct; value = point(2);
            case '点两次选背景窗', target = bgWindow; value = point(2);
            otherwise, target = echo; value = point(2);
        end
        setBoundary(target,value);
    end
    function traceClick(~,event)
        if isempty(bp) || ~ismember(view.Value,{'带通波形',cleanView}), return; end
        switch pick.Value
            case '点两次选直达波窗', target = direct;
            case '点两次选回波窗', target = echo;
            case '点两次选背景窗', target = bgWindow;
            otherwise, return
        end
        value = max(0,min(event.IntersectionPoint(1),(size(bp,1)-1)*1000/fs));
        setBoundary(target,value);
    end
    function setBoundary(target,value)
        if isempty(pickStart)
            pickStart = value; status.Text = sprintf('首个边界 %.5g 已选，请点击另一端。',value);
        else
            bounds = sort([pickStart value]);
            target(1).Value = bounds(1); target(2).Value = bounds(2);
            resetPick();
            if isequal(target,bgWindow), backgroundChanged(); else, gateChanged(); end
            status.Text = '窗口已更新。';
        end
    end
    function drawGates()
        delete(gateLines(isgraphics(gateLines))); gateLines = gobjects(0);
        if isempty(raw) || ~ismember(view.Value,{'带通波形',cleanView}), return; end
        gateLines = gobjects(4,2);
        for k = 1:2
            gateLines(1,k) = xline(map,scan(k).Value,'w--','HitTest','off');
            if bgWindow(2).Value>bgWindow(1).Value
                gateLines(4,k) = yline(map,bgWindow(k).Value,'y:','HitTest','off');
            end
            if direct(2).Value>direct(1).Value
                gateLines(2,k) = yline(map,direct(k).Value,'c-','HitTest','off');
            end
            if echo(2).Value>echo(1).Value
                gateLines(3,k) = yline(map,echo(k).Value,'m-','HitTest','off');
            end
        end
    end
    function showTrace(varargin)
        values = displayed(); if isempty(values), return; end
        k = min(size(values,2),max(1,round(pulse.Value))); pulse.Value = k;
        line = plot(trace,(0:size(values,1)-1)*1000/fs,values(:,k),'Color',[0.12 0.28 0.48]);
        trace.ButtonDownFcn = @traceClick; line.ButtonDownFcn = @traceClick;
        xlabel(trace,'时间 / ms'); ylabel(trace,'幅值');
        title(trace,sprintf('脉冲 %d · %s',k,view.Value)); grid(trace,'on');
        pbaspect(trace,[2 1 1]);
        configurePreview(trace); disableDefaultInteractivity(trace);
        if ismember(view.Value,{'带通波形',cleanView})
            if bgWindow(2).Value>bgWindow(1).Value
                for h = bgWindow, xline(trace,h.Value,':','Color',[.60 .40 0],'HitTest','off'); end
            end
            if direct(2).Value>direct(1).Value
                for h = direct, xline(trace,h.Value,'--','Color',[0 .52 .55],'HitTest','off'); end
            end
            if echo(2).Value>echo(1).Value
                for h = echo, xline(trace,h.Value,'-','Color',[.70 .12 .52],'HitTest','off'); end
            end
        end
    end
    function idx = samplesIn(handles)
        bounds = numbers(handles); last = (size(bp,1)-1)*1000/fs;
        assert(bounds(1)>=0 && bounds(2)<=last && diff(bounds)>0,'请设置记录范围内的起止时间窗。');
        limits = round(bounds*fs/1000)+1;
        assert(diff(limits)>=1,'窗口至少需要两个采样点。');
        idx = limits(1):limits(2);
    end
    function calculate(varargin)
        compute(false);
    end
    function calculateSweep(varargin)
        compute(true);
    end
    function frequencyChanged(varargin)
        if ~isempty(result), compute(false); end
    end
    function sweepChanged(varargin)
        if ~isempty(result) && isfield(result,'spectrum')
            result = rmfield(result,'spectrum');
            figureChoice.Items = figureNames(1:2); figureChoice.Value = figureNames{1};
            bundle.Enable = 'off'; showResult();
        end
        status.Text = '扫频参数已更新。点击“计算全频段 TS”生成新频谱。';
    end
    function compute(fullBand)
        dlg = uiprogressdlg(fig,'Title','计算 TS','Message','提取窗内幅值');
        cleanup = onCleanup(@() close(dlg));
        try
            assert(~isempty(bp),'请先完成滤波。');
            bounds = numbers(scan); angles = numbers(angle); geometry = numbers(dist);
            assert(all(bounds==fix(bounds)) && bounds(1)>=1 && diff(bounds)>=0 && ...
                bounds(2)<=size(bp,2),'扫描范围须为有效的原始脉冲序号。');
            pulses = bounds(1):bounds(2);
            assert(isscalar(pulses) || diff(angles)~=0,'多个脉冲的扫描起止角度不能相同。');
            theta = linspace(angles(1),angles(2),numel(pulses));
            if isscalar(pulses), theta = angles(1); end
            L = geometry(1); r = geometry(2);
            assert(L>r && r>0,'当前传播修正要求 L > r > 0。');
            d = samplesIn(direct); e = samplesIn(echo); ff = numbers(freq)*1000;
            b = numbers(band)*1000;
            assert(ff>=b(1) && ff<=b(2),'TS 频点应在带通频带内。');

            refs = pulses;
            if strcmp(mode.Value,'固定脉冲直达波参考')
                refs = numbers(ref);
                assert(refs==fix(refs) && refs>=1 && refs<=size(bp,2),'固定参考脉冲超出范围。');
            end
            frequencies = ff;
            if fullBand
                rangeHz = numbers(sweepBand)*1000; delta = numbers(step)*1000;
                assert(diff(rangeHz)>0 && rangeHz(1)>=b(1) && rangeHz(2)<=b(2), ...
                    '扫频范围应为带通频带内的递增区间。');
                intervals = diff(rangeHz)/delta;
                assert(delta>0 && isfinite(intervals) && intervals>=1 && ...
                    abs(intervals-round(intervals))<1e-8,'扫频间隔应能整分起止频率。');
                gridHz = linspace(rangeHz(1),rangeHz(2),round(intervals)+1).';
                frequencies = unique([gridHz; ff]);
            end
            % 改窗、角度、距离、带通或通道时，已有 result 会先失效。
            % 此处只复用参数仍相同的结果；网格外的频点独立计算。
            cachedRow = [];
            if ~fullBand && isfield(result,'spectrum')
                cachedRow = find(abs(result.spectrum.frequency_Hz-ff)<=8*eps(ff),1);
            end
            if ~isempty(cachedRow)
                pdAll = result.spectrum.directAmplitude(cachedRow,:);
                peAll = result.spectrum.echoAmplitude(cachedRow,:);
            elseif ~fullBand && ~isempty(result) && result.frequency_Hz==ff
                pdAll = result.directAmplitude; peAll = result.echoAmplitude;
            else
                [pdAll,peAll] = windowAmplitudes(bp(d,refs),bp(e,pulses),fs,frequencies,dlg);
            end
            assert(all(pdAll(:)>0 & isfinite(pdAll(:))),'直达波幅值无效，请检查参考脉冲和直达波窗。');
            ratios = peAll*r./(pdAll*((L-r)/L));
            assert(all(isfinite(ratios(:)) & ratios(:)>0),'TS 幅值无效，请检查脉冲与时间窗。');
            selected = find(frequencies==ff,1);
            pd = pdAll(selected,:); pe = peAll(selected,:);
            ratio = ratios(selected,:); ts = 20*log10(ratio);
            next = struct('folder',folder,'channel',activeChannel,'fs_Hz',fs,'band_kHz',numbers(band), ...
                'lfm_kHz',numbers(chirp),'pulseWidth_ms',numbers(width),'frequency_Hz',ff, ...
                'pulse',pulses,'referenceMode',mode.Value,'referencePulse',refs, ...
                'angle_deg',theta,'angleLimits_deg',angles,'directSamples',d([1 end]),'echoSamples',e([1 end]), ...
                'direct_ms',numbers(direct),'echo_ms',numbers(echo),'L_m',L,'r_m',r, ...
                'directAmplitude',pd,'echoAmplitude',pe,'TS_dB',ts, ...
                'energyMean_dB',10*log10(angleMeanPower(theta,ratio.^2)),'peakToPeak_dB',max(ts)-min(ts));
            if fullBand
                [~,rows] = ismember(gridHz,frequencies);
                next.spectrum = summarizeSpectrum(theta,gridHz,ratios(rows,:));
                next.spectrum.directAmplitude = pdAll(rows,:);
                next.spectrum.echoAmplitude = peAll(rows,:);
                if numel(theta)>1 && abs(abs(theta(end)-theta(1))-360)<1e-8 && strcmp(mode.Value,'逐脉冲直达波参考')
                    diameter = 4*10^(next.spectrum.mean_dB/20);
                    next.spectrum.equivalentDiameter_m = diameter;
                    next.spectrum.kaRange = pi*gridHz([1 end])'*diameter/1500;
                end
            elseif isfield(result,'spectrum')
                next.spectrum = result.spectrum;
            end
            next.colorScale = scaleSettings;
            result = next;
            if isfield(result,'spectrum')
                figureChoice.Items = figureNames;
                bundle.Enable = 'on';
            else
                figureChoice.Items = figureNames(1:2);
                bundle.Enable = 'off';
            end
            if fullBand, figureChoice.Value = figureNames{5}; else, figureChoice.Value = figureNames{1}; end
            showResult(); saveButton.Enable = 'on'; plotButton.Enable = 'on';
            tabs.SelectedTab = resultTab; status.Text = '计算完成，可切换结果图或导出。';
        catch err
            if ~fullBand && ~isempty(result), freq.Value = result.frequency_Hz/1000; end
            uialert(fig,err.message,'无法计算 TS');
        end
    end
    function showResult(varargin)
        if isempty(result), return; end
        captureDraggedScale();
        resultInfo.Text = renderResult(curve,figureChoice.Value);
        configurePreview(curve);
        resultScale.row.Visible = 'off';
        resultLayout.RowHeight = {40,'1x',0,0,54};
        if any(strcmp(figureChoice.Value,figureNames([2 5])))
            resultLayout.RowHeight = {40,'1x',36,20,54};
            resultScale.row.Visible = 'on';
            if strcmp(figureChoice.Value,figureNames{5})
                syncScale(resultScale,curve,scaleSettings.ts,'TS 色阶');
            else
                syncScale(resultScale,curve,scaleSettings.wave,'波形色阶');
            end
        end
        stats.Text = sprintf('%g kHz · %d 次脉冲 · 单频能量平均 %.2f dB · 峰谷差 %.2f dB', ...
            result.frequency_Hz/1000,numel(result.pulse),result.energyMean_dB,result.peakToPeak_dB);
        if isfield(result,'spectrum') && ~strcmp(figureChoice.Value,figureNames{1})
            sp = result.spectrum;
            stats.Text = sprintf(['%g–%g kHz · 所选范围能量平均 %.2f dB · 峰值 %.2f dB（%.2f°）' ...
                ' · 谷值 %.2f dB（%.2f°） · 峰谷差 %.2f dB'],sp.frequency_Hz([1 end])/1000, ...
                sp.mean_dB,sp.max_dB,sp.maxAngle_deg,sp.min_dB,sp.minAngle_deg,sp.peakToPeak_dB);
            if isfield(sp,'equivalentDiameter_m')
                stats.Text = sprintf('%s · 等效刚性球直径粗估 %.2f cm（背向远场、ka ≫ 1；ka %.1f–%.1f）', ...
                    stats.Text,sp.equivalentDiameter_m*100,sp.kaRange);
            end
        end
    end
    function info = renderResult(ax,kind)
        info = '';
        cla(ax,'reset'); legend(ax,'off'); colorbar(ax,'off');
        theta = result.angle_deg; xtext = '角度 / °'; ytext = 'TS / dB';
        if isfield(result,'spectrum'), sp = result.spectrum; f = sp.frequency_Hz/1000; end
        switch kind
            case figureNames{1}
                plot(ax,theta,result.TS_dB,'-','LineWidth',1.2);
            case figureNames{2}
                idx = result.echoSamples(1):result.echoSamples(2);
                info = heat(ax,theta,(idx-1)*1000/fs,20*log10(abs(bp(idx,result.pulse))),scaleSettings.wave,true);
                ytext = '时间 / ms';
            case figureNames{3}
                targets = ceil(f(1)/5)*5:5:floor(f(end)/5)*5;
                idx = nearest(f,[f(1) targets f(end)]);
                curves(ax,theta,sp.TS_dB(idx,:).',compose('%g kHz',f(idx)));
            case figureNames{4}
                targets = ceil(min(theta)/30)*30:30:floor(max(theta)/30)*30;
                idx = nearest(theta,[min(theta) targets max(theta)]);
                curves(ax,f,sp.TS_dB(:,idx),compose('%g°',theta(idx)));
                xtext = '频率 / kHz';
            case figureNames{5}
                info = heat(ax,theta,f,sp.TS_dB,scaleSettings.ts,false); ytext = '频率 / kHz';
            case figureNames{6}
                plot(ax,theta,sp.bandMean_dB,'-','LineWidth',1.2);
            case figureNames{7}
                plot(ax,f,sp.angleMean_dB,'-','LineWidth',1.2); xtext = '频率 / kHz';
        end
        xlabel(ax,xtext); ylabel(ax,ytext);
        if any(strcmp(kind,figureNames([1 2 3 5 6])))
            bounds = result.angleLimits_deg;
            if bounds(1)==bounds(2)
                % 单一角度需要非零显示跨度，只标出实际角度。
                xlim(ax,bounds(1)+[-0.5 0.5]); xticks(ax,bounds(1));
            else
                limits = sort(bounds);
                xlim(ax,limits); xticks(ax,linspace(limits(1),limits(2),5));
                if bounds(1)>bounds(2), ax.XDir = 'reverse'; end
            end
        end
        if ~any(strcmp(kind,figureNames([2 5]))), grid(ax,'on'); end
    end
    function configurePreview(source)
        stylePreviewAxes(source);
        if isempty(source.Toolbar) || ~strcmp(source.Toolbar.Tag,'cornerPreviewTools')
            tb = axtoolbar(source,'default');
            saveAction = findall(tb,'Tag','saveas');
            if isempty(saveAction)
                % 其他版本若没有同名菜单项，则显式提供保存按钮。
                tb = axtoolbar(source,{'restoreview','zoomout','zoomin','pan','datacursor'});
                saveAction = axtoolbarbtn(tb,'push','Icon','export','Tooltip','保存完整图片');
            end
            saveAction.ButtonPushedFcn = @(~,~) savePlot(source);
            tb.Tag = 'cornerPreviewTools';
        end
    end
    function exportFigurePair(kind,base,source)
        widthCM = 8; heightCM = 6;
        paper = figure('Visible','off','WindowStyle','normal','Color','w', ...
            'Units','centimeters','Position',[2 2 widthCM heightCM], ...
            'PaperUnits','centimeters','PaperSize',[widthCM heightCM], ...
            'PaperPosition',[0 0 widthCM heightCM],'NumberTitle','off','Name',kind);
        closePaper = onCleanup(@() close(paper));
        tiles = tiledlayout(paper,1,1,'Padding','compact','TileSpacing','compact');
        ax = nexttile(tiles);
        if nargin<3 || source==curve
            renderResult(ax,kind);
        else
            % 仅复制绘图对象，独立图窗不继承滚动面板的位置或裁剪区域。
            copyobj(flipud(source.Children),ax);
            xlabel(ax,source.XLabel.String); ylabel(ax,source.YLabel.String);
            title(ax,source.Title.String);
            ax.XGrid = source.XGrid; ax.YGrid = source.YGrid;
            if source==trace, pbaspect(ax,[2 1 1]); end
        end
        if nargin>=3
            ax.XDir = source.XDir; ax.YDir = source.YDir;
            xlim(ax,source.XLim); ylim(ax,source.YLim);
            cb = getappdata(source,'scaleBarHandle');
            if ~isempty(findobj(source,'Type','image')) && isscalar(cb) && isgraphics(cb,'colorbar')
                colormap(ax,colormap(source)); clim(ax,visibleScale(source));
                savedBar = colorbar(ax); savedBar.Ticks = cb.Ticks;
            end
        end
        ax.FontUnits = 'points'; ax.FontSize = 8;
        if ~isempty(ax.Legend)
            ax.Legend.FontSize = 7;
            ax.Legend.NumColumns = min(3,numel(ax.Legend.String));
            ax.Legend.Layout.Tile = 'south';
        end
        drawnow;
        exportgraphics(paper,[base '.png'],'Resolution',300,'Units','centimeters', ...
            'Width',widthCM,'Height',heightCM,'Padding','figure', ...
            'PreserveAspectRatio','on','BackgroundColor','white');
        % 使保存的普通 MATLAB 图窗重新打开时可见、可编辑。
        paper.Visible = 'on';
        savefig(paper,[base '.fig']);
    end
    function exportBundle(varargin)
        if isempty(result) || ~isfield(result,'spectrum'), return; end
        captureDraggedScale();
        parent = uigetdir(project,'选择导出位置（将在其下新建结果文件夹）');
        if isequal(parent,0), return; end
        [~,id] = fileparts(folder);
        dest = fullfile(parent,[id '_' result.channel '_TS_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
        dlg = uiprogressdlg(fig,'Title','导出图表与数据','Message','准备导出');
        cleanup = onCleanup(@() close(dlg));
        try
            assert(~isfolder(dest),'结果目录已存在，请再次导出。');
            [ok,msg] = mkdir(dest); assert(ok,'%s',msg);
            save(fullfile(dest,'TS_results.mat'),'result');
            writeTables(dest,result);
            for j = 1:numel(figureNames)
                base = fullfile(dest,sprintf('%02d_%s',j-1,figureNames{j}));
                exportFigurePair(figureNames{j},base);
                dlg.Value = j/numel(figureNames);
            end
            status.Text = ['已导出至 ' dest];
        catch err
            uialert(fig,sprintf('导出未完成。目录：%s\n%s',dest,err.message),'导出失败');
        end
    end
    function saveResult(varargin)
        if isempty(result), return; end
        captureDraggedScale();
        [~,id] = fileparts(folder);
        [name,path] = uiputfile('*.mat','保存当前参数与 TS 结果',[id '_' result.channel '_TS.mat']);
        if isequal(name,0), return; end
        try
            save(fullfile(path,name),'result'); status.Text = ['已保存 ' name];
        catch err
            uialert(fig,err.message,'保存失败');
        end
    end
    function savePlot(varargin)
        source = curve;
        if nargin==1, source = varargin{1}; end
        if isempty(source.Children) || (source==curve && isempty(result))
            uialert(fig,'请先显示要保存的图。','当前图为空'); return
        end
        if source==map
            kind = view.Value;
        elseif source==trace
            kind = sprintf('%s_脉冲%d',view.Value,pulse.Value);
        else
            kind = figureChoice.Value;
        end
        captureDraggedScale();
        [~,id] = fileparts(folder);
        [name,path] = uiputfile('*.png','保存同名 PNG 和 FIG',[id '_' activeChannel '_' kind '.png']);
        if isequal(name,0), return; end
        try
            [~,stem] = fileparts(name);
            if isfile(fullfile(path,[stem '.fig']))
                choice = uiconfirm(fig,['替换已有的可编辑图 ' stem '.fig？'], ...
                    '导出结果图','Options',{'替换','取消'},'DefaultOption',2,'CancelOption',2);
                if ~strcmp(choice,'替换'), return; end
            end
            exportFigurePair(kind,fullfile(path,stem),source);
            status.Text = ['已保存 ' stem '.png 和同名 FIG'];
        catch err
            uialert(fig,err.message,'导出失败');
        end
    end
end

function filtered = pulseHighpass(block,fc)
% 沿每行的脉冲序列作偶对称延拓，再施加二阶巴特沃斯形状的零相位幅频响应。
n = size(block,2);
bins = 0:2*n-1;
f = min(bins,2*n-bins)/(2*n); % 周期/脉冲，正负频率取相同增益
gain = zeros(size(f));
gain(2:end) = 1./sqrt(1+(fc./f(2:end)).^4);
filtered = zeros(size(block),'like',block);
for startRow = 1:64:size(block,1)
    rows = startRow:min(startRow+63,size(block,1));
    data = block(rows,:);
    extended = [data fliplr(data)];
    y = ifft(fft(extended,[],2).*gain,[],2,'symmetric');
    filtered(rows,:) = y(:,1:n);
end
end

function [direct,echo] = windowAmplitudes(d,e,fs,frequencies,dlg)
count = numel(frequencies);
direct = zeros(count,size(d,2)); echo = zeros(count,size(e,2));
% 块内用 FFT 求线性卷积，再取与原脚本 hilbert(conv(...)) 相同的中央 201 点。
for k = 1:count
    kernel = sin(2*pi*frequencies(k)*(1:10000)'/fs);
    direct(k,:) = amplitudes(d,kernel);
    echo(k,:) = amplitudes(e,kernel);
    dlg.Value = k/count;
    dlg.Message = sprintf('%.2f kHz · %d / %d · %.0f%%',frequencies(k)/1000,k,count,100*k/count);
    drawnow limitrate nocallbacks
end
end

function p = amplitudes(signals,kernel)
n = size(signals,1)+numel(kernel)-1;
weight = zeros(n,1); weight(1) = 1;
weight(2:floor((n+1)/2)) = 2;
if mod(n,2)==0, weight(n/2+1) = 1; end
filterFFT = fft(kernel,n).*weight;
center = round(n/2)+(-100:100);
p = zeros(1,size(signals,2));
for first = 1:32:size(signals,2)
    cols = first:min(first+31,size(signals,2));
    z = ifft(fft(signals(:,cols),n,1).*filterFFT,[],1);
    p(cols) = mean(abs(z(center,:)),1);
end
end

function average = angleMeanPower(theta,power)
if isscalar(theta)
    average = power;
else
    average = trapz(theta,power,2)/(theta(end)-theta(1));
end
end

function sp = summarizeSpectrum(theta,f,ratio)
power = ratio.^2;
acrossFrequency = mean(power,1);
acrossAngle = angleMeanPower(theta,power);
sp = struct('frequency_Hz',f,'TS_dB',20*log10(ratio), ...
    'bandMean_dB',10*log10(acrossFrequency),'angleMean_dB',10*log10(acrossAngle), ...
    'mean_dB',10*log10(mean(acrossAngle)));
[sp.max_dB,imax] = max(sp.bandMean_dB);
[sp.min_dB,imin] = min(sp.bandMean_dB);
sp.maxAngle_deg = theta(imax); sp.minAngle_deg = theta(imin);
sp.peakToPeak_dB = sp.max_dB-sp.min_dB;
end

function idx = nearest(grid,targets)
[~,idx] = min(abs(grid(:)-targets(:).'),[],1);
idx = unique(idx,'stable');
end

function curves(ax,x,y,labels)
hold(ax,'on');
styles = {'-','--',':','-.'};
for j = 1:size(y,2)
    plot(ax,x,y(:,j),'LineStyle',styles{1+mod(floor((j-1)/7),4)},'LineWidth',1.15);
end
hold(ax,'off'); legend(ax,labels,'Location','southoutside','NumColumns',min(5,numel(labels)));
end

function stylePreviewAxes(ax)
ax.Box = 'on'; ax.TickDir = 'out'; ax.LineWidth = 0.8;
ax.XColor = [0.22 0.30 0.34]; ax.YColor = ax.XColor;
ax.GridAlpha = 0.12; ax.FontUnits = 'points'; ax.FontSize = 10;
end

function info = heat(ax,x,y,data,setting,isWave)
if numel(x)>1 && x(end)<x(1), x = fliplr(x); data = fliplr(data); end
im = imagesc(ax,x,y,data); ax.YDir = 'normal'; colormap(ax,jet(256));
info = applyScale(ax,im,setting,isWave);
end

function info = applyScale(ax,im,setting,isWave)
data = im.CData;
finite = isfinite(data);
finiteCount = nnz(finite);
% -Inf in a waveform dB image represents a measured zero amplitude.
zeroCount = 0;
if isWave, zeroCount = nnz(data==-Inf); end
delete(findobj(ax,'Tag','emptyScaleMessage'));
if finiteCount==0
    colorbar(ax,'off'); setappdata(ax,'scaleBounds',[]);
    im.AlphaData = 0;
    if isWave && zeroCount==numel(data)
        info = '当前波形全为零';
    elseif zeroCount>0
        info = '有效波形全为零，其余像素无有效数据';
    else
        info = '无有效数据';
    end
    text(ax,0.5,0.5,info,'Units','normalized','HorizontalAlignment','center', ...
        'Tag','emptyScaleMessage','HitTest','off');
    return
end
if finiteCount+zeroCount==numel(data)
    im.AlphaData = 1;
else
    im.AlphaData = finite | (isWave & data==-Inf);
end
switch setting.mode
    case '锁定'
        bounds = setting.limits;
        ticks = linspace(bounds(1),bounds(2),6);
    otherwise
        [lo,hi,ticks] = calc_caxis_v1(data,strcmp(setting.mode,'完整范围'));
        bounds = [lo hi];
end
clim(ax,bounds); cb = colorbar(ax); cb.LimitsMode = 'auto'; cb.Ticks = ticks;
setappdata(ax,'scaleBarHandle',cb);
if isWave, group = 'wave'; else, group = 'ts'; end
setappdata(ax,'scaleGroup',group);
setappdata(ax,'scaleBounds',bounds);
count = finiteCount+zeroCount;
below = nnz(finite & data<bounds(1))+zeroCount;
above = nnz(finite & data>bounds(2));
info = sprintf('%s · 色阶 [%g, %g] dB · 低于下限 %.2f%% · 高于上限 %.2f%%', ...
    setting.mode,bounds,100*below/count,100*above/count);
end

function bounds = visibleScale(ax)
% 交互工具可能调整轴的 CLim，也可能单独设置颜色条的 Limits。
bounds = ax.CLim;
cb = getappdata(ax,'scaleBarHandle');
if isequal(bounds,getappdata(ax,'scaleBounds')) && isgraphics(cb,'colorbar') && strcmp(cb.LimitsMode,'manual')
    bounds = cb.Limits;
end
end

function writeTables(dest,res)
sp = res.spectrum;
writetable(table(res.pulse(:),res.angle_deg(:),res.TS_dB(:),sp.bandMean_dB(:), ...
    'VariableNames',{'Pulse','Angle_deg','SingleFrequencyTS_dB','BandEnergyMeanTS_dB'}), ...
    fullfile(dest,'TS_by_angle.csv'));
writetable(table(sp.frequency_Hz(:),sp.angleMean_dB(:), ...
    'VariableNames',{'Frequency_Hz','AngleEnergyMeanTS_dB'}),fullfile(dest,'TS_by_frequency.csv'));
[f,k] = ndgrid(sp.frequency_Hz,1:numel(res.pulse));
pulses = res.pulse(k(:)); angles = res.angle_deg(k(:));
writetable(table(f(:),pulses(:),angles(:),sp.TS_dB(:), ...
    'VariableNames',{'Frequency_Hz','Pulse','Angle_deg','TS_dB'}),fullfile(dest,'TS_spectrum.csv'));
summary = table(sp.frequency_Hz(1),sp.frequency_Hz(end),res.angle_deg(1),res.angle_deg(end), ...
    sp.mean_dB,sp.max_dB,sp.maxAngle_deg,sp.min_dB,sp.minAngle_deg,sp.peakToPeak_dB, ...
    'VariableNames',{'BandStart_Hz','BandEnd_Hz','AngleStart_deg','AngleEnd_deg', ...
    'Mean_dB','Max_dB','MaxAngle_deg','Min_dB','MinAngle_deg','PeakToPeak_dB'});
if isfield(sp,'equivalentDiameter_m')
    summary.EquivalentSphereDiameter_m = sp.equivalentDiameter_m;
    summary.kaMin = sp.kaRange(1); summary.kaMax = sp.kaRange(2);
end
writetable(summary,fullfile(dest,'TS_statistics.csv'));
end

function y = LFM(fmin,fmax,fs,T1)
    det = 1/fs;
    t1 = 0:det:T1;
    W = fmax - fmin;
    y = sin(2*pi*fmin*t1 + pi*W/T1*t1.^2);
end

function [smf, smff] = matchedfilter(s,r,fs)
% s is the signal; r is the reference waveform.
% MATCHEDFILTER calculates the matched filter output
%                 of signal s with replica r.
%
%                 smf = matchedfilter(s,r,fs)
%
%                 input:
%                        s    : the signal
%                        r    : the replica
%                        fs   : the sample frequency
%                 output:
%                        smf  : the matchedfilter output
 
%                 Developed at TNO-FEL
%                 Author: Ren\'e Laterveer,      30/09/1992
%                 some minor changes, RL  7/10/1992
%                 added normalization, RL  26/11/1992


ls = size(s);
if ls(1) ~= 1
  s = s';
end
ls = max(ls);

r(r==0) = [];
lr = size(r);
if lr(1) ~= 1
  r = r';
end
lr = max(lr);
T = lr/fs;

if ls < lr
    error('Replica must have smaller length than signal');
end

%  Normalize replica on energy 1
%r = r/sqrt(r*r');

% Normalize replica on maximum amplitude 1
r = r/abs(max(r));

% determine number of points in fft
p = 2^ceil(log(ls)/log(2));
if p==ls      %  remove wrap around effects when
  p=2*p;      %  signal is already 2^n in length
end

% correlation by multiplication in frequency domain
y = conj(fft(r,p)).*fft(s,p);

% perform Hilbert transform (stolen from hilbert.m)
% throw away negative frequencies and double positive frequencies
if p ~= 1
%                  freq>0                Nyquest            freq<0
	h = [1; 2*ones(fix((p-1)/2),1); ones(1-rem(p,2),1); zeros(fix((p-1)/2),1)];
	y(:) = y(:).*h;
end

% matched filtered output
smf = abs(ifft(y))';   
smff = (ifft(y))'; % envelope
%smf = real(ifft(y)');      % real part 
%smf2 = imag(ifft(y)');      % imaginery part 

smf(ls+1:p) = [];           % adjust the output to same length as input signal
smf = smf*2/T/fs;           % normalization according to amplitude signal


smff(ls+1:p) = [];           % adjust the output to same length as input signal
smff = smff*2/T/fs;  
%figure;
%plot(smf);

end

function [cmin, cmax, cbtk] = calc_caxis_v1(data,fullRange)
% calc_caxis_v1 自动计算 colorbar 范围与刻度
% fullRange 为 true 时，完整覆盖所有有限值，不做两端修剪。
    %   输入: data - 任意数值矩阵/向量
    %   输出: cmin, cmax - colorbar上下界
    %         cbtk       - 刻度位置向量（包含端点）
    %
    %   行为说明：
    %       - 自动去除 NaN/Inf
    %       - 去除首尾约各3%的极端值（数据充足时）
    %       - 若数据同时包含正负数，则范围以数据中心对称扩展（因子1.2）
    %       - 若数据全为非负或全为非正，则范围在数据区间两端向外扩展5%
    %         （并强制下界≥0或上界≤0，避免无意义颜色）
    %       - 自动选择美观的刻度步长

    % 1. 预处理：去除NaN/Inf
    if nargin<2, fullRange = false; end
    data_vec = data(:);
    data_vec = data_vec(isfinite(data_vec));
    if isempty(data_vec)
        cmin = 0; cmax = 1; cbtk = [0 0.5 1];
        return;
    end

    % 对有效样本取实际的次序统计量；每端恰好丢弃 floor(3% * n) 个。
    n = numel(data_vec);
    trim_n = floor(0.03*n);
    full_min = min(data_vec);
    full_max = max(data_vec);
    data_min = full_min;
    data_max = full_max;
    if ~fullRange && trim_n>0 && full_min<full_max
        lower = mink(data_vec,trim_n+1);
        upper = maxk(data_vec,trim_n+1);
        if lower(end)<upper(end)
            data_min = lower(end);
            data_max = upper(end);
        end
        % 若修剪后上下界重合，保留原始范围，避免稀疏强回波全部饱和。
    end

    span = data_max-data_min;
    if span==0
        pad = max(0.5,eps(data_min));
    elseif data_min<0 && data_max>0
        pad = 0.10*span;
    else
        pad = 0.05*span;
    end
    cmin_raw = data_min-pad;
    cmax_raw = data_max+pad;
    if full_max<=0 && full_min<0
        cmax_raw = min(0,cmax_raw);
    elseif full_min>=0 && full_max>0
        cmin_raw = max(0,cmin_raw);
    end
    range_val = cmax_raw-cmin_raw;

    % 5. 计算美观刻度步长（原算法不变）
    rough_step = range_val / 6;
    if rough_step <= 0 || ~isfinite(rough_step)
        rough_step = 1;
    end
    magnitude = 10 ^ floor(log10(rough_step));
    if ~isfinite(magnitude) || magnitude == 0
        magnitude = 1;
    end
    nice_steps = [0.1 0.2 0.3 0.5 1 2 3 4 5 10 15 25]; % 可改
    [~, idx] = min(abs(nice_steps - rough_step / magnitude));
    step = magnitude * nice_steps(idx);
    if step <= 0 || ~isfinite(step)
        step = 1;
    end

    % 6. 对齐到整步长并生成刻度
    cmin = step * floor(cmin_raw / step);
    cmax = step * ceil(cmax_raw / step);
    if cmin >= cmax
        cmax = cmin + step;
    end

    if cmax - cmin >= step
        inner_ticks = cmin : step : cmax;
    else
        inner_ticks = [];
    end
    cbtk = unique([cmin inner_ticks cmax]);
    if length(cbtk) < 2
        cbtk = [cmin cmax];
    end
end


