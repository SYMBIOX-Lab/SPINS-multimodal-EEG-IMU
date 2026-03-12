% =========================================================================
% FIGURE 1G: VISUALIZING EEG, IMU, AND MOTION MAGNITUDE
% =========================================================================
% This script aligns and plots raw EEG data alongside accelerometer (IMU) data.
% It's built to help spot motion artifacts or see how physical movement 
% correlates with EEG activity during seizures.

% clear;
% close all;
% clc

%% --- 2. Parameters ---
% EEG Dataset details
eeg_recording_start_datetime_str = '2023-11-02 16:30:00';
eeg_parquet_file_path = 'Resaved-biov-2023-11-02T16_30_00-05_00-2023-11-03T12_45_00-05_00-EEGN03.parquet';
eeg_signal_column_name = 'val';
Fs_eeg = 256; % Sampling frequency in Hz

% IMU (Accelerometer) details
imu_parquet_file_path = 'Resaved-xyz-2023-11-02T16_30_00-05_00-2023-11-03T12_45_00-05_00-EEGN03.parquet';
imu_timestamp_column_name = 't';
imu_x_col_name = 'x';
imu_y_col_name = 'y';
imu_z_col_name = 'z';
imu_recording_start_datetime_str = '2023-11-02 16:30:00';

% Define the specific time window we want to look at in the plot
plot_window_start_datetime_str = '2023-11-03 01:30:00';
plot_window_end_datetime_str   = '2023-11-03 11:00:00';

% Optional: Seizure onset markers for the plot
seizure_onset_datetime_strs = {'2023-10-24 10:31:00'}; 
seizure_description_text = 'Left Temporal Seizure Analysis';

% Conversion factors for EEG microvolts (uV)
bitres = 17;
gain = 160;

% Visual settings for the figure
figure_position = [100, 50, 1200, 950];
plot_font_name = 'Arial';
axis_font_size = 9;
label_font_size = 10;
data_line_width = 1.2;
axis_line_width = 0.75;

%% --- 3. Load EEG Data ---
fprintf('Loading EEG data from Parquet file: %s\n', eeg_parquet_file_path);
try
    tbl_eeg_parquet = parquetread(eeg_parquet_file_path);
    raw_eeg_signal = tbl_eeg_parquet.(eeg_signal_column_name);
    fprintf('EEG data loaded successfully for channel: %s.\n', eeg_signal_column_name);
catch ME_eeg_load
    error('Failed to load EEG data. Check file path or column names.\nError: %s', ME_eeg_load.message);
end

% Basic cleaning: ensure it's a column vector
if isempty(raw_eeg_signal); error('Raw EEG signal is empty.'); end
if size(raw_eeg_signal, 2) > 1 && size(raw_eeg_signal,1) == 1; raw_eeg_signal = raw_eeg_signal';
elseif size(raw_eeg_signal, 2) > 1 && size(raw_eeg_signal,1) > 1
    warning('Multiple columns found. Defaulting to the first.'); raw_eeg_signal = raw_eeg_signal(:,1);
end

%% --- 3.1. Load IMU Data ---
fprintf('Loading IMU data from Parquet file: %s\n', imu_parquet_file_path);
imu_time_datetime = NaT(0,0); imu_movement_magnitude = [];
imu_x_data = []; imu_y_data = []; imu_z_data = [];
try
    tbl_imu_parquet = parquetread(imu_parquet_file_path);
    imu_timestamps_raw = tbl_imu_parquet.(imu_timestamp_column_name);
    imu_x_data = tbl_imu_parquet.(imu_x_col_name);
    imu_y_data = tbl_imu_parquet.(imu_y_col_name);
    imu_z_data = tbl_imu_parquet.(imu_z_col_name);

    if isa(imu_timestamps_raw, 'datetime')
        imu_time_datetime = imu_timestamps_raw;
        if isempty(imu_time_datetime(1).TimeZone); imu_time_datetime.TimeZone = 'local'; end
    elseif isnumeric(imu_timestamps_raw) && ~isempty(imu_recording_start_datetime_str)
        imu_start_dt = datetime(imu_recording_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
        imu_time_datetime = imu_start_dt + milliseconds(imu_timestamps_raw); 
    end

    % Calculate resultant magnitude
    imu_x_data = double(imu_x_data(:)); imu_y_data = double(imu_y_data(:)); imu_z_data = double(imu_z_data(:));
    imu_movement_magnitude = sqrt(imu_x_data.^2 + imu_y_data.^2 + imu_z_data.^2);
    
    if length(imu_time_datetime) ~= length(imu_movement_magnitude); error('IMU time/data length mismatch.'); end
    fprintf('IMU data loaded and processed.\n');
catch ME_imu_load
    warning('IMU data issue. Plots will focus on EEG only.');
end

can_plot_imu = ~isempty(imu_time_datetime) && length(imu_time_datetime) == length(imu_movement_magnitude);

%% --- 3.5. Time Alignment & Cropping ---
eeg_file_start_dt = datetime(eeg_recording_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
effective_plot_start_dt = datetime(plot_window_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
effective_plot_end_dt = datetime(plot_window_end_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');

offset_start_sec = seconds(effective_plot_start_dt - eeg_file_start_dt);
offset_end_sec   = seconds(effective_plot_end_dt - eeg_file_start_dt);
idx_eeg_start_crop = max(1, round(offset_start_sec * Fs_eeg) + 1);
idx_eeg_end_crop   = min(length(raw_eeg_signal), round(offset_end_sec * Fs_eeg) + 1);

raw_eeg_signal_cropped = raw_eeg_signal(idx_eeg_start_crop:idx_eeg_end_crop);
time_vector_eeg_datetime = effective_plot_start_dt + seconds((0:(length(raw_eeg_signal_cropped)-1))' / Fs_eeg);
time_vector_eeg_datetime.TimeZone = 'local';

% Convert signal to microvolts
val_uv = double(raw_eeg_signal_cropped) * 1e6 / (2^bitres * gain);

%% --- 6. Prepare Seizure Onset Markers ---
seizure_onset_dt_objs = NaT(0,0);
if iscell(seizure_onset_datetime_strs)
    valid_dts = [];
    for k = 1:length(seizure_onset_datetime_strs)
        try
            valid_dts = [valid_dts; datetime(seizure_onset_datetime_strs{k}, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local')];
        catch
        end
    end
    seizure_onset_dt_objs = valid_dts;
end

%% --- 7. Plotting ---
fprintf('Plotting data...\n');
fig_handle = figure('Color','w', 'Position', figure_position);

num_eeg_plots = 1;
num_imu_plots = can_plot_imu * 2; 
num_active_plots = num_eeg_plots + num_imu_plots;
ax = gobjects(num_active_plots, 1);
plot_counter = 0;

dull_purple = [0.55, 0.47, 0.59]; 
colors = [0 0 0; dull_purple]; % Black (EEG), Purple (Magnitude)

% --- PLOT 1: Raw EEG Signal (Top) ---
plot_counter = plot_counter + 1;
ax(plot_counter) = subplot(num_active_plots, 1, plot_counter);
if ~isempty(val_uv)
    plot(ax(plot_counter), time_vector_eeg_datetime, val_uv, 'Color', colors(1,:), 'LineWidth', data_line_width);
    % Setting top plot range to -150 to 150 as requested
    ylim(ax(plot_counter), [-200 200]); 
else
    text(0.5,0.5,'EEG data not available','HorizontalAlignment','center');
end
set(ax(plot_counter), 'FontName', plot_font_name, 'FontSize', axis_font_size, 'TickDir', 'out', 'LineWidth', axis_line_width, 'Box', 'off');

% --- IMU Plots ---
if can_plot_imu
    imu_plot_indices = imu_time_datetime >= effective_plot_start_dt & imu_time_datetime <= effective_plot_end_dt;
    
    % --- PLOT 2: IMU XYZ Components (Middle) ---
    plot_counter = plot_counter + 1;
    ax(plot_counter) = subplot(num_active_plots, 1, plot_counter);
    hold on;
    plot(ax(plot_counter), imu_time_datetime(imu_plot_indices), imu_x_data(imu_plot_indices), 'LineWidth', data_line_width);
    plot(ax(plot_counter), imu_time_datetime(imu_plot_indices), imu_y_data(imu_plot_indices), 'LineWidth', data_line_width);
    plot(ax(plot_counter), imu_time_datetime(imu_plot_indices), imu_z_data(imu_plot_indices), 'LineWidth', data_line_width);
    % Legend removed as requested
    set(ax(plot_counter), 'FontName', plot_font_name, 'FontSize', axis_font_size, 'TickDir', 'out', 'LineWidth', axis_line_width, 'Box', 'off');

    % --- PLOT 3: IMU Movement Magnitude (Bottom) ---
    plot_counter = plot_counter + 1;
    ax(plot_counter) = subplot(num_active_plots, 1, plot_counter);
    plot(ax(plot_counter), imu_time_datetime(imu_plot_indices), imu_movement_magnitude(imu_plot_indices), 'Color', colors(2,:), 'LineWidth', data_line_width);
    % Setting bottom plot range to 4100 to 4900 as requested
    ylim(ax(plot_counter), [4150 4900]); 
    xlabel(ax(plot_counter), 'Date / Time', 'FontName', plot_font_name, 'FontSize', label_font_size);
    set(ax(plot_counter), 'FontName', plot_font_name, 'FontSize', axis_font_size, 'TickDir', 'out', 'LineWidth', axis_line_width, 'Box', 'off');
end

%% --- Final Figure Formatting ---
valid_ax = ax(isgraphics(ax) & ax~=0);
if length(valid_ax) > 1
    linkaxes(valid_ax, 'x');
    % Tighten vertical spacing
    vertical_gap = 0.04; top_margin = 0.98; bottom_margin = 0.1;
    total_h = top_margin - bottom_margin;
    plot_h = (total_h - vertical_gap*(length(valid_ax)-1)) / length(valid_ax);
    for i = 1:length(valid_ax)
        pos = get(valid_ax(i), 'Position');
        pos(2) = top_margin - i*plot_h - (i-1)*vertical_gap;
        pos(4) = plot_h;
        set(valid_ax(i), 'Position', pos);
    end
end

% Set the synchronized time range
if ~isempty(valid_ax)
    xlim(valid_ax(1), [effective_plot_start_dt, effective_plot_end_dt]);
    datetick(valid_ax(end), 'x', 'HH:MM', 'keeplimits');
    if length(valid_ax) > 1; set(valid_ax(1:end-1), 'XTickLabel', ''); end
end

% Draw seizure onset markers
if ~isempty(seizure_onset_dt_objs)
    for i = 1:length(valid_ax)
        hold(valid_ax(i), 'on');
        for k = 1:length(seizure_onset_dt_objs)
            xline(valid_ax(i), seizure_onset_dt_objs(k), '--r', 'Label', 'Seizure Onset');
        end
    end
end

fprintf('Plots generated.\n');