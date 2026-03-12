% =========================================================================
% FIGURE 4E: ELECTROGRAPHIC SEIZURE
% =========================================================================
% clear, close all, clc;

%% Parameters

% EEG Data Parameters
eeg_recording_start_datetime_str = '2024-07-08 17:15:00';
eeg_parquet_file_path = 'Resaved-tk_micz-2024-07-08T17_15_00-05_00-2024-07-09T17_15_00-05_00-EEG0702.parquet';
eeg_signal_column_name = 'z';
Fs_eeg = 256;

% IMU Data Parameters
imu_parquet_file_path = 'Resaved-tk_xyz_secondary-2024-07-08T17_15_00-05_00-2024-07-09T17_15_00-05_00-EEG0702.parquet';
imu_timestamp_column_name = 't';
imu_x_col_name = 'x'; imu_y_col_name = 'y'; imu_z_col_name = 'z'; 
imu_recording_start_datetime_str = '2024-07-08 17:15:00';

% Plotting Window
plot_window_start_datetime_str = '2024-07-08 22:25:37';
plot_window_end_datetime_str   = '2024-07-08 22:26:37';
seizure_description_text = 'EEG_MovMag_Pub_DarkPurple_8inch'; 

% Plot settings
publication_ready = true; 

% Plots to show:
show_raw_eeg = true;
show_imu_magnitude = true;

% Set colors
color_eeg = 'k'; % Black
color_purple_darker = [0.55, 0.35, 0.75]; 

if publication_ready

    target_pub_width_inches = 8; 
    target_pub_height_inches = 1.5;
    
    figure_width_pixels = target_pub_width_inches * 150;
    figure_height_pixels = target_pub_height_inches * 150;
    figure_position = [100, 50, figure_width_pixels, figure_height_pixels];
    
    plot_font_name = 'Arial';
    axis_font_size = 7;    
    label_font_size = 7;   
    data_line_width = 0.5;
    axis_line_width = 0.25;
    
    % Margins (Normalized units)
    left_margin = 0.10;   % Reduced left margin since plot is wider
    right_margin = 0.05;  
    bottom_margin = 0.20; 
    top_margin = 0.05;    
    vertical_spacing = 0.05; 
else 
    figure_position = [100, 50, 1200, 950];
    plot_font_name = 'Arial';
    axis_font_size = 9;
    label_font_size = 10;
    data_line_width = 1.2;
    axis_line_width = 0.75;
    left_margin = 0.08; right_margin = 0.05; bottom_margin = 0.08; top_margin = 0.05;
    vertical_spacing = 0.05;
end

% Microvolt Conversion Parameters 
bitres = 17; gain = 160;

% Y-Axis Limits
raw_eeg_plot_ylim = [-20, 20];          
imu_magnitude_plot_ylim = [3500 4800];      

%% Load EEG Data
fprintf('Loading EEG data...\n');
try
    tbl_eeg_parquet = parquetread(eeg_parquet_file_path);
    raw_eeg_signal = tbl_eeg_parquet.(eeg_signal_column_name);
catch ME_eeg_load
    error('Failed to load EEG data: %s', ME_eeg_load.message);
end
if size(raw_eeg_signal, 2) > 1 && size(raw_eeg_signal,1) == 1; raw_eeg_signal = raw_eeg_signal';
elseif size(raw_eeg_signal, 2) > 1 && size(raw_eeg_signal,1) > 1; raw_eeg_signal = raw_eeg_signal(:,1); end

%% Load IMU Data
can_plot_imu = false; 
if show_imu_magnitude
    fprintf('Loading IMU data...\n');
    try
        tbl_imu_parquet = parquetread(imu_parquet_file_path);
        imu_timestamps_raw = tbl_imu_parquet.(imu_timestamp_column_name);
        imu_x_data = double(tbl_imu_parquet.(imu_x_col_name));
        imu_y_data = double(tbl_imu_parquet.(imu_y_col_name));
        imu_z_data = double(tbl_imu_parquet.(imu_z_col_name));
        
        imu_time_datetime = NaT(0,0);
        if isa(imu_timestamps_raw, 'datetime')
            imu_time_datetime = imu_timestamps_raw;
            if isempty(imu_time_datetime(1).TimeZone); imu_time_datetime.TimeZone = 'local'; end
        elseif isnumeric(imu_timestamps_raw)
            imu_start_dt = datetime(imu_recording_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
            imu_time_datetime = imu_start_dt + milliseconds(imu_timestamps_raw);
        end
        
        imu_movement_magnitude = sqrt(imu_x_data.^2 + imu_y_data.^2 + imu_z_data.^2); 
        can_plot_imu = true; 
    catch ME_imu_load
        warning('Failed to load IMU: %s', ME_imu_load.message);
    end
end

%% Crop Data
eeg_file_start_dt = datetime(eeg_recording_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
effective_plot_start_dt = datetime(plot_window_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
effective_plot_end_dt = datetime(plot_window_end_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');

offset_start = seconds(effective_plot_start_dt - eeg_file_start_dt);
offset_end   = seconds(effective_plot_end_dt - eeg_file_start_dt);
idx_start = round(offset_start * Fs_eeg) + 1;
idx_end   = round(offset_end * Fs_eeg) + 1;

if idx_start < 1; idx_start = 1; end
if idx_end > length(raw_eeg_signal); idx_end = length(raw_eeg_signal); end

raw_eeg_signal_cropped = raw_eeg_signal(idx_start:idx_end);
time_vector_eeg_datetime = effective_plot_start_dt + seconds((0:(length(raw_eeg_signal_cropped)-1))' / Fs_eeg);
val_uv = double(raw_eeg_signal_cropped) * 1e6 / (2^bitres * gain);

%% Plot Selected Data

fig_handle = figure('Color','w', 'Position', figure_position); 

plot_width_norm = 1 - left_margin - right_margin;
total_plot_height_norm = 1 - bottom_margin - top_margin;
plot_height_each_norm = (total_plot_height_norm - vertical_spacing) / 2;

eeg_ax = []; imu_mag_ax = [];
valid_axes = [];

% EEG Plot (Top)
if show_raw_eeg
    pos_eeg = [left_margin, bottom_margin + plot_height_each_norm + vertical_spacing, plot_width_norm, plot_height_each_norm];
    eeg_ax = axes('Position', pos_eeg);
    plot(eeg_ax, time_vector_eeg_datetime, val_uv, 'Color', color_eeg, 'LineWidth', data_line_width);
    ylabel(eeg_ax, 'EEG (\muV)', 'FontName', plot_font_name, 'FontSize', label_font_size);
    if ~isempty(raw_eeg_plot_ylim); ylim(eeg_ax, raw_eeg_plot_ylim); else; axis(eeg_ax, 'tight'); end
    set(eeg_ax, 'FontName', plot_font_name, 'FontSize', axis_font_size, 'TickDir', 'out', 'LineWidth', axis_line_width, 'Box', 'off');
    set(eeg_ax, 'XAxisLocation', 'bottom'); 
    eeg_ax.XAxis.Visible = 'off'; 
    eeg_ax.YAxis.Visible = 'off'; 
    % Re-apply label
    ylabel(eeg_ax, 'EEG (\muV)', 'FontName', plot_font_name, 'FontSize', label_font_size, 'Visible', 'on');
    valid_axes = [valid_axes, eeg_ax];
end

% IMU Plot (Bottom)
if show_imu_magnitude && can_plot_imu
    pos_imu = [left_margin, bottom_margin, plot_width_norm, plot_height_each_norm];
    imu_mag_ax = axes('Position', pos_imu);
    
    mask = imu_time_datetime >= effective_plot_start_dt & imu_time_datetime <= effective_plot_end_dt;
    if any(mask)
        plot(imu_mag_ax, imu_time_datetime(mask), imu_movement_magnitude(mask), ...
             'Color', color_purple_darker, 'LineWidth', data_line_width);
         
        ylabel(imu_mag_ax, sprintf('Mov Mag\n(au)'), 'FontName', plot_font_name, 'FontSize', label_font_size);
        if ~isempty(imu_magnitude_plot_ylim); ylim(imu_mag_ax, imu_magnitude_plot_ylim); else; axis(imu_mag_ax, 'tight'); end
    end
    set(imu_mag_ax, 'FontName', plot_font_name, 'FontSize', axis_font_size, 'TickDir', 'out', 'LineWidth', axis_line_width, 'Box', 'off');
    imu_mag_ax.YAxis.Visible = 'off'; 
    
    % Re-apply label
    ylabel(imu_mag_ax, sprintf('Mov Mag\n(au)'), 'FontName', plot_font_name, 'FontSize', label_font_size, 'Visible', 'on');
    valid_axes = [valid_axes, imu_mag_ax];
end

% Formatting
if ~isempty(valid_axes)
    linkaxes(valid_axes, 'x');
    xlim(valid_axes(1), [effective_plot_start_dt, effective_plot_end_dt]);
    
    % Format Bottom Axis
    if ~isempty(imu_mag_ax)
        datetick(imu_mag_ax, 'x', 'HH:MM:SS', 'keeplimits');
        imu_mag_ax.XTickLabelRotation = 0;
    end
end

%% Save figure (Optional)
if publication_ready
    set(fig_handle, 'PaperUnits', 'inches');
    set(fig_handle, 'PaperSize', [target_pub_width_inches, target_pub_height_inches]);
    set(fig_handle, 'PaperPosition', [0, 0, target_pub_width_inches, target_pub_height_inches]);
end

filename = strrep(seizure_description_text, ' ', '_');
fprintf('Saving to %s.png...\n', filename);
print(fig_handle, [filename '.png'], '-dpng', '-r300');
fprintf('Done.\n');