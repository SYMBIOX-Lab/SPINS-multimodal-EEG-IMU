% =========================================================================
% FIGURE 3D: PRE-ICTAL, ICTAL, AND POST-ICTAL SINGLE-CHANNEL RAW EEG TRACE
% EVENT 2 - Cz-Pz
% =========================================================================
% clear;
% clc;

% Input EDF file
edf_filename = 'SABRE0025_20231024_000136_20231024_120136_CzPz.edf';

% Define target timezone
target_tz = 'America/Chicago';

% Define the four 5-second phases for plotting
% These are the same absolute times as the wearable sensor plot
phases = {
    datetime('2023-10-24 10:04:10', 'TimeZone', target_tz), datetime('2023-10-24 10:04:15', 'TimeZone', target_tz);
    datetime('2023-10-24 10:30:54', 'TimeZone', target_tz), datetime('2023-10-24 10:30:59', 'TimeZone', target_tz);
    datetime('2023-10-24 10:31:42', 'TimeZone', target_tz), datetime('2023-10-24 10:31:47', 'TimeZone', target_tz);
    datetime('2023-10-24 10:36:45', 'TimeZone', target_tz), datetime('2023-10-24 10:36:50', 'TimeZone', target_tz);
};
% Plotting parameters
eeg_line_color = '#800000'; % Maroon red color
eeg_line_width = 1.2;
font_name = 'Helvetica';
font_size = 10;
axis_line_width = 1.2;

% Load Data
fprintf('Reading EDF file: %s...\n', edf_filename);
try
    info = edfinfo(edf_filename);
    edf_table = edfread(edf_filename);
catch ME
    error('Failed to read the EDF file. Error: %s', ME.message);
end

fprintf('EDF data loaded successfully.\n\n');

% Programmatically determine headers from the EDF file
fprintf('--- Determining parameters from file ---\n');

% 1. Get channel name and sampling rate
var_names = edf_table.Properties.VariableNames;
channel_to_plot = var_names{1};
first_cell = edf_table.(channel_to_plot){1};
record_duration_sec = seconds(info.DataRecordDuration(1));
sampling_rate = size(first_cell, 1) / record_duration_sec;
fprintf('Found data channel: ''%s''\n', channel_to_plot);
fprintf('Calculated sampling rate: %d Hz\n', sampling_rate);

% 2. Manually build the start time from its numeric parts
date_str = info.StartDate;
time_str = info.StartTime;
date_parts = split(date_str, '.');
time_parts = split(time_str, '.');
day = str2double(date_parts{1});
month = str2double(date_parts{2});
year = 2000 + str2double(date_parts{3});
hour = str2double(time_parts{1});
minute = str2double(time_parts{2});
sec = str2double(time_parts{3});
file_start_time = datetime(year, month, day, hour, minute, sec, 'TimeZone', target_tz);
fprintf('Parsed file start time: %s\n\n', char(file_start_time));

% Create absolute time vector for entire signal
fprintf('--- Creating absolute time vector ---\n');

% Unpack data from cells
data_cells = edf_table.(channel_to_plot);
continuous_data = vertcat(data_cells{:});

% Create a relative time vector, then convert to absolute
num_samples = length(continuous_data);
relative_time_sec = (0:num_samples-1)' / sampling_rate;
absolute_time_vector = file_start_time + seconds(relative_time_sec);
fprintf('Time vector created successfully.\n\n');

% Generate a four panel plot
fprintf('--- Generating four-phase plot ---\n');
figure('Color', 'w', 'Position', [50, 400, 1200, 350]);
tl = tiledlayout(1, 4, 'TileSpacing', 'none', 'Padding', 'compact');
axes_handles = gobjects(4, 1);

% Loop through each of the four phases
for i = 1:length(phases)
    plot_start_time = phases{i, 1};
    plot_end_time = phases{i, 2};
    
    start_idx = find(absolute_time_vector >= plot_start_time, 1, 'first');
    end_idx   = find(absolute_time_vector <= plot_end_time, 1, 'last');
    
    ax = nexttile;
    axes_handles(i) = ax;
    
    if isempty(start_idx) || isempty(end_idx)
        warning('No data found for phase %d.', i);
        set(ax, 'visible', 'off');
        continue;
    end
    
    data_segment = continuous_data(start_idx:end_idx);
    plot_time_vector = absolute_time_vector(start_idx:end_idx);
    
    plot(ax, plot_time_vector, data_segment, 'Color', eeg_line_color, 'LineWidth', eeg_line_width);
    
    set(ax, 'Box', 'off', 'FontName', font_name, 'FontSize', font_size, 'TickDir', 'in', 'LineWidth', axis_line_width);
    grid(ax, 'off');
    
    % Remove X-axis labels (the numbers/times below the axis)
    set(ax, 'XTickLabel', []);
    
    if i > 1
        set(ax, 'YTickLabel', []);
        ax.YAxis.Visible = 'off';
    end
end

% Apply final formatting to entire layout

linkaxes(axes_handles, 'y');
ylim(axes_handles(1), [-100, 100]); 
ylabel(tl, 'Amplitude (\muV)'); 
fprintf('Plot generation complete.\n');