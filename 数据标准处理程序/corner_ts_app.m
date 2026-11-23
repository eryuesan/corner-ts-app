function corner_ts_app
home = uifigure('Name','角反射体试验 · TS 处理','WindowState','maximized');
shell = uigridlayout(home,[5 3],'RowHeight',{'1x',48,65,65,'1x'}, ...
    'ColumnWidth',{'1x',300,'1x'},'BackgroundColor',[.95 .97 .97]);
h = uilabel(shell,'Text','选择数据处理类型','FontSize',22,'HorizontalAlignment','center');
h.Layout.Row = 2; h.Layout.Column = 2;
names = {'合置处理','分置处理'}; sessions = gobjects(1,2);
opening = false;
for k=1:2
    b = uibutton(shell,'Text',names{k},'FontSize',18,'ButtonPushedFcn',@(~,~) enter(k));
    b.Layout.Row = k+2; b.Layout.Column = 2;
end
home.CloseRequestFcn = @finish;
    function enter(index)
        if opening, return; end
        opening = true;
        dlg = [];
        try
            dlg = uiprogressdlg(home,'Title',['正在打开' names{index}], ...
                'Message','正在加载界面，请稍候…','Indeterminate','on');
            cleanup = onCleanup(@() finishOpening(dlg));
            drawnow; % 先显示提示，再创建控件较多的处理界面。
            if ~isgraphics(home), return; end
            if ~isgraphics(sessions(index))
                sessions(index) = processingSession(index==2,@back);
                sessions(index).CloseRequestFcn = @(src,~) back(src);
            end
            sessions(index).Visible = 'on';
            drawnow;
            if isgraphics(home), home.Visible = 'off'; end
        catch err
            finishOpening(dlg);
            if isgraphics(home)
                home.Visible = 'on';
                uialert(home,err.message,'界面加载失败');
            end
        end
    end
    function finishOpening(dlg)
        if ~isempty(dlg) && isvalid(dlg), close(dlg); end
        opening = false;
    end
    function back(page)
        home.Visible = 'on'; page.Visible = 'off';
    end
    function finish(varargin)
        delete(sessions(isgraphics(sessions))); delete(home);
    end
end

function fig = processingSession(bistatic,goHome)
% 角反射体 TS 处理界面。支持单频与频率扫描，每列对应一个原始脉冲。
project = fileparts(fileparts(mfilename('fullpath')));
raw = []; bp = []; mf = []; fs = []; folder = ''; result = [];
activeChannel = '';
dataOrigin = ''; timeSeconds = []; recordNumbers = []; recordFiles = {};
clean = []; cleanPulses = []; cleanView = '脉冲维去背景';
backgroundPending = false;
scaleSettings = struct('wave',struct('mode','自动','limits',[]), ...
                       'ts',struct('mode','自动','limits',[]));
pickStart = []; gateLines = gobjects(0);

pageName = '合置处理'; if bistatic, pageName = '分置处理'; end
fig = uifigure('Name',['角反射体试验 · ' pageName],'WindowState','maximized','Visible','off');
echoResults = {}; editor = []; echoSelect = [];
combined = [];
combinedNames = {'多窗频带能量平均 TS 对比','多窗相干频带能量平均 TS','多窗非相干频带能量平均 TS', ...
    '多窗相干角度能量平均 TS–频率曲线','多窗非相干角度能量平均 TS–频率曲线', ...
    '多窗相干 TS 频率–角度谱','多窗非相干 TS 频率–角度谱'};
layout = uigridlayout(fig,[1 2],'ColumnWidth',{355,'1x'},'Padding',[12 12 12 12]);
% 左栏的设置可以滚动，状态栏始终可见。
sidebar = uigridlayout(layout,[2 1],'RowHeight',{'1x',54},'Padding',[0 0 0 0],'RowSpacing',5);
rowHeights = repmat({27},1,32);
rowHeights([1 4 9 16 20 24 29]) = {24};
form = uigridlayout(sidebar,[32 3],'ColumnWidth',{132,'1x','1x'}, ...
    'RowHeight',rowHeights,'RowSpacing',4,'ColumnSpacing',6,'Padding',[6 4 8 4], ...
    'BackgroundColor',[0.98 0.985 0.99],'Scrollable','on');

sourceBar = uigridlayout(form,[1 3],'ColumnWidth',{'1x',58,70},'Padding',[0 0 0 0]);
wide(sourceBar,1);
uilabel(sourceBar,'Text','数据与通道','FontWeight','bold');
uilabel(sourceBar,'Text','数据来源');
sourceMenu = uidropdown(sourceBar,'Items',{'NI','LTT'},'Value','NI', ...
    'Tag','dataSource','ValueChangedFcn',@sourceChanged);
folderButton = uibutton(form,'Text','选择采集文件夹','ButtonPushedFcn',@loadFolder);
folderButton.Layout.Row = 2; folderButton.Layout.Column = [1 2];
channelMenu = uidropdown(form,'Items',{'通道'},'Enable','off','Tooltip','切换要读取和处理的通道', ...
    'Tag','dataChannel','ValueChangedFcn',@changeChannel);
channelMenu.Layout.Row = 2; channelMenu.Layout.Column = 3;
recordLabel = uilabel(form,'Text','尚未加载数据'); wide(recordLabel,3);

signalBar = uigridlayout(form,[1 3],'ColumnWidth',{'1x',58,70},'Padding',[0 0 0 0]);
wide(signalBar,4);
uilabel(signalBar,'Text','信号与滤波','FontWeight','bold');
uilabel(signalBar,'Text','信号类型');
signalType = uidropdown(signalBar,'Items',{'LFM','CW'},'Value','LFM', ...
    'Tag','signalType','ValueChangedFcn',@signalChanged);
band = fields(5,'带通频带 / kHz',[15 45],@filterChanged);
signalLabel = uilabel(form,'Text','LFM 起止 / kHz'); signalLabel.Layout.Row = 6; signalLabel.Layout.Column = 1;
chirp = gobjects(1,2);
for signalFieldIndex=1:2
    chirp(signalFieldIndex) = uieditfield(form,'numeric','Value',20*signalFieldIndex,'ValueChangedFcn',@filterChanged);
    chirp(signalFieldIndex).Layout.Row = 6; chirp(signalFieldIndex).Layout.Column = signalFieldIndex+1;
end
cwFrequency = uieditfield(form,'numeric','Value',30,'Visible','off', ...
    'Tag','cwFrequency','ValueChangedFcn',@filterChanged);
cwFrequency.Layout.Row = 6; cwFrequency.Layout.Column = [2 3];
width = fields(7,'信号脉宽 / ms',0.1,@filterChanged);
bpButton = uibutton(form,'Text','带通滤波','ButtonPushedFcn',@filterData);
bpButton.Layout.Row = 8; bpButton.Layout.Column = 1;
mfButton = uibutton(form,'Text','匹配滤波','ButtonPushedFcn',@filterData);
mfButton.Layout.Row = 8; mfButton.Layout.Column = [2 3];

if bistatic, sectionHeading(9,'脉冲范围'); else, sectionHeading(9,'固定横带背景抑制'); end
scan = fields(10,'处理脉冲（首 / 末）',[1 1],@gateChanged);
set(scan,'Tooltip','背景抑制与 TS 共用此范围；首末角度对应这两个脉冲。');
bgWindow = []; bgRef = []; bgButton = [];
if ~bistatic
bgWindow = fields(11,'背景时间窗 / ms',[0 0],@backgroundChanged);
bgMode = uidropdown(form,'Items',{'脉冲维高通','参考脉冲均值相减'},'ValueChangedFcn',@backgroundModeChanged);
wide(bgMode,12);
cutoff = fields(13,'截止 / (周期/脉冲)',0.01,@backgroundChanged);
cutoff.Tooltip = '半功率截止频率，0.01 对应 100 次脉冲一个周期';
bgRef = fields(14,'背景参考脉冲（首/末）',[1 1],@backgroundChanged);
set(bgRef,'Enable','off');
bgButton = uibutton(form,'Text','应用到扫描脉冲','Enable','off','ButtonPushedFcn',@removeBackground);
wide(bgButton,15);
else
    set(scan,'Tooltip','按接收方位顺序选择首、末脉冲');
    form.RowHeight(11:15) = repmat({0},1,5);
end
axisBar = uigridlayout(form,[1 2],'ColumnWidth',{'1x',144},'Padding',[0 0 0 0]);
wide(axisBar,16); uilabel(axisBar,'Text','采集方式与时间窗','FontWeight','bold');
axisMode = uidropdown(axisBar,'Items',{'角度扫描','固定方位重复采集'}, ...
    'ValueChangedFcn',@axisModeChanged,'Tag','acquisitionMode');
angle = fields(17,'首末角度 / °',[0 360],@invalidate);
direct = fields(18,'直达波窗 / ms',[0 0],@gateChanged);
if bistatic
    editor = uigridlayout(form,[2 4],'ColumnWidth',{75,'1x','1x',32},'Padding',[0 0 0 0], ...
        'RowHeight',{27,27},'RowSpacing',3);
    wide(editor,19); echo = gobjects(0,2); echoLabels = gobjects(0); removeButtons = gobjects(0);
    plus = uibutton(editor,'Text','＋ 添加回波窗','ButtonPushedFcn',@appendWindow);
    appendWindow();
else
    echo = fields(19,'回波窗 / ms',[0 0],@gateChanged);
end

sectionHeading(20,'收发距离与直达波参考');
dist = fields(21,'距离 L / r（m）',[2.46 1.43],@invalidate);
dist(1).Tooltip = '发射换能器到目标的距离'; dist(2).Tooltip = '水听器到目标的距离';
mode = uidropdown(form,'Items',{'逐脉冲直达波参考','固定脉冲直达波参考'}, ...
    'ValueChangedFcn',@modeChanged); wide(mode,22);
ref = fields(23,'固定参考脉冲',1,@invalidate); ref.Enable = 'off';
if bistatic
    mode.Items = {'固定脉冲直达波参考'}; mode.Value = mode.Items{1}; ref.Enable = 'on';
    ref.Tooltip = '使用共线位置（发射阵—水听器—目标）的参考脉冲，参考距离 L−r';
end

tsBar = uigridlayout(form,[1 2],'ColumnWidth',{'1x',105},'Padding',[0 0 0 0]);
wide(tsBar,24);
uilabel(tsBar,'Text','目标强度计算','FontWeight','bold');
tsScope = uidropdown(tsBar,'Items',{'单频点','扫频范围'},'Value','扫频范围', ...
    'Tooltip','选择 TS 计算范围','ValueChangedFcn',@scopeChanged);
freq = fields(25,'TS 频点 / kHz',30,@frequencyChanged);
sweepBand = fields(26,'扫频范围 / kHz',[20 40],@sweepChanged);
step = fields(27,'扫频间隔 / kHz',0.2,@sweepChanged);
singleButton = uibutton(form,'Text','计算单频 TS','ButtonPushedFcn',@calculate);
singleButton.Layout.Row = 28; singleButton.Layout.Column = 1;
sweepButton = uibutton(form,'Text','计算全频段 TS','ButtonPushedFcn',@calculateSweep);
sweepButton.Layout.Row = 28; sweepButton.Layout.Column = [2 3];

sectionHeading(29,'结果导出');
sizeLabel = uilabel(form,'Text','导出图幅');
sizeLabel.Layout.Row = 30; sizeLabel.Layout.Column = 1;
exportSize = uidropdown(form,'Items',{'小图 · 8 × 6 cm · 8 pt','大图 · 16 × 12 cm · 11 pt'}, ...
    'ItemsData',[8 16],'Value',8);
exportSize.Layout.Row = 30; exportSize.Layout.Column = [2 3];
saveButton = uibutton(form,'Text','导出结果 MAT','Enable','off','ButtonPushedFcn',@saveResult);
saveButton.Layout.Row = 31; saveButton.Layout.Column = 1;
plotButton = uibutton(form,'Text','导出当前图 PNG + FIG','Enable','off','ButtonPushedFcn',@savePlot);
plotButton.Layout.Row = 31; plotButton.Layout.Column = [2 3];
bundle = uibutton(form,'Text','导出全部图表与数据','Enable','off','ButtonPushedFcn',@exportBundle);
wide(bundle,32);
footer = uigridlayout(sidebar,[1 3],'ColumnWidth',{'1x',62,72},'Padding',[4 4 4 4], ...
    'ColumnSpacing',4,'BackgroundColor',[0.91 0.95 0.96]);
status = uilabel(footer,'Text','请选择一次采集的日期时间文件夹。','WordWrap','on', ...
    'FontColor',[0.12 0.27 0.32],'BackgroundColor',[0.91 0.95 0.96]);
refreshButton = uibutton(footer,'Text','刷新视图','Tooltip','按当前选窗和色阶重绘本页', ...
    'Enable','off','ButtonPushedFcn',@refreshView);
uibutton(footer,'Text','返回首页','ButtonPushedFcn',@(~,~) goHome(fig));

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
pick = uidropdown(bar,'Items',{'点击查看脉冲','点两次选脉冲范围','点两次选直达波窗','点两次选回波窗','点两次选背景窗'}, ...
    'ValueChangedFcn',@armPick);
if bistatic
    view.Items = view.Items(1:3); syncPick();
end
uibutton(bar,'Text','显示整组波形图','ButtonPushedFcn',@showMapWithProgress, ...
    'Interruptible','off','BusyAction','cancel', ...
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
figureNames = {'单频 TS','回波时间–角度图','多频点 TS–角度曲线','多角度 TS–频率曲线', ...
    'TS 频率–角度谱','频带能量平均 TS–角度曲线','角度能量平均 TS–频率曲线'};
scanNames = figureNames; scanCombinedNames = combinedNames;
resultBar = uigridlayout(resultLayout,[1 3],'ColumnWidth',{52,230,'1x'}, ...
    'Padding',[8 4 8 4],'ColumnSpacing',6,'BackgroundColor',barColor);
uilabel(resultBar,'Text','结果图','FontWeight','bold','FontColor',ink);
figureChoice = uidropdown(resultBar,'Items',figureNames(1),'ValueChangedFcn',@showResult);
if bistatic
    echoSelect = uidropdown(resultBar,'Items',{'回波 1'},'ItemsData',1,'Enable','off', ...
        'Tooltip','选择要查看或单独导出的回波','ValueChangedFcn',@chooseResult);
end
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
    function appendWindow(varargin)
        n = size(echo,1)+1;
        echoLabels(n) = uilabel(editor,'Text','');
        for col = 1:2
            echo(n,col) = uieditfield(editor,'numeric','ValueChangedFcn',@gateChanged);
        end
        removeButtons(n) = uibutton(editor,'Text','−','Tooltip','删除这条回波窗','ButtonPushedFcn',@dropWindow);
        layoutWindows();
        if n>1, syncPick(); gateChanged(); end
    end
    function dropWindow(src,~)
        n = find(removeButtons==src,1);
        delete(echo(n,:)); delete(echoLabels(n)); delete(removeButtons(n));
        echo(n,:)=[]; echoLabels(n)=[]; removeButtons(n)=[];
        layoutWindows(); syncPick(); gateChanged();
    end
    function layoutWindows()
        n = size(echo,1);
        editor.RowHeight = repmat({27},1,n+1); form.RowHeight{19} = 27*(n+1)+3*n;
        for j=1:n
            echoLabels(j).Text = sprintf('回波 %d / ms',j);
            controls = [echoLabels(j) echo(j,:) removeButtons(j)];
            for c=1:4, controls(c).Layout.Row=j; controls(c).Layout.Column=c; end
            removeButtons(j).Enable = matlab.lang.OnOffSwitchState(n>1);
        end
        plus.Layout.Row=n+1; plus.Layout.Column=[1 4];
    end
    function syncPick()
        pickStart = []; pick.Items = [{'点击查看脉冲','点两次选脉冲范围','点两次选直达波窗'}, ...
            reshape(cellstr(compose('点两次选回波窗 %d',1:size(echo,1))),1,[])];
        pick.Value=pick.Items{1};
    end
    function handles = pickedEcho()
        if bistatic
            index = find(strcmp(pick.Items,pick.Value),1)-3;
            handles = echo(index,:);
        else
            handles = echo;
        end
    end
    function chooseResult(varargin)
        captureDraggedScale(); result = echoResults{echoSelect.Value};
        result.colorScale = scaleSettings; showResult();
    end
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
            if any(strcmp(figureChoice.Value,[figureNames(5) combinedNames(6:7)])), group = 'ts'; else, group = 'wave'; end
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
        if ~isempty(result) && any(strcmp(figureChoice.Value,[figureNames([2 5]) combinedNames(6:7)]))
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
        combined = [];
        echoResults = {};
        if bistatic, echoSelect.Enable = 'off'; end
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
    function axisModeChanged(varargin)
        repeated = strcmp(axisMode.Value,'固定方位重复采集');
        set(angle,'Enable',matlab.lang.OnOffSwitchState(~repeated));
        figureNames = scanNames; combinedNames = scanCombinedNames;
        if repeated
            figureNames = strrep(scanNames,'角度','脉冲');
            combinedNames = strrep(scanCombinedNames,'角度','脉冲');
            set(scan,'Tooltip','填写要处理的首末采集列号，从 1 开始。');
        else
            set(scan,'Tooltip','首末脉冲分别对应扫描首末角度。');
        end
        invalidate();
    end
    function signalChanged(src,event)
        isCW = strcmp(signalType.Value,'CW');
        cwFrequency.Visible = matlab.lang.OnOffSwitchState(isCW);
        set(chirp,'Visible',matlab.lang.OnOffSwitchState(~isCW));
        if isCW, signalLabel.Text = 'CW 频率 / kHz'; else, signalLabel.Text = 'LFM 起止 / kHz'; end
        if isCW
            tsScope.Value = '单频点'; freq.Value = cwFrequency.Value;
        else
            tsScope.Value = '扫频范围';
        end
        scopeChanged();
        filterChanged(src,event);
        status.Text = ['已切换为 ' signalType.Value '，请核对信号频率、脉宽和带通频带，重新进行匹配滤波。'];
    end
    function res = stampSignal(res)
        res.signalType = signalType.Value;
        res.pulseWidth_ms = numbers(width);
        res.cwFrequency_kHz = []; res.lfm_kHz = [];
        if strcmp(signalType.Value,'CW')
            res.cwFrequency_kHz = cwFrequency.Value;
        else
            res.lfm_kHz = numbers(chirp);
        end
    end
    function filterChanged(src,~)
        if isequal(src,cwFrequency) && strcmp(tsScope.Value,'单频点') && strcmp(signalType.Value,'CW')
            freq.Value = cwFrequency.Value;
            invalidate();
        end
        if any(src==band)
            backgroundPending = backgroundPending || ~isempty(clean);
            clean = []; cleanPulses = []; if ~bistatic, bgButton.Enable = 'off'; end
            if strcmp(view.Value,cleanView), view.Value = '带通波形'; end
            bp = []; invalidate(); staleView = '带通波形';
        else
            mf = []; staleView = '匹配滤波';
            if ~isempty(result)
                result = stampSignal(result);
                for j=1:numel(echoResults), echoResults{j} = stampSignal(echoResults{j}); end
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
        if ~isempty(clean)
            backgroundPending = true;
            invalidate();
        end
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
        dlg = uiprogressdlg(fig,'Cancelable','on','CancelText','取消','Title','背景抑制','Message','处理选区');
        cleanup = onCleanup(@() close(dlg));
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
                filtered = pulseHighpass(bp(rows,cols),fc,dlg);
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
            checkCancel(dlg);
            clean = bp;
            clean(rows,cols) = filtered;
            cleanPulses = bounds;
            backgroundPending = false;
            invalidate();
            resetPick(); view.Value = cleanView; tabs.SelectedTab = waveTab; drawMap();
            status.Text = sprintf('%s · 脉冲 %d–%d · %.4g–%.4g ms', ...
                description,bounds,timeSeconds(rows([1 end]))*1000);
        catch err
            if strcmp(err.identifier,'cornerTS:Cancelled'), status.Text = '已取消，本次临时数据已丢弃。'; return; end
            uialert(fig,err.message,'固定横带背景抑制');
        end
    end
    function sourceChanged(varargin)
        raw = []; bp = []; mf = []; clean = []; cleanPulses = [];
        fs = []; timeSeconds = []; recordNumbers = []; recordFiles = {};
        folder = ''; dataOrigin = ''; activeChannel = ''; backgroundPending = false;
        if ~bistatic, bgButton.Enable = 'off'; end
        channelMenu.Items = {'通道'}; channelMenu.Enable = 'off';
        resetPick(); invalidate(); view.Value = '原始波形'; clearMap(); cla(trace);
        refreshButton.Enable = 'off'; recordLabel.Text = '尚未加载数据';
        if strcmp(sourceMenu.Value,'LTT')
            angle(1).Value = 0; angle(2).Value = 0;
        else
            angle(1).Value = 0; angle(2).Value = 360;
        end
        status.Text = ['已切换到 ' sourceMenu.Value '，请选择一个采集工况文件夹。'];
    end
    function loadFolder(varargin)
        startDir = fullfile(project,'数据');
        if ~isfolder(startDir), startDir = pwd; end
        prompt = '选择含 JSON 与 MAT 的 NI 采集文件夹';
        if strcmp(sourceMenu.Value,'LTT'), prompt = '选择一个 LTT 工况文件夹或其 00000 子目录'; end
        selected = uigetdir(startDir,prompt);
        if isequal(selected,0), return; end
        try
            if strcmp(sourceMenu.Value,'LTT')
                readChannel(selected,'');
                return
            end
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
            if strcmp(err.identifier,'cornerTS:Cancelled'), status.Text = '已取消，本次临时数据已丢弃。'; return; end
            uialert(fig,err.message,'读取失败');
        end
    end
    function changeChannel(src,~)
        try
            readChannel(folder,src.Value);
        catch err
            src.Value = activeChannel;
            if strcmp(err.identifier,'cornerTS:Cancelled'), status.Text = '已取消，本次临时数据已丢弃。'; return; end
            uialert(fig,err.message,'切换通道失败');
        end
    end
    function readChannel(selected,channel)
        dlg = uiprogressdlg(fig,'Cancelable','on','CancelText','取消','Title','读取采集记录','Message','正在读取文件');
        cleanup = onCleanup(@() close(dlg));
        readTimer = tic;
        if strcmp(sourceMenu.Value,'LTT')
            imported = readLTTFolder(selected,channel,dlg);
            values = imported.values; rate = imported.fs;
            selected = imported.folder; channel = imported.channel;
            channels = imported.channels; times = imported.timeSeconds;
            indices = imported.recordNumbers; filenames = imported.recordFiles;
            [~,id] = fileparts(selected);
            if strcmp(id,'00000'), [~,id] = fileparts(fileparts(selected)); end
            samples = size(values,1); count = size(values,2);
        else
        [~,id] = fileparts(selected);
        meta = jsondecode(fileread(fullfile(selected,[id '.json'])));
        rate = meta.SampleRate_Hz_; count = meta.CollectTimes;
        samples = round(meta.SingalTime_ms_*rate/1000);
        assert(rate>0 && samples>=2 && count>=1 && count==fix(count),'JSON 采集参数无效。');
        values = zeros(samples,count);
        filenames = cell(1,count);
        for k = 1:count
            name = sprintf('%s_%d_%s.mat',id,k,channel);
            filenames{k} = name;
            loaded = load(fullfile(selected,name)); names = fieldnames(loaded);
            assert(isscalar(names),'文件 %s 中的信号变量不唯一。',name);
            v = loaded.(names{1});
            assert(isnumeric(v) && isreal(v) && isvector(v) && numel(v)==samples && ...
                all(isfinite(v(:))),'文件 %s 的波形或采样点数异常。',name);
            values(:,k) = double(v(:));
            if mod(k,20)==0, dlg.Value = k/count; checkCancel(dlg); end
        end
        times = (0:samples-1)'/rate; indices = 1:count;
        end
        checkCancel(dlg);
        readSeconds = toc(readTimer);
        sameRecord = strcmp(dataOrigin,sourceMenu.Value) && strcmp(folder,selected) && ...
            isequal(size(raw),size(values)) && isequal(timeSeconds,times);
        raw = values; fs = rate; folder = selected; activeChannel = channel; bp = []; mf = [];
        dataOrigin = sourceMenu.Value; timeSeconds = times;
        recordNumbers = indices; recordFiles = filenames;
        if strcmp(dataOrigin,'LTT')
            channelMenu.Items = channels; channelMenu.Value = channel; channelMenu.Enable = 'on';
        end
        backgroundPending = false;
        clean = []; cleanPulses = []; if ~bistatic, bgButton.Enable = 'off'; end
        if ~sameRecord
            if ~bistatic, bgRef(1).Value = 1; bgRef(2).Value = count; end
            scan(1).Value = 1; scan(2).Value = count; ref.Value = 1; pulse.Value = 1;
            for h = [direct reshape(echo,1,[]) bgWindow], h.Value = timeSeconds(1)*1000; end
            if strcmp(dataOrigin,'LTT'), angle(1).Value = 0; angle(2).Value = 0; end
            if strcmp(dataOrigin,'NI') && ~bistatic && strcmp(id,'20261031_151830') && count>=833 && samples>=4780
                scan(1).Value = 112; scan(2).Value = 833;
                gates = ([1050 2011 3362 4780]-1)*1000/fs;
                boxes = [direct echo];
                for k = 1:4, boxes(k).Value = gates(k); end
            end
        end
        resetPick(); invalidate(); view.Value = '原始波形';
        recordLabel.Text = sprintf('%s · %s · %d 次 · %g kHz',id,channel,count,rate/1000);
        recordLabel.Tooltip = sprintf('%s · %d 点/次 · 时间 %.6g 至 %.6g ms', ...
            dataOrigin,samples,timeSeconds([1 end])*1000);
        refreshButton.Enable = 'on';
        tabs.SelectedTab = waveTab; clearMap(); showTrace();
        status.Text = sprintf('已读取 %s 的 %d 个文件，用时 %.1f 秒。',channel,count,readSeconds);
        if strcmp(dataOrigin,'LTT')
            status.Text = [status.Text ' 请按工况选择固定方位或填写扫描角度，并设置频带。'];
            if imported.missingMetadata>0
                status.Text = [status.Text sprintf(' %d 个 TXT 缺失，仅按 CSV 校验。',imported.missingMetadata)];
            end
        end
    end
    function filterData(src,~)
        isBand = src==bpButton;
        dlg = uiprogressdlg(fig,'Cancelable','on','CancelText','取消','Title',src.Text,'Message','0%','Value',0);
        cleanup = onCleanup(@() close(dlg));
        try
            assert(~isempty(raw),'请先读取采集文件夹。');
            count = size(raw,2);
            if isBand
                b = numbers(band)*1000;
                assert(b(1)>0 && diff(b)>0 && b(2)<fs/2,'带通频带须递增且在奈奎斯特频率以内。');
            else
                duration = numbers(width)/1000;
                assert(duration*fs>=1 && duration*fs<size(raw,1),'脉宽超出记录范围。');
                if strcmp(signalType.Value,'CW')
                    f = cwFrequency.Value*1000;
                    assert(isfinite(f) && f>0 && f<fs/2,'CW 频率须大于零且小于奈奎斯特频率。');
                    replica = LFM(f,f,fs,duration); % 零扫频率时退化为同相位约定的单频正弦。
                else
                    f = numbers(chirp)*1000;
                    assert(f(1)>0 && diff(f)>0 && f(2)<fs/2,'LFM 频带须递增且在奈奎斯特频率以内。');
                    replica = LFM(f(1),f(2),fs,duration);
                end
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
                    checkCancel(dlg);
                    lastPct = pct;
                end
            end
            checkCancel(dlg);
            if isBand
                backgroundPending = backgroundPending || ~isempty(clean);
                clean = []; cleanPulses = []; if ~bistatic, bgButton.Enable = 'on'; end
                bp = filtered; invalidate(); view.Value = '带通波形';
            else
                mf = filtered; view.Value = '匹配滤波';
            end
            resetPick(); tabs.SelectedTab = waveTab;
            dlg.Message = '100% · 正在显示滤波结果'; drawMap();
            status.Text = [src.Text '完成。'];
        catch err
            if strcmp(err.identifier,'cornerTS:Cancelled'), status.Text = '已取消，本次临时数据已丢弃。'; return; end
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
        showMapWithProgress();
    end
    function armPick(varargin)
        pickStart = [];
        if strcmp(pick.Value,'点击查看脉冲'), return; end
        if isempty(bp), resetPick(); status.Text = '请先完成滤波。'; return; end
        wanted = '带通波形';
        if strcmp(pick.Value,'点两次选直达波窗') || startsWith(pick.Value,'点两次选回波窗')
            if backgroundPending
                resetPick(); status.Text = '请重新应用背景抑制后再选取时间窗。'; return
            end
            if ~isempty(clean), wanted = cleanView; end
        elseif strcmp(view.Value,cleanView)
            wanted = cleanView;
        end
        if ~strcmp(view.Value,wanted), view.Value = wanted; showMapWithProgress(); end
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
    function showMapWithProgress(varargin)
        if isempty(displayed())
            status.Text = '请先读取数据或完成所选滤波。';
            return
        end
        dlg = uiprogressdlg(fig,'Title','显示整组波形图', ...
            'Message',['正在生成' view.Value '，请稍候…'],'Indeterminate','on');
        cleanup = onCleanup(@() close(dlg));
        try
            drawnow; % 在幅值转换、色阶计算与整组热图绘制前显示提示。
            drawMap();
            drawnow; % 等待图像更新后再关闭提示。
        catch err
            clear cleanup
            uialert(fig,err.message,'波形图显示失败');
        end
    end
    function drawMap(varargin)
        captureDraggedScale();
        values = displayed();
        if isempty(values), return; end
        times = timeSeconds*1000;
        db = 20*log10(abs(values));
        im = imagesc(map,[1 size(values,2)],times([1 end]),db);
        title(map,''); im.ButtonDownFcn = @mapClick; map.YDir = 'normal'; colormap(map,jet(256));
        waveInfo.Text = applyScale(map,im,scaleSettings.wave,true);
        syncScale(waveScale,map,scaleSettings.wave,'波形色阶');
        xlim(map,[0.5 size(values,2)+0.5]); ylim(map,times([1 end]));
        xlabel(map,'原始脉冲序号'); ylabel(map,'时间 / ms');
        if strcmp(dataOrigin,'LTT'), xlabel(map,'采集列号（按 M 序号排序）'); end
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
            case '点两次选脉冲范围', target = scan; value = k;
            case '点两次选直达波窗', target = direct; value = point(2);
            case '点两次选背景窗', target = bgWindow; value = point(2);
            otherwise, target = pickedEcho(); value = point(2);
        end
        setBoundary(target,value);
    end
    function traceClick(~,event)
        if isempty(bp) || ~ismember(view.Value,{'带通波形',cleanView}), return; end
        switch pick.Value
            case '点两次选直达波窗', target = direct;

            case '点两次选背景窗', target = bgWindow;
            otherwise
                if ~startsWith(pick.Value,'点两次选回波窗'), return; end
                target = pickedEcho();
        end
        value = max(timeSeconds(1)*1000,min(event.IntersectionPoint(1),timeSeconds(end)*1000));
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
            if ~bistatic && bgWindow(2).Value>bgWindow(1).Value
                gateLines(4,k) = yline(map,bgWindow(k).Value,'y:','HitTest','off');
            end
            if direct(2).Value>direct(1).Value
                gateLines(2,k) = yline(map,direct(k).Value,'c-','HitTest','off');
            end
            for j=1:size(echo,1)
                if echo(j,2).Value>echo(j,1).Value
                    gateLines(4+j,k) = yline(map,echo(j,k).Value,'m-','HitTest','off');
                    if bistatic && k==1, gateLines(4+j,k).Label = sprintf('回波 %d',j); end
                end
            end
        end
    end
    function showTrace(varargin)
        values = displayed(); if isempty(values), return; end
        k = min(size(values,2),max(1,round(pulse.Value))); pulse.Value = k;
        line = plot(trace,timeSeconds*1000,values(:,k),'Color',[0.12 0.28 0.48]);
        trace.ButtonDownFcn = @traceClick; line.ButtonDownFcn = @traceClick;
        xlabel(trace,'时间 / ms'); ylabel(trace,'幅值');
        title(trace,sprintf('脉冲 %d · %s',k,view.Value)); grid(trace,'on');
        if strcmp(dataOrigin,'LTT')
            title(trace,sprintf('采集列 %d · M%04d · %s · %s',k,recordNumbers(k),activeChannel,view.Value));
            ylabel(trace,'电压 / V');
        end
        pbaspect(trace,[2 1 1]);
        configurePreview(trace); disableDefaultInteractivity(trace);
        if ismember(view.Value,{'带通波形',cleanView})
            if ~bistatic && bgWindow(2).Value>bgWindow(1).Value
                for h = bgWindow, xline(trace,h.Value,':','Color',[.60 .40 0],'HitTest','off'); end
            end
            if direct(2).Value>direct(1).Value
                for h = direct, xline(trace,h.Value,'--','Color',[0 .52 .55],'HitTest','off'); end
            end
            for j=1:size(echo,1)
                if echo(j,2).Value>echo(j,1).Value
                    for h = echo(j,:), xline(trace,h.Value,'-','Color',[.70 .12 .52],'HitTest','off'); end
                end
            end
        end
    end
    function idx = samplesIn(handles)
        bounds = numbers(handles); times = timeSeconds*1000;
        assert(bounds(1)>=times(1) && bounds(2)<=times(end) && diff(bounds)>0,'请设置记录范围内的起止时间窗。');
        limits = round((bounds/1000-timeSeconds(1))*fs)+1;
        limits = max(1,min(numel(timeSeconds),limits));
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
    function scopeChanged(varargin)
        sweepOn = strcmp(tsScope.Value,'扫频范围');
        enabled = matlab.lang.OnOffSwitchState(sweepOn);
        set(sweepBand,'Enable',enabled); step.Enable = enabled; sweepButton.Enable = enabled;
        if ~sweepOn && strcmp(signalType.Value,'CW'), freq.Value = cwFrequency.Value; end
        invalidate();
    end
    function sweepChanged(varargin)
        if ~isempty(result) && isfield(result,'spectrum')
            result = rmfield(result,'spectrum');
            if bistatic
                for j=1:numel(echoResults), echoResults{j}=rmfield(echoResults{j},'spectrum'); end
                combined = selectCombination(combined,result.frequency_Hz);
            end
            items = figureNames(1:2);
            figureChoice.Items = items; figureChoice.Value = figureNames{1};
            bundle.Enable = 'on'; showResult();
        end
        status.Text = '扫频参数已更新。点击“计算全频段 TS”生成新频谱。';
    end
    function compute(fullBand)
        dlg = uiprogressdlg(fig,'Cancelable','on','CancelText','取消','Title','计算 TS','Message','提取窗内幅值');
        cleanup = onCleanup(@() close(dlg));
        try
            assert(~isempty(bp),'请先完成滤波。');
            assert(~backgroundPending,'背景抑制参数或输入已改变，请重新应用到扫描脉冲后再计算 TS。');
            [signal,signalSource] = analysisSignal();
            bounds = numbers(scan); geometry = numbers(dist);
            assert(all(bounds==fix(bounds)) && bounds(1)>=1 && diff(bounds)>=0 && ...
                bounds(2)<=size(bp,2),'处理范围须填写有效的首末脉冲序号。');
            pulses = bounds(1):bounds(2);
            if strcmp(axisMode.Value,'固定方位重复采集')
                theta = []; angles = [];
            else
                angles = numbers(angle);
                assert(isscalar(pulses) || diff(angles)~=0,'请填写实际扫描首末角度，或选择固定方位重复采集。');
                theta = linspace(angles(1),angles(2),numel(pulses));
                if isscalar(pulses), theta = angles(1); end
            end
            L = geometry(1); r = geometry(2);
            assert(L>r && r>0,'当前传播修正要求 L > r > 0。');
            d = samplesIn(direct); ff = numbers(freq)*1000;
            windows = cell(1,size(echo,1));
            for j=1:numel(windows)
                try
                    windows{j} = samplesIn(echo(j,:));
                catch gateError
                    error('回波窗 %d：%s',j,gateError.message);
                end
            end
            b = numbers(band)*1000;
            if bistatic && numel(unique([windows{:}]))~=sum(cellfun(@numel,windows))
                error('回波窗在采样点上重叠，强度相加会重复计入回波。请分开各窗后再计算。');
            end
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
            computed = cell(size(windows));
            for w=1:numel(windows)
                e = windows{w};
                previous = result;
                if bistatic && ~isempty(echoResults), previous = echoResults{w}; end
                cachedRow = [];
                if ~fullBand && isfield(previous,'spectrum')
                    cachedRow = find(abs(previous.spectrum.frequency_Hz-ff)<=8*eps(ff),1);
                end
                if ~isempty(cachedRow)
                    pdAll = previous.spectrum.directAmplitude(cachedRow,:);
                    peAll = previous.spectrum.echoAmplitude(cachedRow,:);
                elseif ~fullBand && ~isempty(previous) && previous.frequency_Hz==ff
                    pdAll = previous.directAmplitude; peAll = previous.echoAmplitude;
                else
                    [pdAll,peAll] = windowAmplitudes(signal(d,refs),signal(e,pulses),fs,frequencies,dlg);
                end
                assert(all(pdAll(:)>0 & isfinite(pdAll(:))),'直达波幅值无效，请检查参考脉冲和直达波窗。');
                ratios = peAll*r./(pdAll*((L-r)/L));
                assert(all(isfinite(ratios(:)) & ratios(:)>0),'TS 幅值无效，请检查脉冲与时间窗。');
                selected = find(frequencies==ff,1);
                pd = pdAll(selected,:); pe = peAll(selected,:);
                ratio = ratios(selected,:); ts = 20*log10(ratio);
                next = struct('folder',folder,'channel',activeChannel,'fs_Hz',fs,'band_kHz',b/1000, ...
                    'frequency_Hz',ff, ...
                    'pulse',pulses,'referenceMode',mode.Value,'referencePulse',refs, ...
                    'angle_deg',theta,'angleLimits_deg',angles,'directSamples',d([1 end]),'echoSamples',e([1 end]), ...
                    'direct_ms',numbers(direct),'echo_ms',numbers(echo(w,:)),'L_m',L,'r_m',r, ...
                    'directAmplitude',pd,'echoAmplitude',pe,'TS_dB',ts, ...
                    'energyMean_dB',10*log10(acquisitionMeanPower(theta,ratio.^2)),'peakToPeak_dB',max(ts)-min(ts));
                if fullBand
                    [~,rows] = ismember(gridHz,frequencies);
                    next.spectrum = summarizeSpectrum(theta,pulses,gridHz,ratios(rows,:));
                    next.spectrum.directAmplitude = pdAll(rows,:);
                    next.spectrum.echoAmplitude = peAll(rows,:);
                    if numel(theta)>1 && abs(abs(theta(end)-theta(1))-360)<1e-8 && strcmp(mode.Value,'逐脉冲直达波参考')
                        diameter = 4*10^(next.spectrum.mean_dB/20);
                        next.spectrum.equivalentDiameter_m = diameter;
                        next.spectrum.kaRange = pi*gridHz([1 end])'*diameter/1500;
                    end
                elseif isfield(previous,'spectrum')
                    next.spectrum = previous.spectrum;
                end
                next = stampSignal(next);
                next.colorScale = scaleSettings;
                next.dataSource = dataOrigin;
                next.acquisitionMode = axisMode.Value;
                next.timeOrigin_s = timeSeconds(1);
                next.time_s = timeSeconds;
                next.acquisitionNumber = recordNumbers(pulses);
                next.acquisitionFiles = recordFiles(pulses);
                next.signalSource = signalSource;
                if ~isempty(clean)
                    next.background = struct('method',bgMode.Value,'pulseRange',cleanPulses,'window_ms',numbers(bgWindow));
                    if strcmp(bgMode.Value,'脉冲维高通')
                        next.background.cutoff_cyclesPerPulse = numbers(cutoff);
                    else
                        next.background.referencePulseRange = numbers(bgRef);
                    end
                end
                next.processingMode = pageName; next.echoIndex = w;
                computed{w} = next;
            end
            if bistatic
                if fullBand || isempty(combined)
                    newCombined = combineEchoWindows(signal,d,refs,windows,pulses,fs,frequencies,L,r,dlg);
                elseif any(combined.frequency_Hz==ff)
                    newCombined = combined;
                else
                    newCombined = combineEchoWindows(signal,d,refs,windows,pulses,fs,ff,L,r,dlg);
                    if isfield(computed{1},'spectrum')
                        gridOnly = selectCombination(combined,computed{1}.spectrum.frequency_Hz);
                        newCombined.frequency_Hz = [gridOnly.frequency_Hz; ff];
                        newCombined.coherent_dB = [gridOnly.coherent_dB; newCombined.coherent_dB];
                        newCombined.incoherent_dB = [gridOnly.incoherent_dB; newCombined.incoherent_dB];
                    end
                end
                newCombined.angle_deg = theta; newCombined.pulse = pulses;
                newCombined.acquisitionMode = axisMode.Value;
                newCombined.selectedFrequency_Hz = ff;
                checkCancel(dlg);
                combined = newCombined;
                selectedEcho = min(echoSelect.Value,numel(computed));
                echoSelect.ItemsData = [];
                echoSelect.Items = cellstr(compose('回波 %d',1:numel(computed)));
                echoSelect.ItemsData = 1:numel(computed); echoSelect.Value = selectedEcho;
                echoSelect.Enable = 'on'; echoResults = computed;
                result = computed{selectedEcho};
            else
                checkCancel(dlg);
                result = computed{1};
            end
            if isfield(result,'spectrum')
                figureChoice.Items = figureNames;
            else
                figureChoice.Items = figureNames(1:2);
            end
            bundle.Enable = 'on';
            if fullBand, figureChoice.Value = figureNames{5}; else, figureChoice.Value = figureNames{1}; end
            if bistatic && isfield(result,'spectrum')
                figureChoice.Items = [figureChoice.Items(:).' combinedNames];
                if fullBand, figureChoice.Value = combinedNames{1}; end
            end
            showResult(); saveButton.Enable = 'on'; plotButton.Enable = 'on';
            tabs.SelectedTab = resultTab; status.Text = ['计算完成 · TS 数据来源：' signalSource];
        catch err
            if ~fullBand && ~isempty(result), freq.Value = result.frequency_Hz/1000; end
            if strcmp(err.identifier,'cornerTS:Cancelled'), status.Text = '已取消，本次临时数据已丢弃。'; return; end
            uialert(fig,err.message,'无法计算 TS');
        end
    end
    function [signal,source] = analysisSignal()
        if isempty(clean)
            signal = bp; source = '带通波形';
        else
            signal = clean; source = cleanView;
        end
    end
    function showResult(varargin)
        if isempty(result), return; end
        captureDraggedScale();
        resultInfo.Text = renderResult(curve,figureChoice.Value);
        configurePreview(curve);
        resultScale.row.Visible = 'off';
        resultLayout.RowHeight = {40,'1x',0,0,54};
        if bistatic
            echoSelect.Enable = matlab.lang.OnOffSwitchState(~any(strcmp(figureChoice.Value,combinedNames)));
            if any(strcmp(figureChoice.Value,combinedNames))
                if any(strcmp(figureChoice.Value,combinedNames(1:3)))
                    f = result.spectrum.frequency_Hz;
                    stats.Text = sprintf('%g–%g kHz · %d 个扫频点的线性能量平均 · %d 条回波窗', ...
                        f(1)/1000,f(end)/1000,numel(f),numel(echoResults));
                elseif any(strcmp(figureChoice.Value,combinedNames(4:5)))
                    if isempty(result.angle_deg)
                        stats.Text = sprintf('脉冲 %d–%d · %d 次采集的线性能量平均 · %d 条回波窗', ...
                            result.pulse(1),result.pulse(end),numel(result.pulse),numel(echoResults));
                    else
                        stats.Text = sprintf('%g°–%g° · 扫描角度范围内的线性能量平均 · %d 条回波窗', ...
                            result.angle_deg(1),result.angle_deg(end),numel(echoResults));
                    end
                else
                    f = result.spectrum.frequency_Hz;
                    axisUnit = '个角度';
                    if isempty(result.angle_deg), axisUnit = '次脉冲'; end
                    stats.Text = sprintf('%g–%g kHz · %d 个频点 × %d %s · %d 条回波窗合成', ...
                        f(1)/1000,f(end)/1000,numel(f),numel(result.pulse),axisUnit,numel(echoResults));
                    resultLayout.RowHeight = {40,'1x',36,20,54};
                    resultScale.row.Visible = 'on';
                    syncScale(resultScale,curve,scaleSettings.ts,'TS 色阶');
                end
                return
            end
        end
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
            if isempty(result.angle_deg)
                stats.Text = sprintf('%g–%g kHz · 脉冲能量平均 %.2f dB · 峰值 %.2f dB（脉冲 %d） · 谷值 %.2f dB（脉冲 %d）', ...
                    sp.frequency_Hz([1 end])/1000,sp.mean_dB,sp.max_dB,sp.maxPulse,sp.min_dB,sp.minPulse);
                return
            end
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
        if bistatic, xtext = '接收方位角 / °'; end
        repeated = isempty(theta);
        if repeated, theta = result.pulse; xtext = '脉冲序号'; end
        if isfield(result,'spectrum'), sp = result.spectrum; f = sp.frequency_Hz/1000; end
        switch kind
            case combinedNames(6:7)
                c = selectCombination(combined,result.spectrum.frequency_Hz);
                values = c.coherent_dB;
                if strcmp(kind,combinedNames{7}), values = c.incoherent_dB; end
                info = heat(ax,theta,f,values,scaleSettings.ts,false);
                ytext = '频率 / kHz';
            case combinedNames(1:5)
                which = find(strcmp(kind,combinedNames),1);
                if which<=3
                    [coherent,incoherent] = combinedBandMean();
                    info = '各频点先分别合成，再对扫频网格的线性强度求平均；不跨频点相干相加。';
                    x = theta;
                else
                    [coherent,incoherent] = combinedAcquisitionMean();
                    x = f; xtext = '频率 / kHz';
                    info = '各频点分别对扫描角度范围的线性强度作角度积分平均，再转换为 dB。';
                    if repeated, info = '各频点分别对所选脉冲的线性强度等权平均，再转换为 dB。'; end
                end
                if which==1
                    plot(ax,x,coherent,'-','LineWidth',1.3);
                    hold(ax,'on'); plot(ax,x,incoherent,'--','LineWidth',1.3); hold(ax,'off');
                    legend(ax,{'相干合成','非相干强度和'},'Location','southoutside','NumColumns',2);
                elseif any(which==[2 4])
                    plot(ax,x,coherent,'-','LineWidth',1.3);
                else
                    plot(ax,x,incoherent,'-','LineWidth',1.3);
                end
            case figureNames{1}
                plot(ax,theta,result.TS_dB,'-','LineWidth',1.2);
            case figureNames{2}
                idx = result.echoSamples(1):result.echoSamples(2);
                signal = analysisSignal();
                info = heat(ax,theta,timeSeconds(idx)*1000,20*log10(abs(signal(idx,result.pulse))),scaleSettings.wave,true);
                ytext = '时间 / ms';
            case figureNames{3}
                targets = ceil(f(1)/5)*5:5:floor(f(end)/5)*5;
                idx = nearest(f,[f(1) targets f(end)]);
                curves(ax,theta,sp.TS_dB(idx,:).',compose('%g kHz',f(idx)));
            case figureNames{4}
                if repeated
                    idx = unique(round(linspace(1,numel(theta),min(5,numel(theta)))));
                    labels = compose('脉冲 %d',theta(idx));
                else
                    targets = ceil(min(theta)/30)*30:30:floor(max(theta)/30)*30;
                    idx = nearest(theta,[min(theta) targets max(theta)]);
                    labels = compose('%g°',theta(idx));
                end
                curves(ax,f,sp.TS_dB(:,idx),labels);
                xtext = '频率 / kHz';
            case figureNames{5}
                info = heat(ax,theta,f,sp.TS_dB,scaleSettings.ts,false); ytext = '频率 / kHz';
            case figureNames{6}
                plot(ax,theta,sp.bandMean_dB,'-','LineWidth',1.2);
            case figureNames{7}
                plot(ax,f,sp.recordMean_dB,'-','LineWidth',1.2); xtext = '频率 / kHz';
        end
        xlabel(ax,xtext); ylabel(ax,ytext);
        if any(strcmp(kind,combinedNames(4:5)))
            xlim(ax,[f(1) f(end)]);
        end
        if any(strcmp(kind,combinedNames([1 2 3 6 7]))) || any(strcmp(kind,figureNames([1 2 3 5 6])))
            bounds = result.angleLimits_deg;
            if repeated, bounds = theta([1 end]); end
            if isscalar(theta), set(findobj(ax,'Type','line'),'Marker','.'); end
            if bounds(1)==bounds(2)
                % 单个采集位置需要非零显示跨度。
                xlim(ax,bounds(1)+[-0.5 0.5]); xticks(ax,bounds(1));
            else
                limits = sort(bounds);
                xlim(ax,limits); xticks(ax,linspace(limits(1),limits(2),5));
                if repeated, xticks(ax,unique(round(linspace(limits(1),limits(2),5)))); end
                if bounds(1)>bounds(2), ax.XDir = 'reverse'; end
            end
        end
        if ~any(strcmp(kind,[figureNames([2 5]) combinedNames(6:7)])), grid(ax,'on'); end
    end
    function [coherent,incoherent] = combinedBandMean()
        % 只使用扫频网格；额外计算的当前单频点不参与平均。
        c = selectCombination(combined,result.spectrum.frequency_Hz);
        coherent = 10*log10(mean(10.^(c.coherent_dB/10),1));
        incoherent = 10*log10(mean(10.^(c.incoherent_dB/10),1));
    end
    function [coherent,incoherent] = combinedAcquisitionMean()
        c = selectCombination(combined,result.spectrum.frequency_Hz);
        coherent = 10*log10(acquisitionMeanPower(result.angle_deg,10.^(c.coherent_dB/10)));
        incoherent = 10*log10(acquisitionMeanPower(result.angle_deg,10.^(c.incoherent_dB/10)));
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
        widthCM = exportSize.Value; heightCM = widthCM*3/4;
        paper = figure('Visible','off','WindowStyle','normal','Color','w', ...
            'Units','centimeters','Position',[2 2 widthCM heightCM], ...
            'PaperUnits','centimeters','PaperSize',[widthCM heightCM], ...
            'PaperPosition',[0 0 widthCM heightCM],'NumberTitle','off','Name',kind);
        closePaper = onCleanup(@() close(paper));
        tiles = tiledlayout(paper,1,1,'Padding','tight','TileSpacing','tight');
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
        formatExportLayout(paper,tiles,ax,widthCM);
        drawnow;
        print(paper,[base '.png'],'-dpng','-r300');
        % 使保存的普通 MATLAB 图窗重新打开时可见、可编辑。
        paper.Visible = 'on';
        savefig(paper,[base '.fig']);
    end
    function exportBundle(varargin)
        if isempty(result), return; end
        hasSpectrum = isfield(result,'spectrum');
        exportNames = figureNames(1:2);
        if hasSpectrum, exportNames = figureNames; end
        captureDraggedScale();
        parent = uigetdir(project,'选择导出位置（将在其下新建结果文件夹）');
        if isequal(parent,0), return; end
        [~,id] = fileparts(folder);
        dest = fullfile(parent,[id '_' result.channel '_TS_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
        dlg = uiprogressdlg(fig,'Cancelable','on','CancelText','取消','Title','导出图表与数据','Message','准备导出');
        cleanup = onCleanup(@() close(dlg));
        try
            assert(~isfolder(dest),'结果目录已存在，请再次导出。');
            [ok,msg] = mkdir(dest); assert(ok,'%s',msg);
            checkCancel(dlg);
            saveResultsTo(fullfile(dest,'TS_results.mat'));
            if bistatic && hasSpectrum
                for j=1:numel(combinedNames)
                    checkCancel(dlg);
                    exportFigurePair(combinedNames{j},fullfile(dest,combinedNames{j}));
                end
                [coherent,incoherent] = combinedBandMean();
                t = positionTable(combined,1:numel(combined.pulse));
                t.CoherentBandMeanTS_dB = coherent(:); t.IncoherentBandMeanTS_dB = incoherent(:);
                writetable(t,fullfile(dest,'TS_combined_band_mean.csv'));
                [coherent,incoherent] = combinedAcquisitionMean();
                meanLabel = 'Angle'; meanFile = 'TS_combined_angle_mean.csv';
                if isempty(result.angle_deg), meanLabel = 'Pulse'; meanFile = 'TS_combined_pulse_mean.csv'; end
                writetable(table(result.spectrum.frequency_Hz(:),coherent(:),incoherent(:), ...
                    'VariableNames',{'Frequency_Hz',['Coherent' meanLabel 'MeanTS_dB'],['Incoherent' meanLabel 'MeanTS_dB']}), ...
                    fullfile(dest,meanFile));
            end
            if bistatic
                [hz,index] = ndgrid(combined.frequency_Hz,1:numel(combined.pulse));
                t = [table(hz(:),'VariableNames',{'Frequency_Hz'}) positionTable(combined,index(:))];
                t.CoherentTS_dB = combined.coherent_dB(:); t.IncoherentTS_dB = combined.incoherent_dB(:);
                writetable(t,fullfile(dest,'TS_combined.csv'));
            end
            originalResult = result;
            restore = onCleanup(@() restoreResult(originalResult));
            batch = {result}; if bistatic, batch = echoResults; end
            for w=1:numel(batch)
                result = batch{w}; targetDir = dest;
                if bistatic
                    targetDir = fullfile(dest,sprintf('回波_%02d',w)); mkdir(targetDir);
                end
                writeTables(targetDir,result);
                for j = 1:numel(exportNames)
                    base = fullfile(targetDir,sprintf('%02d_%s',j-1,exportNames{j}));
                    checkCancel(dlg);
                    exportFigurePair(exportNames{j},base);
                    dlg.Value = ((w-1)*numel(exportNames)+j)/(numel(exportNames)*numel(batch));
                end
            end
            status.Text = ['已导出至 ' dest];
        catch err
            if strcmp(err.identifier,'cornerTS:Cancelled'), status.Text = ['已停止导出，已写入的文件在 ' dest]; return; end
            uialert(fig,sprintf('导出未完成。目录：%s\n%s',dest,err.message),'导出失败');
        end
    end
    function restoreResult(saved)
        result = saved;
    end
    function saveResultsTo(path)
        if bistatic
            for w=1:numel(echoResults), echoResults{w}.colorScale = scaleSettings; end
            save(path,'result','echoResults','combined');
        else
            save(path,'result');
        end
    end
    function saveResult(varargin)
        if isempty(result), return; end
        captureDraggedScale();
        [~,id] = fileparts(folder);
        [name,path] = uiputfile('*.mat','保存当前参数与 TS 结果',[id '_' result.channel '_TS.mat']);
        if isequal(name,0), return; end
        try
            saveResultsTo(fullfile(path,name)); status.Text = ['已保存 ' name];
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
        suffix = ''; if bistatic && source==curve && ~any(strcmp(kind,combinedNames)), suffix = sprintf('_回波%d',result.echoIndex); end
        [name,path] = uiputfile('*.png','保存同名 PNG 和 FIG',[id '_' activeChannel '_' kind suffix '.png']);
        if isequal(name,0), return; end
        try
            [~,stem] = fileparts(name);
            if isfile(fullfile(path,[stem '.fig']))
                choice = uiconfirm(fig,['替换已有的可编辑图 ' stem '.fig？'], ...
                    '导出结果图','Options',{'替换','取消'},'DefaultOption',2,'CancelOption',2);
                if ~strcmp(choice,'替换'), return; end
            end
            dlg = uiprogressdlg(fig,'Title','导出当前图', ...
                'Message','正在调整排版并保存 PNG 和 FIG，请稍候…','Indeterminate','on');
            cleanup = onCleanup(@() close(dlg));
            drawnow;
            exportFigurePair(kind,fullfile(path,stem),source);
            status.Text = ['已保存 ' stem '.png 和同名 FIG'];
        catch err
            clear cleanup
            uialert(fig,err.message,'导出失败');
        end
    end
end

function imported = readLTTFolder(selected,channel,dlg)
% 一个工况一次导入；不递归扫描多个工况，CSV 电压不再应用 TXT 的原始码缩放。
files = dir(fullfile(selected,'*.csv'));
if isempty(files)
    child = fullfile(selected,'00000');
    files = dir(fullfile(child,'*.csv'));
    assert(~isempty(files),'%s：没有 CSV。请选择一个 LTT 工况或其 00000 子目录，不要选择多个工况的上级目录。',selected);
    selected = child;
end
tokens = regexp({files.name},'^(.*)_M(\d+)\.csv$','tokens','once','ignorecase');
bad = find(cellfun(@isempty,tokens),1);
assert(isempty(bad),'%s：文件名须以 _M采集序号.csv 结尾。',filesName(files,bad));
prefixes = cellfun(@(t)t{1},tokens,'UniformOutput',false);
assert(isscalar(unique(prefixes)),'%s：检测到不同采集文件前缀，请将不同工况或批次分开。',selected);
indices = cellfun(@(t)str2double(t{2}),tokens);
assert(all(isfinite(indices)) && numel(unique(indices))==numel(indices), ...
    '%s：M 采集序号无效或重复。',selected);
[indices,order] = sort(indices); files = files(order);
count = numel(files); missingMetadata = 0;
for k=1:count
    checkCancel(dlg);
    path = fullfile(selected,files(k).name);
    try
        [times,channels,volts,rate] = readLTTRecord(path);
        if k==1
            baseline = times; channelNames = channels; sampleRate = rate;
            if isempty(channel), channel = channels{1}; end
            channelIndex = find(strcmp(channels,channel),1);
            assert(~isempty(channelIndex),'找不到所选通道 %s。',channel);
            values = zeros(numel(times),count);
        else
            assert(isequal(channels,channelNames),'电压通道名称或排列顺序与首个文件不一致。');
            assert(numel(times)==numel(baseline),'采样点数与首个文件不一致（%d / %d）。',numel(times),numel(baseline));
            tolerance = max(1e-12,1/sampleRate*1e-5);
            assert(all(abs(times-baseline)<=tolerance),'时间轴与首个文件不一致（含起点和采样间隔）。');
        end
        hasMetadata = checkLTTMetadata(path,rate,numel(times),numel(channels));
        missingMetadata = missingMetadata+~hasMetadata;
        values(:,k) = volts(:,channelIndex);
    catch err
        error('cornerTS:LTTRecord','%s：%s',files(k).name,err.message);
    end
    dlg.Value = k/count;
    dlg.Message = sprintf('LTT · %d / %d 次采集 · %s',k,count,channel);
end
checkCancel(dlg);
imported = struct('values',values,'fs',sampleRate,'timeSeconds',baseline, ...
    'folder',selected,'channel',channel,'channels',{channelNames}, ...
    'recordNumbers',indices,'recordFiles',{{files.name}},'missingMetadata',missingMetadata);
end

function name = filesName(files,index)
name = ''; if ~isempty(index), name = files(index).name; end
end

function [times,channels,volts,rate] = readLTTRecord(path)
fid = fopen(path,'rt'); assert(fid>=0,'无法打开文件。');
cleanup = onCleanup(@() fclose(fid));
header = fgetl(fid); assert(ischar(header),'CSV 为空。');
header = erase(header,char(65279));
headers = strtrim(strsplit(header,';'));
headers = cellfun(@(s)strtrim(erase(s,'"')),headers,'UniformOutput',false);
timeIndex = find(strcmpi(headers,'Time [s]'));
assert(isscalar(timeIndex),'表头须有且仅有一列 Time [s]。');
voltageTokens = regexp(headers,'^(.+?)\s*\[V\]$','tokens','once');
voltageIndex = find(~cellfun(@isempty,voltageTokens));
assert(~isempty(voltageIndex),'表头未找到单位为 [V] 的电压通道。');
channels = cellfun(@(t)strtrim(t{1}),voltageTokens(voltageIndex),'UniformOutput',false);
assert(numel(unique(channels))==numel(channels),'电压通道名重复。');
data = readmatrix(path,'Delimiter',';','NumHeaderLines',1,'FileType','text');
assert(size(data,2)==numel(headers) && size(data,1)>=2,'CSV 数据列数与表头不符或不足两个采样点。');
times = data(:,timeIndex); volts = data(:,voltageIndex);
assert(all(isfinite(times)) && all(isfinite(volts(:))),'时间或电压存在缺失/非有限值。');
intervals = diff(times);
assert(all(intervals>0),'时间列必须严格递增。');
dt = mean(intervals);
assert(all(abs(intervals-dt)<=max(1e-12,dt*1e-5)),'时间列不是等间隔采样。');
rate = 1/dt;
assert(isfinite(rate) && rate>0,'时间列无法确定有效采样率。');
end

function available = checkLTTMetadata(csvPath,rate,samples,channels)
[parent,name] = fileparts(csvPath); path = fullfile(parent,[name '.txt']);
available = isfile(path);
if ~available, return; end
metadata = fileread(path);
number = '([0-9]+(?:\.[0-9]*)?(?:[eE][+-]?\d+)?)';
token = regexpi(metadata,['Timebase:\s*' number '\s*(GHz|MHz|kHz|Hz)'],'tokens','once');
if ~isempty(token)
    units = {'hz','khz','mhz','ghz'};
    multiplier = 1000^(find(strcmpi(token{2},units),1)-1);
    value = str2double(token{1})*multiplier;
    % Timebase 的频率文本可能只保留两位小数，容许其末位舍入误差。
    mantissa = regexp(token{1},'^\d+(?:\.(\d*))?','tokens','once');
    decimals = 0; if ~isempty(mantissa) && ~isempty(mantissa{1}), decimals = numel(mantissa{1}); end
    exponent = regexp(token{1},'[eE]([+-]?\d+)','tokens','once');
    power = 0; if ~isempty(exponent), power = str2double(exponent{1}); end
    tolerance = .5*10^(power-decimals)*multiplier+rate*1e-8;
    assert(abs(rate-value)<=tolerance,'TXT Timebase 频率与 CSV 不一致（TXT %g Hz，CSV %g Hz）。',value,rate);
end
period = regexpi(metadata,['Timebase:[^\r\n]*\(\s*' number '\s*(ns|us|µs|μs|ms|s)\s*\)'],'tokens','once');
if ~isempty(period)
    switch lower(period{2})
        case 'ns', factor=1e-9;
        case {'us','µs','μs'}, factor=1e-6;
        case 'ms', factor=1e-3;
        otherwise, factor=1;
    end
    dt = str2double(period{1})*factor;
    assert(abs(dt-1/rate)<=max(1e-12,dt*1e-5),'TXT Timebase 采样间隔与 CSV 不一致。');
end
token = regexpi(metadata,'Sequences:\s*(\d+)(?:\s*\[\s*(\d+)\s+channels?\s+each\])?','tokens','once');
if ~isempty(token)
    assert(str2double(token{1})==samples,'TXT Sequences 与 CSV 点数不一致（TXT %s，CSV %d）。',token{1},samples);
    if numel(token)>1 && ~isempty(token{2})
        assert(str2double(token{2})==channels,'TXT 通道数与 CSV 电压通道数不一致。');
    end
end
end

function checkCancel(dlg)
% 允许进度框响应点击，在提交结果之前退出并释放本次局部数组。
drawnow limitrate
if dlg.CancelRequested, error('cornerTS:Cancelled','已取消。'); end
end

function c = combineEchoWindows(signal,d,ref,windows,pulses,fs,f,L,r,dlg)
% 各窗沿原采样时间轴投影到相同频点；统一用同一参考频谱和传播修正。
f = f(:); phase = -2i*pi*f/fs;
reference = exp(phase*(d-1))*signal(d,ref);
tolerance = max(realmin,16*eps(sum(abs(signal(d,ref)))));
assert(all(isfinite(reference) & abs(reference)>tolerance),'直达波参考频谱在所选频点接近零，无法归一化。');
total = complex(zeros(numel(f),numel(pulses))); power = zeros(size(total));
for w=1:numel(windows)
    checkCancel(dlg);
    idx = windows{w};
    component = (exp(phase*(idx-1))*signal(idx,pulses))./reference*(r*L/(L-r));
    total = total+component;
    power = power+abs(component).^2;
end
c = struct('frequency_Hz',f,'coherent_dB',20*log10(abs(total)),'incoherent_dB',10*log10(power));
end

function c = selectCombination(c,frequencies)
[found,rows] = ismember(frequencies,c.frequency_Hz);
assert(all(found),'合成结果缺少相应频点。');
c.frequency_Hz = frequencies(:);
c.coherent_dB = c.coherent_dB(rows,:); c.incoherent_dB = c.incoherent_dB(rows,:);
end

function formatExportLayout(paper,tiles,ax,widthCM)
% 布局按最终字号为轴标签、图例和色条分配空间，整个画布保持固定尺寸。
tiles.Padding = 'tight'; tiles.TileSpacing = 'tight';
fontPt = 8;
if widthCM==16, fontPt = 11; end
ax.FontUnits = 'points'; ax.FontSize = fontPt;
ax.LabelFontSizeMultiplier = 1; ax.TitleFontSizeMultiplier = 1;
for cb = reshape(findall(paper,'Type','colorbar'),1,[])
    cb.FontSize = fontPt;
end
for label = reshape(findall(paper,'Type','text'),1,[])
    label.FontUnits = 'points'; label.FontSize = fontPt;
end
lg = ax.Legend;
if ~isempty(lg)
    lg.FontUnits = 'points'; lg.FontSize = fontPt;
    lg.Box = 'off'; lg.ItemTokenSize(1) = 1.5*fontPt;
    lg.Location = 'southoutside'; lg.Units = 'centimeters';
    % 测量排版后的图例，选择能放入画布的最大列数。
    for cols = numel(lg.String):-1:1
        lg.NumColumns = cols;
        drawnow;
        if lg.Position(3)<=widthCM-0.1, break; end
    end
    lg.Layout.Tile = 'south';
end
% 在固定纸面上测量刻度、标签、图例和色条的实际外缘，再扩大内部布局。
% 保留约 0.5 mm 的安全边，防止字符贴边或截断。
tiles.Units = 'normalized';
for pass = 1:3
    drawnow;
    raster = print(paper,'-RGBImage','-r300');
    ink = min(raster,[],3)<225;
    x = find(any(ink,1)); y = find(any(ink,2));
    if isempty(x) || isempty(y), break; end
    h = size(ink,1); w = size(ink,2);
    margins = [x(1)-1 h-y(end) w-x(end) y(1)-1];
    delta = (margins-6)./[w h w h];
    if max(abs(margins-6))<=3, break; end
    pos = tiles.OuterPosition;
    tiles.OuterPosition = pos + [-delta(1:2),delta(1)+delta(3),delta(2)+delta(4)];
end
end

function filtered = pulseHighpass(block,fc,dlg)
% 沿每行的脉冲序列作偶对称延拓，再施加二阶巴特沃斯形状的零相位幅频响应。
n = size(block,2);
bins = 0:2*n-1;
f = min(bins,2*n-bins)/(2*n); % 周期/脉冲，正负频率取相同增益
gain = zeros(size(f));
gain(2:end) = 1./sqrt(1+(fc./f(2:end)).^4);
filtered = zeros(size(block),'like',block);
for startRow = 1:64:size(block,1)
    dlg.Value = (startRow-1)/size(block,1); checkCancel(dlg);
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
    direct(k,:) = amplitudes(d,kernel,dlg);
    echo(k,:) = amplitudes(e,kernel,dlg);
    dlg.Value = k/count;
    dlg.Message = sprintf('%.2f kHz · %d / %d · %.0f%%',frequencies(k)/1000,k,count,100*k/count);
    checkCancel(dlg);
end
end

function p = amplitudes(signals,kernel,dlg)
n = size(signals,1)+numel(kernel)-1;
weight = zeros(n,1); weight(1) = 1;
weight(2:floor((n+1)/2)) = 2;
if mod(n,2)==0, weight(n/2+1) = 1; end
filterFFT = fft(kernel,n).*weight;
center = round(n/2)+(-100:100);
p = zeros(1,size(signals,2));
for first = 1:32:size(signals,2)
    checkCancel(dlg);
    cols = first:min(first+31,size(signals,2));
    z = ifft(fft(signals(:,cols),n,1).*filterFFT,[],1);
    p(cols) = mean(abs(z(center,:)),1);
end
end

function average = acquisitionMeanPower(theta,power)
if isempty(theta)
    average = mean(power,2); % 固定方位独立重复采集，每列等权。
elseif isscalar(theta)
    average = power;
else
    average = trapz(theta,power,2)/(theta(end)-theta(1));
end
end

function sp = summarizeSpectrum(theta,pulses,f,ratio)
power = ratio.^2;
acrossFrequency = mean(power,1);
acrossAcquisitions = acquisitionMeanPower(theta,power);
sp = struct('frequency_Hz',f,'TS_dB',20*log10(ratio), ...
    'bandMean_dB',10*log10(acrossFrequency),'recordMean_dB',10*log10(acrossAcquisitions), ...
    'mean_dB',10*log10(mean(acrossAcquisitions)));
[sp.max_dB,imax] = max(sp.bandMean_dB);
[sp.min_dB,imin] = min(sp.bandMean_dB);
if isempty(theta)
    sp.maxPulse = pulses(imax); sp.minPulse = pulses(imin);
    sp.pulseMean_dB = sp.recordMean_dB;
else
    sp.maxAngle_deg = theta(imax); sp.minAngle_deg = theta(imin);
    sp.angleMean_dB = sp.recordMean_dB;
end
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

function t = positionTable(res,idx)
p = res.pulse(idx); t = table(p(:),'VariableNames',{'Pulse'});
if ~isempty(res.angle_deg)
    a = res.angle_deg(idx); t.Angle_deg = a(:);
end
end

function writeTables(dest,res)
if isempty(res.angle_deg)
    t = positionTable(res,1:numel(res.pulse));
    t.Frequency_Hz = repmat(res.frequency_Hz,height(t),1);
    t.SingleFrequencyTS_dB = res.TS_dB(:);
    if isfield(res,'spectrum')
        sp = res.spectrum;
        t.BandEnergyMeanTS_dB = sp.bandMean_dB(:);
        writetable(table(sp.frequency_Hz(:),sp.pulseMean_dB(:), ...
            'VariableNames',{'Frequency_Hz','PulseEnergyMeanTS_dB'}),fullfile(dest,'TS_by_frequency.csv'));
        [hz,k] = ndgrid(sp.frequency_Hz,1:numel(res.pulse));
        spectrum = positionTable(res,k(:)); spectrum.Frequency_Hz = hz(:); spectrum.TS_dB = sp.TS_dB(:);
        writetable(spectrum,fullfile(dest,'TS_spectrum.csv'));
        summary = table(sp.frequency_Hz(1),sp.frequency_Hz(end),sp.mean_dB,sp.max_dB,sp.maxPulse,sp.min_dB,sp.minPulse,sp.peakToPeak_dB, ...
            'VariableNames',{'BandStart_Hz','BandEnd_Hz','Mean_dB','Max_dB','MaxPulse','Min_dB','MinPulse','PeakToPeak_dB'});
    else
        summary = table(res.frequency_Hz,res.energyMean_dB,res.peakToPeak_dB, ...
            'VariableNames',{'Frequency_Hz','PulseEnergyMeanTS_dB','PeakToPeak_dB'});
    end
    writetable(t,fullfile(dest,'TS_by_pulse.csv'));
    writetable(summary,fullfile(dest,'TS_statistics.csv'));
    return
end
if ~isfield(res,'spectrum')
    hz = repmat(res.frequency_Hz,numel(res.pulse),1);
    writetable(table(hz,res.pulse(:),res.angle_deg(:),res.TS_dB(:), ...
        'VariableNames',{'Frequency_Hz','Pulse','Angle_deg','SingleFrequencyTS_dB'}), ...
        fullfile(dest,'TS_by_angle.csv'));
    writetable(table(res.frequency_Hz,res.energyMean_dB,res.peakToPeak_dB, ...
        'VariableNames',{'Frequency_Hz','AngleEnergyMeanTS_dB','PeakToPeak_dB'}), ...
        fullfile(dest,'TS_statistics.csv'));
    return
end
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


