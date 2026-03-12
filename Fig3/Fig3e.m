% =========================================================================
% FIGURE 3E: DELTA-THETA BANDS ICTAL ACTIVITY
% =========================================================================
%clear; 
%close all; 
%clc; 

%% Parameters
% Input EEG Data: recording start time, file path, column, and sampling
% frequency
eeg_recording_start_datetime_str = '2023-10-24 11:51:00'; 
eeg_parquet_file_path = 'Resaved-biov-2023-10-24T11_51_00-05_00-2023-10-25T11_51_00-05_00-EEGN03.parquet';  
eeg_signal_column_name = 'val'; 
Fs_eeg = 256;

% Define plotting window
plot_window_start_datetime_str = '2023-10-24 12:37:00'; 
plot_window_end_datetime_str   = '2023-10-24 12:41:00'; 

% Seizure onset time (optional)
seizure_onset_datetime_str = '2023-10-24 12:39:00';

% Extracting delta and theta frequency bands
delta_band_hz = [0.5, 4]; % Delta band definition (Hz)
theta_band_hz = [4, 8];   % Theta band definition (Hz)

% Microvolt conversion parameters
bitres = 17;
gain = 160; 

% Band Power Parameters
power_smoothing_window_sec = 1.0; % Seconds to average/smooth the power plot over (0.5-2s)

% Plotting parameters
plot_font_name = 'Arial';
axis_font_size = 9;
label_font_size = 10;
line_width_power = 1.5;

% Figure position adjusted to 3.5 width x 2.5 height aspect ratio
figure_width_pixels = 3.5 * 150; 
figure_height_pixels = 2.5 * 150;
figure_position = [100, 100, figure_width_pixels, figure_height_pixels]; 

%% Derive parameters and set up time window

% Convert datetime strings to datetime objects
try
    eeg_file_start_dt = datetime(eeg_recording_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
    plot_start_dt = datetime(plot_window_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
    plot_end_dt = datetime(plot_window_end_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
    seizure_onset_dt = datetime(seizure_onset_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
catch ME
    error('Error parsing datetime strings: %s. Please check formats (yyyy-MM-dd HH:mm:ss).', ME.message);
end

if plot_start_dt >= plot_end_dt
    error('Plot window start time must be before end time.');
end

%% Apply load, crop and conversion for EEG data

fprintf('Loading EEG data...\n');
try
    tbl_eeg_parquet = parquetread(eeg_parquet_file_path);
catch ME_load
    error('Failed to read Parquet file "%s". Error: %s', eeg_parquet_file_path, ME_load.message);
end

if ~ismember(eeg_signal_column_name, tbl_eeg_parquet.Properties.VariableNames)
    error('Specified eeg_signal_column_name "%s" not found in the Parquet file. Available columns: %s', ...
        eeg_signal_column_name, strjoin(tbl_eeg_parquet.Properties.VariableNames, ', '));
end
raw_eeg_signal_full = tbl_eeg_parquet.(eeg_signal_column_name);

% Calculate start and end indices for the plot window
offset_plot_start_sec = seconds(plot_start_dt - eeg_file_start_dt);
offset_plot_end_sec = seconds(plot_end_dt - eeg_file_start_dt);

idx_plot_start = round(offset_plot_start_sec * Fs_eeg) + 1;
idx_plot_end = round(offset_plot_end_sec * Fs_eeg) + 1; 

% Boundary checks for cropping indices
if idx_plot_start < 1
    warning('Plot window start (datetime: %s, index: %d) is before the EEG file start. Adjusting to beginning of file.', datestr(plot_start_dt), idx_plot_start);
    idx_plot_start = 1;
    plot_start_dt = eeg_file_start_dt; 
end

if idx_plot_end > length(raw_eeg_signal_full)
    warning('Plot window end (datetime: %s, index: %d) is after the EEG file end. Adjusting to end of file.', datestr(plot_end_dt), idx_plot_end);
    idx_plot_end = length(raw_eeg_signal_full);
    plot_end_dt = eeg_file_start_dt + seconds((idx_plot_end-1)/Fs_eeg); 
end

if idx_plot_start >= idx_plot_end
    error('No valid data in the specified plot window (Start index %d, End index %d). Check times or data length.', idx_plot_start, idx_plot_end);
end

raw_eeg_signal_plot_window = raw_eeg_signal_full(idx_plot_start:idx_plot_end);

% Create the time vector for the plotted data
time_vector_plot_datetime = plot_start_dt + seconds((0:(length(raw_eeg_signal_plot_window)-1))' / Fs_eeg);
if ~isempty(time_vector_plot_datetime); time_vector_plot_datetime.TimeZone = 'local'; end

% Convert to microvolts
val_uv_plot_window = double(raw_eeg_signal_plot_window) * 1e6 / (2^bitres * gain);
fprintf('EEG data for plot window loaded, cropped, and converted to microvolts.\n');

%% Analysis for Plotting
% Filter for Delta and Theta Bands for the plot window
fprintf('Filtering for Delta and Theta bands for the plot window...\n');
delta_filtered_plot = bandpass(val_uv_plot_window, delta_band_hz, Fs_eeg);
theta_filtered_plot = bandpass(val_uv_plot_window, theta_band_hz, Fs_eeg);

% Calculate Instantaneous Power for each band for the plot window
fprintf('Calculating instantaneous power for each band...\n');
delta_power_inst_plot = abs(hilbert(delta_filtered_plot)).^2;
theta_power_inst_plot = abs(hilbert(theta_filtered_plot)).^2;

% Smooth the power signals for better visualization
smoothing_samples_power = round(power_smoothing_window_sec * Fs_eeg);
if smoothing_samples_power < 1; smoothing_samples_power = 1; end 

delta_power_smooth_plot = movmean(delta_power_inst_plot, smoothing_samples_power);
theta_power_smooth_plot = movmean(theta_power_inst_plot, smoothing_samples_power);

fprintf('Analysis for plotting complete.\n');

%% Plotting
fig = figure('Color', 'w', 'Position', figure_position);

% Create single axes for band power plot
ax_power = axes('Parent', fig); % Create axes directly

plot(ax_power, time_vector_plot_datetime, delta_power_smooth_plot, 'Color', [0 0.4470 0.7410], 'LineWidth', line_width_power, 'DisplayName', sprintf('Delta Power (%.1f-%.1f Hz)', delta_band_hz(1), delta_band_hz(2)));
hold(ax_power, 'on');
plot(ax_power, time_vector_plot_datetime, theta_power_smooth_plot, 'Color', [0.8500 0.3250 0.0980], 'LineWidth', line_width_power, 'DisplayName', sprintf('Theta Power (%.1f-%.1f Hz)', theta_band_hz(1), theta_band_hz(2)));
hold(ax_power, 'off');

% Axes and formatting
xlabel(ax_power, 'Time', 'FontName', plot_font_name, 'FontSize', label_font_size);
legend(ax_power, 'show', 'Location', 'northeast', 'FontSize', axis_font_size-1);
    
set(ax_power, 'FontName', plot_font_name, 'FontSize', axis_font_size, 'Box', 'off'); 
ax_power.YAxis.Visible = 'off'; 
axis(ax_power, 'tight'); 

xlim(ax_power, [time_vector_plot_datetime(1), time_vector_plot_datetime(end)]); 

% Set appropriate x-axis tick format
plot_duration_total_hours = hours(time_vector_plot_datetime(end) - time_vector_plot_datetime(1));
if plot_duration_total_hours <= (2/60); tick_format = 'HH:MM:SS.FFF'; 
elseif plot_duration_total_hours <= (30/60); tick_format = 'HH:MM:SS'; 
elseif plot_duration_total_hours <= 4; tick_format = 'HH:MM';      
else; tick_format = 'dd-mmm HH:MM';                                
end
datetick(ax_power, 'x', tick_format, 'keeplimits');
ax_power.XTickLabelRotation = 25;

fprintf('Plot generation complete.\n');

%% Save Figure (optional)
% save_figure = false; % << USER: Set to true to save the figure
% if save_figure
%     channel_name_safe = matlab.lang.makeValidName(strrep(eeg_signal_column_name,'_','-'));
%     start_time_safe = datestr(plot_start_dt, 'yyyymmdd_HHMMSS');
%     figure_filename_base = 'DeltaThetaPower_Minimal'; 
%     figure_filename = sprintf('%s_Channel_%s_Start_%s.png',figure_filename_base, channel_name_safe, start_time_safe);
%     figure_filename = matlab.lang.makeValidName(figure_filename); 
%     try
%         exportgraphics(fig, figure_filename, 'Resolution', 300);
%         fprintf('Figure saved to: %s\n', figure_filename);
%     catch ME_save
%         fprintf('Error saving figure: %s\n', ME_save.message);
%     end
% end
