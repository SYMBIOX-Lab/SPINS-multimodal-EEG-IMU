% =========================================================================
% FIGURE 1F: VISUALIZING AN EEG SLEEP SPINDLE
% =========================================================================
%clear; clc; close all;

%% 1. Configuration & Setup
% Import parquet file
eegFilename    = 'Resaved-tk_micz-2024-07-29T10_55_00-05_00-2024-07-30T10_55_00-05_00-EEG0630.parquet'; 

% Import channel within the parquet file
eegChannelName = 'z'; 

% Time Window (6 seconds) in America/Chicago Timezone
% Note: 06:29:01 UTC is 01:29:01 CDT
timeWindowStart = datetime('2024-07-30 01:29:01', 'TimeZone', 'America/Chicago');
timeWindowEnd   = datetime('2024-07-30 01:29:07', 'TimeZone', 'America/Chicago');

% --- Microvolt Conversion Parameters ---
bitres = 17; 
gain = 160;  

if ~isfile(eegFilename)
    error('Data file not found: %s', eegFilename);
end

%% 2. Load and Convert EEG Data
fprintf('Reading and converting EEG data...\n');
try
    eegTbl = parquetread(eegFilename);
    eegTimeStamps = eegTbl{:,1};
    
    if ~isdatetime(eegTimeStamps)
       eegTimeStamps = datetime(eegTimeStamps, 'ConvertFrom', 'posixtime');
    end
    
    % Set data to UTC first, then convert to Chicago time
    eegTimeStamps.TimeZone = 'UTC';
    eegTimeStamps = datetime(eegTimeStamps, 'TimeZone', 'America/Chicago');

    % Apply Microvolt Conversion
    eegSignal = (double(eegTbl.(eegChannelName)) * 1e6) / (2^bitres * gain);
    
    fprintf('Data converted to Chicago time and microvolts successfully.\n');
catch ME
    error('Failed to process file. Error: %s', ME.message);
end

%% 3. Generate and Save Plot
fprintf('Generating plot...\n');
fig = figure('Color', 'w');
ax = gca;

% Find indices within the time window
eeg_indices = find(eegTimeStamps >= timeWindowStart & eegTimeStamps <= timeWindowEnd);

if ~isempty(eeg_indices)
    plot(ax, eegTimeStamps(eeg_indices), eegSignal(eeg_indices), ...
        'Color', [0 0.4470 0.7410], 'LineWidth', 1);
    
    % Axis Limits and Formatting
    xlim(ax, [timeWindowStart, timeWindowEnd]);
    ylim(ax, [-20, 20]); 
    
    grid(ax, 'on');
    ax.XMinorGrid = 'on';
    ax.XTick = timeWindowStart:seconds(1):timeWindowEnd;
    xtickformat('HH:mm:ss'); % Simplified for readability
    xtickangle(45);
    
    title(sprintf('EEG Signal - %s Channel (Chicago Time)', eegChannelName), 'FontWeight', 'bold');
    xlabel('Time (Central)');
    ylabel('Amplitude (\muV)');
    box on;
else
    text(0.5, 0.5, 'No EEG data found in this time range.', 'HorizontalAlignment', 'center');
end

% Save the plot
outputFilename = 'eeg_spindle.png';
saveas(fig, outputFilename);
fprintf('Done. Plot saved as %s.\n', outputFilename);