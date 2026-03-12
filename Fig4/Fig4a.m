% =========================================================================
% FIGURE 4A: BI-TEMPORAL SEIZURE
% =========================================================================

% clear; 
% close all; 
% clc; 

%% Parameters

% Import EEG data: recording start time, file path, column, sampling frequency
eeg_recording_start_datetime_str = '2023-10-23 11:51:00';
eeg_parquet_file_path = 'Resaved-biov-2023-10-23T11_51_00-05_00-2023-10-24T11_51_00-05_00-EEGN03.parquet'; % << USER: SET EEG PARQUET FILE PATH
eeg_signal_column_name = 'val';      
Fs_eeg = 256; 

% Import IMU data: recording start time, file path, column, sampling
% frequency

imu_parquet_file_path = 'Resaved-xyz-2023-12-11T12_25_00-06_00-2023-12-12T12_25_00-06_00-EEGN03.parquet'; % << USER: SET IMU PARQUET FILE PATH; % << USER: SET IMU PARQUET FILE PATH
imu_timestamp_column_name = 't'; 
imu_x_col_name = 'x';                 
imu_y_col_name = 'y';                
imu_z_col_name = 'z';                      
imu_recording_start_datetime_str = '2023-10-24 11:51:00'; 

% Plot window
plot_window_start_datetime_str = '2023-10-24 10:27:00';
plot_window_end_datetime_str   = '2023-10-24 10:37:00'; 

% Seizure onset time
seizure_onset_datetime_strs = {'2023-10-24 11:51:00'}; 
seizure_description_text = 'Left Temporal Example';

% Spectogram parameters
spectrogram_freq_max_hz = 25;  % Focus up to ~beta, good for delta (0.5-4), theta (4-8), alpha (8-13)
clim_lower_percentile = 65;
clim_upper_percentile = 97;
win_len_sec = 1.0;             % Window length for STFT (1.0s or 1.5s)
overlap_percentage = 75;

% Microvolt conversion parameters
bitres = 17; 
gain = 160;  

% Filtering parameters
apply_notch_filter = true;
notch_freq_hz = 60;          % Notch filter frequency (Hz) for powerline noise
notch_bandwidth_hz = 2;      % Bandwidth for the notch filter in Hz
apply_bandpass_filter = true;
bandpass_order = 4;          % 4th order Butterworth filter
bandpass_freqs_hz = [0.5, 70]; % Passband frequencies in Hz [low_cutoff, high_cutoff]

% Plotting/figure parameters
figure_position = [100, 100, 1000, 350]; % Figure size for a single spectrogram plot
plot_font_name = 'Arial';
axis_font_size = 10;
label_font_size = 11;
title_font_size = 12;
axis_line_width = 0.75;

% Spectrogram Calculation Parameters (EEG derived)
N_window = round(win_len_sec * Fs_eeg);
N_overlap = round(N_window * (overlap_percentage / 100));
N_fft = max(1024, 2^nextpow2(N_window));

%% Load EEG Data
fprintf('Loading EEG data from Parquet file: %s\n', eeg_parquet_file_path);
try
    tbl_eeg_parquet = parquetread(eeg_parquet_file_path);
    raw_eeg_signal = tbl_eeg_parquet.(eeg_signal_column_name);
    fprintf('EEG data loaded successfully for channel: %s.\n', eeg_signal_column_name);
catch ME_eeg_load
    error('Failed to load EEG data for channel %s from Parquet file: %s\nError: %s', eeg_signal_column_name, eeg_parquet_file_path, ME_eeg_load.message);
end

if isempty(raw_eeg_signal); error('Raw EEG signal is empty after loading for channel: %s.', eeg_signal_column_name); end

if size(raw_eeg_signal, 2) > 1 && size(raw_eeg_signal,1) == 1; raw_eeg_signal = raw_eeg_signal';
elseif size(raw_eeg_signal, 2) > 1 && size(raw_eeg_signal,1) > 1
    warning('EEG signal for channel %s has multiple columns. Using the first column only.', eeg_signal_column_name); raw_eeg_signal = raw_eeg_signal(:,1);
end

%% Implement time window and time alignment
try eeg_file_start_dt = datetime(eeg_recording_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
catch ME; error('Invalid eeg_recording_start_datetime_str: %s. Error: %s', eeg_recording_start_datetime_str, ME.message); end

try effective_plot_start_dt = datetime(plot_window_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
catch ME; error('Invalid plot_window_start_datetime_str: %s. Error: %s', plot_window_start_datetime_str, ME.message); end

try effective_plot_end_dt = datetime(plot_window_end_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
catch ME; error('Invalid plot_window_end_datetime_str: %s. Error: %s', plot_window_end_datetime_str, ME.message); end

if effective_plot_start_dt >= effective_plot_end_dt
    error('Plot window start time must be before end time. Please correct.');
end

offset_plot_start_sec_from_eeg_file_start = seconds(effective_plot_start_dt - eeg_file_start_dt);
offset_plot_end_sec_from_eeg_file_start   = seconds(effective_plot_end_dt - eeg_file_start_dt);

% Ensure indices are positive and within bounds of raw_eeg_signal
idx_eeg_start_crop = max(1, round(offset_plot_start_sec_from_eeg_file_start * Fs_eeg) + 1);
idx_eeg_end_crop   = min(length(raw_eeg_signal), round(offset_plot_end_sec_from_eeg_file_start * Fs_eeg) + 1);

% Adjust effective plot start/end times if cropping changed the actual window
if idx_eeg_start_crop == 1 && offset_plot_start_sec_from_eeg_file_start < 0
    warning('Plot window starts before EEG data. Effective plot start adjusted to EEG file start.');
    effective_plot_start_dt = eeg_file_start_dt;
    if ~isempty(effective_plot_start_dt); effective_plot_start_dt.TimeZone = 'local'; end;
end

if idx_eeg_end_crop == length(raw_eeg_signal) && offset_plot_end_sec_from_eeg_file_start > (length(raw_eeg_signal)-1)/Fs_eeg
     warning('Plot window ends after EEG data. Effective plot end adjusted to EEG file end.');
    effective_plot_end_dt = eeg_file_start_dt + seconds((length(raw_eeg_signal)-1)/Fs_eeg);
    if ~isempty(effective_plot_end_dt); effective_plot_end_dt.TimeZone = 'local'; end;
end
if idx_eeg_start_crop >= idx_eeg_end_crop || idx_eeg_start_crop > length(raw_eeg_signal) || idx_eeg_end_crop < 1
    error('No valid EEG data range for the specified plot window after adjustments. Check datetime strings, data length, and alignment.');
else
    raw_eeg_signal_cropped = raw_eeg_signal(idx_eeg_start_crop:idx_eeg_end_crop);
    fprintf('EEG data cropped to plot window: %s to %s.\n', datestr(effective_plot_start_dt), datestr(effective_plot_end_dt));
end

if isempty(raw_eeg_signal_cropped)
    error('EEG signal is empty after cropping. Cannot proceed.');
end

val_uv = double(raw_eeg_signal_cropped) * 1e6 / (2^bitres * gain);
fprintf('Cropped EEG Data converted to microvolts.\n');

%% Apply Filters to EEG Data

if apply_notch_filter || apply_bandpass_filter
    fprintf('Applying filters to EEG data...\n');
end

% Design and apply a 60 Hz notch filter
if apply_notch_filter
    fprintf(' -> Applying %.1f Hz notch filter.\n', notch_freq_hz);
    f_nyquist = Fs_eeg / 2;
    f_low = (notch_freq_hz - notch_bandwidth_hz / 2) / f_nyquist;
    f_high = (notch_freq_hz + notch_bandwidth_hz / 2) / f_nyquist;
    [b_notch, a_notch] = butter(2, [f_low, f_high], 'stop');
    val_uv = filtfilt(b_notch, a_notch, val_uv);
end

% Design and apply a Butterworth bandpass filter
if apply_bandpass_filter
    fprintf(' -> Applying %.1f-%.1f Hz bandpass filter.\n', bandpass_freqs_hz(1), bandpass_freqs_hz(2));
    f_nyquist = Fs_eeg / 2;
    [b_bandpass, a_bandpass] = butter(bandpass_order, bandpass_freqs_hz / f_nyquist, 'bandpass');
    val_uv = filtfilt(b_bandpass, a_bandpass, val_uv);
end

%% Calculate EEG Spectrogram

P_db = []; T_spec_datetime = []; F_spec = [];
if isempty(val_uv)
    warning('val_uv is empty before spectrogram calculation. Skipping spectrogram.');
elseif length(val_uv) < N_window
    warning('EEG signal for spectrogram (length: %d samples) is shorter than STFT window length (%d samples). Spectrogram might be empty or inaccurate.', length(val_uv), N_window);
else
    [~, F_spec, T_spec_relative_sec, P_spec_data] = spectrogram(val_uv, N_window, N_overlap, N_fft, Fs_eeg, 'psd');
    epsilon = 1e-12;
    P_db = 10 * log10(P_spec_data + epsilon);
    T_spec_datetime = effective_plot_start_dt + seconds(T_spec_relative_sec);
    if ~isempty(T_spec_datetime); T_spec_datetime.TimeZone = 'local'; end
end

fprintf('EEG Spectrogram calculated.\n');

%% Plot EEG Spectrogram

fig_handle = figure('Color','w'); 
set(fig_handle, 'Position', figure_position);

if ~isempty(P_db) && ~isempty(T_spec_datetime) && ~isempty(F_spec)
    ax_spec = axes; % Create a single axes for the spectrogram
    imagesc(ax_spec, T_spec_datetime, F_spec, P_db);
    axis(ax_spec, 'xy');
    colormap(ax_spec, parula);
    colorbar(ax_spec);
    all_P_db_plot_vals = P_db(:);
    all_P_db_plot_vals = all_P_db_plot_vals(isfinite(all_P_db_plot_vals));
    clim_vals_spec_plot = [-12 8]; % Default fallback
    if ~isempty(all_P_db_plot_vals)
        clim_vals_spec_plot = [prctile(all_P_db_plot_vals, clim_lower_percentile), prctile(all_P_db_plot_vals, clim_upper_percentile)];
        if clim_vals_spec_plot(1) >= clim_vals_spec_plot(2)
            if all(all_P_db_plot_vals == all_P_db_plot_vals(1)); clim_vals_spec_plot = [all_P_db_plot_vals(1) - 0.5, all_P_db_plot_vals(1) + 0.5];
            else; clim_vals_spec_plot = [clim_vals_spec_plot(1)-1, clim_vals_spec_plot(1)+1]; end
        end
    end

    clim(ax_spec, clim_vals_spec_plot);
    ylim(ax_spec, [0 65]);
    
    set(ax_spec, 'FontName', plot_font_name, 'FontSize', axis_font_size, 'TickDir', 'in', 'LineWidth', axis_line_width, 'Box', 'off');
    set(ax_spec, 'YTickLabel', {});
    grid(ax_spec, 'off');

    % X-Tick Label Formatting
    plot_duration_hours = hours(effective_plot_end_dt - effective_plot_start_dt);
    if plot_duration_hours <= (10/60); tick_format = 'HH:MM:SS';
    elseif plot_duration_hours <= 2; tick_format = 'HH:MM';
    else; tick_format = 'dd-mmm HH:MM'; end
    ax_spec.XTickLabelRotation = 30;
    datetick(ax_spec, 'x', tick_format, 'keeplimits');
    
    set(ax_spec, 'XTickLabel', {}); 
else
    text(0.5,0.5,'Spectrogram data not available or signal too short for STFT.','HorizontalAlignment','center', 'FontName', plot_font_name);
    axis off;
end

% Save figure (optional)
% valid_fig_handle = ishandle(fig_handle) && strcmp(get(fig_handle,'type'),'figure');
% if valid_fig_handle
%     plot_filename_base_str = 'EEG_SpectrogramOnly';
%     if ~isempty(seizure_description_text)
%         plot_filename_base_str = [plot_filename_base_str, '_', matlab.lang.makeValidName(strrep(seizure_description_text, ' ', '_'))];
%     end
%     if ~isempty(plot_window_start_datetime_str)
%         try dt_start_str_for_file_name = datestr(datetime(plot_window_start_datetime_str, 'TimeZone', 'local'), 'yyyymmdd_HHMMSS');
%             plot_filename_no_ext_str = sprintf('%s_%s', plot_filename_base_str, dt_start_str_for_file_name);
%         catch; plot_filename_no_ext_str = plot_filename_base_str; end
%     else; plot_filename_no_ext_str = plot_filename_base_str; end
% 
%     % Save .fig file
%     fig_filename_fig_str = [plot_filename_no_ext_str, '.fig'];
%     fprintf('Saving interactive plot to: %s\n', fig_filename_fig_str);
%     savefig(fig_handle, fig_filename_fig_str); fprintf('Interactive plot saved.\n');
% 
%     % Save .png file
%     fig_filename_png_str = [plot_filename_no_ext_str, '.png'];
%     fprintf('Saving high-resolution PNG to: %s\n', fig_filename_png_str);
%     try
%       exportgraphics(fig_handle, fig_filename_png_str, 'Resolution', 300); fprintf('High-resolution PNG saved.\n');
%     catch ME_export
%         fprintf('Could not save PNG with exportgraphics (requires R2020a or newer). Error: %s\n', ME_export.message);
%         fprintf('Attempting to save with saveas instead (lower quality for some formats).\n');
%         try
%             saveas(fig_handle, fig_filename_png_str); fprintf('PNG saved with saveas.\n');
%         catch ME_saveas
%             fprintf('Failed to save PNG with saveas. Error: %s\n', ME_saveas.message);
%         end
%     end
% 
%     % Save .emf file
%     fig_filename_emf_str = [plot_filename_no_ext_str, '.emf'];
%     fprintf('Saving vector EMF to: %s\n', fig_filename_emf_str);
%     try
%         exportgraphics(fig_handle, fig_filename_emf_str, 'ContentType', 'vector');
%         fprintf('EMF saved.\n');
%     catch ME_export_emf
%         fprintf('Could not save EMF with exportgraphics. Error: %s\n', ME_export_emf.message);
%         fprintf('Attempting to save with saveas...\n');
%         try
%             saveas(fig_handle, fig_filename_emf_str);
%             fprintf('EMF saved with saveas.\n');
%         catch ME_saveas_emf
%             fprintf('Failed to save EMF with saveas. Error: %s\n', ME_saveas_emf.message);
%         end
%     end
% else
%     fprintf('Figure handle invalid. Plot not saved.\n');
% end
% fprintf('Plot generation complete.\n');