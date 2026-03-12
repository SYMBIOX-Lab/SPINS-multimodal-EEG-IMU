% =========================================================================
% FIGURE 4C: CLINICAL EEG
% =========================================================================
% clear, close all, clc;
%% Import EDF file 
fileName = 'SABRE0071_20240710_000027_20240711_000027.edf';

% List of channels to plot (top to bottom, to match clinical standard)
channelsToPlot = {
    'EEG Fp1-Ref', ... % Top
    'EEG Fp2-Ref', ...
    'EEG Cz-Ref', ...
    'EEG Pz-Ref', ...
    'EEG O1-Ref', ...
    'EEG O2-Ref'        % Bottom
};

% Colors for all channels (all black)
plotColors = {
    'k', ...   % Fp1
    'k', ...   % Fp2
    'k', ...   % Cz
    'k', ...   % Pz
    'k', ...   % O1
    'k'        % O2
};

% Define time window (can be adjusted as needed)
windowDateStr = '2024-07-10'; 
windowStartStr = '07:47:30';
windowEndStr   = '07:50:30';

% Define timezone
tz = 'America/Chicago'; 

if ~isfile(fileName)
    error('File not found. Please check the path and "fileName" variable.');
end
try
    info = edfinfo(fileName);
    fprintf('File found and header read successfully.\n');
catch ME
    error('File exists, but could not read EDF header. File may be corrupt. Error: %s', ME.message);
end

% Extract sampling rate
[~, channelIndices] = ismember(channelsToPlot, info.SignalLabels);
if any(channelIndices == 0)
    error('Could not find all channels in the file header. Check "channelsToPlot".');
end

recordDuration = seconds(info.DataRecordDuration);
samplesPerRecord = info.NumSamples(channelIndices);
fs_array = samplesPerRecord / recordDuration;

if ~all(fs_array == fs_array(1))
    error('The selected channels have different sample rates, which this script does not support.');
end

fs = fs_array(1); 
fprintf('Detected correct sample rate: %g Hz\n', fs);

%% Calculate time windows
fprintf('Parsing recording start time from filename...\n');
try
    nameParts = split(fileName, '_');
    dateStr = nameParts{2};
    timeStr = nameParts{3};
    startTimeStr = [dateStr, timeStr];
    
    recordingStartTime = datetime(startTimeStr, ...
        'InputFormat', 'yyyyMMddHHmmss', ...
        'TimeZone', tz);
    fprintf('Detected recording start time: %s\n', string(recordingStartTime));
catch
    error('Could not parse the start time from the filename.');
end

windowStart = datetime([windowDateStr ' ' windowStartStr], 'TimeZone', tz);
windowEnd   = datetime([windowDateStr ' ' windowEndStr], 'TimeZone', tz);

%% Read Data (compatible method)
fprintf('Reading data from: %s\n', fileName);
fprintf('Loading only required channels (this may take a moment)...\n');
try
    edfTimetable = edfread(fileName, ...
        'SelectedSignals', channelsToPlot);
    
    sanitizedChannelNames = edfTimetable.Properties.VariableNames;
    
    fprintf('Data loaded.\n');
catch ME
    fprintf('\n--- ERROR ---"\nFailed to read EDF file. Check that channels exist.\n');
    fprintf('Your "channelsToPlot" list:\n');
    disp(channelsToPlot');
    fprintf('\nChannels available in the file:\n');
    disp(info.SignalLabels');
    fprintf('Error: %s\n', ME.message);
    rethrow(ME);
end

%% Prepare data for plotting
if iscell(edfTimetable.(sanitizedChannelNames{1}))
    fprintf('Data is in cell format. Converting to numeric...\n');
    tempData = [];
    for i = 1:numel(sanitizedChannelNames)
        channelName = sanitizedChannelNames{i}; 
        concatenatedColumn = vertcat(edfTimetable.(channelName){:});
        tempData(:, i) = concatenatedColumn;
    end
    
    numSamples = size(tempData, 1);
    timeVector = seconds((0:numSamples-1)' / fs);
    
    cleanTimetable = array2timetable(tempData, 'RowTimes', timeVector, 'VariableNames', sanitizedChannelNames);
    fprintf('Conversion complete.\n');
else
    cleanTimetable = edfTimetable;
end

cleanTimetable.Time = recordingStartTime + cleanTimetable.Time;

fprintf('Selecting time window from %s to %s...\n', string(windowStart), string(windowEnd));
timeRange = cleanTimetable.Time >= windowStart & ...
            cleanTimetable.Time <= windowEnd;
finalData = cleanTimetable(timeRange, :);

if isempty(finalData)
    error('The specified time window is empty or outside the recording range.');
end

%% Manual Plotting
fprintf('Generating custom plot...\n');
figure('Name', 'Custom EEG Plot', 'Color', 'w');
hold on; 

verticalOffset = max(range(finalData{:,:}), [], 'all') * 1.5;
if verticalOffset == 0; verticalOffset = 1; end 

% Draw horizontal grid lines for each channel 
gridColor = [0.8 0.8 0.8]; % Light gray
for i = 1:numel(sanitizedChannelNames)
    plotOffset = (numel(sanitizedChannelNames) - i) * verticalOffset;
    line([windowStart, windowEnd], [plotOffset, plotOffset], ...
         'Color', gridColor, 'LineStyle', '--');
end

% Plot from top to bottom (this now plots *over* the gridlines)
for i = 1:numel(sanitizedChannelNames)
    sanitizedName = sanitizedChannelNames{i};
    originalLabel = channelsToPlot{i}; 
    plotColor = plotColors{i}; % Get the color (will be 'k')
    
    plotOffset = (numel(sanitizedChannelNames) - i) * verticalOffset;
    
    plot(finalData.Time, finalData{:, sanitizedName} + plotOffset, ...
        'Color', plotColor); 
    
    text(windowStart, plotOffset, [originalLabel '  '], ...
        'HorizontalAlignment', 'right', 'FontSize', 10, 'FontWeight', 'bold');
end

%% Customize Final Plot Appearance
set(gca, 'YColor', 'none'); 
set(gca, 'XColor', 'k');

ax = gca; 
ax.XGrid = 'on'; 
ax.YGrid = 'off'; 
ax.GridColor = [0.8 0.8 0.8]; 
ax.GridAlpha = 0.5;

% Set X-ticks to every 1 second
% Round start time up to the nearest 1-second mark
firstTick = windowStart;
firstTick.Second = ceil(firstTick.Second);

% Create the vector of tick times, one for every second
tickVector = firstTick:seconds(1):windowEnd;

ax.XTick = tickVector; 
ax.XAxis.TickLabelFormat = 'HH:mm:ss'; 

xlim([windowStart, windowEnd]);
box on;   
hold off; 
xlabel('Time (HH:mm:ss)');
title(sprintf('EEG Data from %s to %s', string(windowStart), string(windowEnd)));

fprintf('Plot generation complete.\n');