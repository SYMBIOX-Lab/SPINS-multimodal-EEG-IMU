% =========================================================================
% FIGURE 4F: PSYCHOGENIC NON-EPILEPTIC SEIZURE (PNES)
% =========================================================================
% clear, close all, clc;

% Note: Please adjust the y axis limit accordingly for the plot. Can zoom
% in on interactive plot, or can adjust limits in this code. See Y-Axis
% Limits section.


%% Parameters
% EEG Data Parameters
target_timezone = 'America/Chicago'; 
eeg_recording_start_datetime_str = '2024-07-09 10:25:00'; 
eeg_parquet_file_path = 'Resaved-tk_micz-2024-07-09T10_25_00-05_00-2024-07-10T10_25_00-05_00-EEG0630.parquet'; 
eeg_signal_column_name = 'z'; 
Fs_eeg = 256; 

% IMU Data Parameters
imu_parquet_file_path = 'Resaved-tk_xyz_secondary-2024-07-09T10_25_00-05_00-2024-07-10T10_25_00-05_00-EEG0630.parquet'; 
imu_timestamp_column_name = 't';
imu_x_col_name = 'x'; 
imu_y_col_name = 'y'; 
imu_z_col_name = 'z';
imu_recording_start_datetime_str = '2024-07-09 10:25:00'; 

% Plotting Window
plot_window_start_datetime_str = '2024-07-10 06:06:40'; 
plot_duration_sec = 20; 

% Microvolt Conversion
bitres = 17; 
gain = 160;  

% Filter Parameters 
apply_notch_filter = true;
notch_freq_hz = 60; notch_bandwidth_hz = 2;      
apply_bandpass_filter = true;
bandpass_order = 4; bandpass_freqs_hz = [0.5, 70]; 

% Plotting Settings
figure_position = [100, 50, 1400, 800]; 
plot_font_name = 'Arial';
axis_font_size = 11;
data_line_width = 1.0; 

% Y-Axis Limits
eeg_ylim = [-700, 700];
imu_ylim = [0, 5000]; 

% -Standard MATLAB Colors
color_blue   = [0, 0.4470, 0.7410];
color_orange = [0.8500, 0.3250, 0.0980];
color_yellow = [0.9290, 0.6940, 0.1250];

%% Load EEG Data
try
    tbl_eeg_parquet = parquetread(eeg_parquet_file_path);
    raw_eeg_signal = tbl_eeg_parquet.(eeg_signal_column_name);
catch ME; error('Failed to load EEG data: %s', ME.message); end

if size(raw_eeg_signal, 2) > 1 && size(raw_eeg_signal,1) == 1; raw_eeg_signal = raw_eeg_signal';
elseif size(raw_eeg_signal, 2) > 1 && size(raw_eeg_signal,1) > 1; raw_eeg_signal = raw_eeg_signal(:,1); end

%% Load IMU Data

imu_time_datetime = NaT(0,0); 
try
    tbl_imu_parquet = parquetread(imu_parquet_file_path);
    imu_timestamps_raw = tbl_imu_parquet.(imu_timestamp_column_name);
    imu_x_data = double(tbl_imu_parquet.(imu_x_col_name));
    imu_y_data = double(tbl_imu_parquet.(imu_y_col_name));
    imu_z_data = double(tbl_imu_parquet.(imu_z_col_name));
    
    if isa(imu_timestamps_raw, 'datetime')
        imu_time_datetime = imu_timestamps_raw;
        if isempty(imu_time_datetime.TimeZone); imu_time_datetime.TimeZone = target_timezone; else; imu_time_datetime.TimeZone = target_timezone; end
    elseif isnumeric(imu_timestamps_raw)
        imu_start_dt = datetime(imu_recording_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', target_timezone);
        imu_time_datetime = imu_start_dt + milliseconds(imu_timestamps_raw);
    end
catch ME_imu
    warning('Failed to load IMU data: %s', ME_imu.message);
end
can_plot_imu = ~isempty(imu_time_datetime);

%% -Plotting window and time alignment implementation
eeg_file_start_dt = datetime(eeg_recording_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', target_timezone);
effective_plot_start_dt = datetime(plot_window_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', target_timezone);
effective_plot_end_dt = effective_plot_start_dt + seconds(plot_duration_sec);

idx_eeg_start_crop = round(seconds(effective_plot_start_dt - eeg_file_start_dt) * Fs_eeg) + 1;
idx_eeg_end_crop   = round(seconds(effective_plot_end_dt - eeg_file_start_dt) * Fs_eeg) + 1;

if idx_eeg_start_crop < 1; idx_eeg_start_crop = 1; end
if idx_eeg_end_crop > length(raw_eeg_signal); idx_eeg_end_crop = length(raw_eeg_signal); end

raw_eeg_signal_cropped = raw_eeg_signal(idx_eeg_start_crop:idx_eeg_end_crop);
time_vector_eeg_datetime = effective_plot_start_dt + seconds((0:(length(raw_eeg_signal_cropped)-1))' / Fs_eeg);
val_uv = double(raw_eeg_signal_cropped) * 1e6 / (2^bitres * gain);

%% Apply Filters
if apply_notch_filter
    f_nyquist = Fs_eeg / 2;
    [b_notch, a_notch] = butter(2, [(notch_freq_hz-1)/f_nyquist, (notch_freq_hz+1)/f_nyquist], 'stop');
    val_uv = filtfilt(b_notch, a_notch, val_uv);
end

if apply_bandpass_filter
    f_nyquist = Fs_eeg / 2;
    [b_bp, a_bp] = butter(bandpass_order, bandpass_freqs_hz / f_nyquist, 'bandpass');
    val_uv = filtfilt(b_bp, a_bp, val_uv);
end

%% Plotting, Manual Spacing

fig_handle = figure('Color','w', 'Position', figure_position);
ax = [];

% Layout Calculations
left_margin = 0.05;
right_margin = 0.05;
top_margin = 0.05;
bottom_margin = 0.1; % Space for X-ticks
plot_width = 1 - left_margin - right_margin;
total_plot_height = 1 - top_margin - bottom_margin;
gap = 0.00; % Gap between plots (Set to 0 for touching)

height_eeg = total_plot_height * 0.5; % 50% for EEG
height_imu = total_plot_height * 0.5; % 50% for IMU

% -Plot 1: EEG - TOP
% Position: [left, bottom, width, height]
pos_eeg = [left_margin, bottom_margin + height_imu + gap, plot_width, height_eeg];
ax(1) = axes('Position', pos_eeg);
plot(time_vector_eeg_datetime, val_uv, 'k', 'LineWidth', data_line_width);
ylim(eeg_ylim);

% CLEANUP EEG AXIS
set(gca, 'Box', 'off', 'TickDir', 'out', 'FontSize', axis_font_size); 
set(gca, 'XColor', 'none'); % Hide X Axis completely
set(gca, 'YColor', 'none'); % Hide Y Axis completely
grid off;

% -Plot 2: IMU - BOTTOM
pos_imu = [left_margin, bottom_margin, plot_width, height_imu];
ax(2) = axes('Position', pos_imu);

if can_plot_imu
    mask_imu = imu_time_datetime >= effective_plot_start_dt & imu_time_datetime <= effective_plot_end_dt;
    if any(mask_imu)
        hold on;
        plot(imu_time_datetime(mask_imu), imu_x_data(mask_imu), 'Color', color_blue, 'LineWidth', data_line_width);
        plot(imu_time_datetime(mask_imu), imu_y_data(mask_imu), 'Color', color_orange, 'LineWidth', data_line_width);
        plot(imu_time_datetime(mask_imu), imu_z_data(mask_imu), 'Color', color_yellow, 'LineWidth', data_line_width);
        hold off;
        ylim(imu_ylim); 
    end
end

% CLEANUP IMU AXIS
set(gca, 'Box', 'off', 'TickDir', 'out', 'FontSize', axis_font_size); 
set(gca, 'YColor', 'none'); % Hide Y Axis completely
% Keep XColor default (visible)
grid off;

% Shared X-axis logic
linkaxes(ax, 'x');
xlim(ax(1), [effective_plot_start_dt, effective_plot_end_dt]);

start_tick = effective_plot_start_dt;
end_tick = effective_plot_end_dt;
tick_locations = start_tick : seconds(1) : end_tick; 

axes(ax(2)); % Focus on bottom
xticks(tick_locations);
xtickformat('HH:mm:ss'); 

% Remove Label text
% xlabel('Time');

% Enable zoom
h = zoom;
set(h,'Motion','both','Enable','on'); 

fprintf('Minimalist Plot generated.\n');