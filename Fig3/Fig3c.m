% =========================================================================
% FIGURE 3C: PRE-ICTAL, ICTAL, AND POST-ICTAL SINGLE-CHANNEL RAW EEG TRACE
% =========================================================================
% Configured to show only the raw EEG signal for a specific time window.

%% ---1. Initial Setup ---
%clear; clc;

% EEG Data Parameters
eeg_recording_start_datetime_str = '2023-10-03 15:30:00'; 
eeg_parquet_file_path = 'Resaved-biov-2023-10-03T15_30_00-05_00-2023-10-04T12_00_00-05_00-EEGSY08.parquet';  
eeg_signal_column_name = 'val'; 
Fs_eeg = 256; 

% Define plotting window
plot_window_start_datetime_str = '2023-10-04 06:50:00'; 
plot_window_end_datetime_str   = '2023-10-04 07:05:00';   

% Microvolt conversion parameters
bitres = 17; 
gain = 160;  

% Define Y-axis limit
raw_eeg_ylim = [-1500, 1500]; 

% Plotting parameters
figure_position = [100, 100, 1000, 400];
plot_font_name = 'Arial';
axis_font_size = 10;
label_font_size = 11;
axis_line_width = 0.75;
data_line_width = 1.0;

%% Load EEG Data
fprintf('Loading EEG data...\n');
try
    tbl_eeg_parquet = parquetread(eeg_parquet_file_path);
    raw_eeg_signal = tbl_eeg_parquet.(eeg_signal_column_name);
catch ME
    error('File load failed: %s', ME.message);
end

% Ensure column vector
if isrow(raw_eeg_signal); raw_eeg_signal = raw_eeg_signal'; end

%% Time Alignment and Plotting Window Implementation
eeg_file_start_dt = datetime(eeg_recording_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
effective_plot_start_dt = datetime(plot_window_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
effective_plot_end_dt = datetime(plot_window_end_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');

offset_start = seconds(effective_plot_start_dt - eeg_file_start_dt);
offset_end   = seconds(effective_plot_end_dt - eeg_file_start_dt);

idx_start = round(offset_start * Fs_eeg) + 1;
idx_end   = round(offset_end * Fs_eeg) + 1;

% Crop and convert to microvolts
raw_eeg_cropped = raw_eeg_signal(idx_start:idx_end);
val_uv = double(raw_eeg_cropped) * 1e6 / (2^bitres * gain);

% Create Time Vector
time_vec = effective_plot_start_dt + seconds((0:(length(val_uv)-1))' / Fs_eeg);
time_vec.TimeZone = 'local';

%% Plotting
fprintf('Generating Trace...\n');
fig_handle = figure('Color','w', 'Position', figure_position);
eeg_ax = axes('NextPlot', 'add');

plot(eeg_ax, time_vec, val_uv, 'Color', 'k', 'LineWidth', data_line_width);

% Set Labels and Limits
ylabel(eeg_ax, 'EEG (\muV)', 'FontName', plot_font_name, 'FontSize', label_font_size);
xlabel(eeg_ax, 'Time (Local)', 'FontName', plot_font_name, 'FontSize', label_font_size);
ylim(eeg_ax, raw_eeg_ylim);
xlim(eeg_ax, [effective_plot_start_dt, effective_plot_end_dt]);

% Formatting
set(eeg_ax, 'FontName', plot_font_name, 'FontSize', axis_font_size, ...
    'TickDir', 'out', 'LineWidth', axis_line_width, 'Box', 'off');

% Format X-axis to show Time
datetick(eeg_ax, 'x', 'HH:MM:SS', 'keeplimits');

fprintf('Plot generation complete.\n');