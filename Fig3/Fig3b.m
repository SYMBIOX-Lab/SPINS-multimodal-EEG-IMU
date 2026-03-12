% =========================================================================
% FIGURE 3B: POST-ICTAL SUPPRESSION
% =========================================================================

%% --- 1. Initial Setup ---
% clear;
% close all;
% clc;
%% --- 2. Parameters ---

% EEG Data Parameters
eeg_recording_start_datetime_str = '2023-10-03 15:30:00'; 
eeg_parquet_file_path = 'Resaved-biov-2023-10-03T15_30_00-05_00-2023-10-04T12_00_00-05_00-EEGSY08.parquet';
eeg_signal_column_name = 'val'; 

% Sampling frequency
Fs_eeg = 256; 

% Plotting window and seizure onset
plot_window_start_datetime_str = '2023-10-04 06:50:00'; 
plot_window_end_datetime_str   = '2023-10-04 07:05:00';      
seizure_description_text = 'Post-Ictal Suppression (Sz 10-4 06-55)'; 

% Filtering parameters
apply_notch_filter = true;
notch_freq_hz = 60;          % Notch filter frequency (Hz) for powerline noise
notch_bandwidth_hz = 2;      % Bandwidth for the notch filter in Hz
apply_bandpass_filter = true;
bandpass_order = 4;          % 4th order Butterworth filter
bandpass_freqs_hz = [0.5, 70]; % Passband frequencies in Hz [low_cutoff, high_cutoff]
publication_mode = false;      % Set to false for a larger, more detailed review plot
plot_spectrogram_only = true; % Set to true to ONLY plot the spectrogram

% Plotting parameters and content control
if publication_mode
    target_pub_width_inches = 3.5;
    target_pub_height_inches = 1.5;
    figure_width_pixels = target_pub_width_inches * 150; 
    figure_height_pixels = target_pub_height_inches * 150;
    figure_position = [100, 50, figure_width_pixels, figure_height_pixels];
    left_margin = 0.18; right_margin = 0.22; bottom_margin = 0.20; top_margin = 0.15;
    data_line_width = 0.5; axis_line_width = 0.25;
else % Regular plotting mode (large display)
    figure_position = [100, 50, 1200, 600];
    left_margin = 0.10; right_margin = 0.12; bottom_margin = 0.15; top_margin = 0.10;
    data_line_width = 1.2; axis_line_width = 0.75;
end

plot_font_name = 'Arial';
axis_font_size = 12;    % For axis numbers/ticks & colorbar ticks
label_font_size = 12;   % For Colorbar label

% Determine which plots to actually render based on flags
cfg_show_spectrogram = plot_spectrogram_only;
% Spectogram Parameters
spectrogram_freq_max_hz = 65; clim_lower_percentile = 65; clim_upper_percentile = 97;
win_len_sec = 1.5; overlap_percentage = 80;

% Microovolt conversion parameters
bitres = 17; gain = 160;

N_window = round(win_len_sec * Fs_eeg);
N_overlap = round(N_window * (overlap_percentage / 100));
N_fft = max(2048, 2^nextpow2(N_window));

%% Load and Prepare Data

% Load EEG data for the channel
fprintf('Loading EEG data from Parquet file: %s\n', eeg_parquet_file_path);
try
    tbl_eeg_parquet = parquetread(eeg_parquet_file_path);
    raw_eeg_signal = tbl_eeg_parquet.(eeg_signal_column_name);
    fprintf('EEG data loaded successfully for channel: %s.\n', eeg_signal_column_name);
catch ME_eeg_load
    error('Failed to load EEG data: %s', ME_eeg_load.message);
end

% Check if signal is filled
if isempty(raw_eeg_signal); error('Raw EEG signal is empty.'); end
if size(raw_eeg_signal, 2) > 1; raw_eeg_signal = raw_eeg_signal(:,1); end

try eeg_file_start_dt = datetime(eeg_recording_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
catch ME; error('Invalid eeg_recording_start_datetime_str: %s', ME.message); end

% Implement plot start and end datetime
effective_plot_start_dt = datetime(plot_window_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
effective_plot_end_dt = datetime(plot_window_end_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');

% If datetime outside of given plotting window, display error.
if effective_plot_start_dt >= effective_plot_end_dt; error('Plot window start time must be before end time.'); end

offset_plot_start_sec_from_eeg_file_start = seconds(effective_plot_start_dt - eeg_file_start_dt);
offset_plot_end_sec_from_eeg_file_start   = seconds(effective_plot_end_dt - eeg_file_start_dt);
idx_eeg_start_crop = round(offset_plot_start_sec_from_eeg_file_start * Fs_eeg) + 1;
idx_eeg_end_crop   = round(offset_plot_end_sec_from_eeg_file_start * Fs_eeg) + 1;

if idx_eeg_start_crop < 1; idx_eeg_start_crop = 1; end
if idx_eeg_end_crop > length(raw_eeg_signal); idx_eeg_end_crop = length(raw_eeg_signal); end

raw_eeg_signal_cropped = raw_eeg_signal(idx_eeg_start_crop:idx_eeg_end_crop);
val_uv = double(raw_eeg_signal_cropped) * 1e6 / (2^bitres * gain);

%% Apply Filters
if apply_notch_filter || apply_bandpass_filter; fprintf('Applying filters...\n'); end

if apply_notch_filter
    fprintf(' -> Applying %.1f Hz notch filter.\n', notch_freq_hz);
    [b, a] = butter(2, [(notch_freq_hz-notch_bandwidth_hz/2) (notch_freq_hz+notch_bandwidth_hz/2)]/(Fs_eeg/2), 'stop');
    val_uv = filtfilt(b, a, val_uv);
end

if apply_bandpass_filter
    fprintf(' -> Applying %.1f-%.1f Hz bandpass filter.\n', bandpass_freqs_hz(1), bandpass_freqs_hz(2));
    [b, a] = butter(bandpass_order, bandpass_freqs_hz/(Fs_eeg/2), 'bandpass');
    val_uv = filtfilt(b, a, val_uv);
end

%% Calculate Spectrogram

[~, F_spec, T_spec_relative_sec, P_spec_data] = spectrogram(val_uv, N_window, N_overlap, N_fft, Fs_eeg, 'psd');
P_db = 10 * log10(P_spec_data + 1e-12);
T_spec_datetime = effective_plot_start_dt + seconds(T_spec_relative_sec);

if ~isempty(T_spec_datetime); T_spec_datetime.TimeZone = 'local'; end

%% Plot Selected Data

fprintf('Plotting data...\n');
fig_handle = figure('Color','w');
set(fig_handle, 'Position', figure_position);
plot_pos = [left_margin, bottom_margin, 1-left_margin-right_margin, 1-bottom_margin-top_margin];
spectrogram_ax = axes('Position', plot_pos);
imagesc(spectrogram_ax, T_spec_datetime, F_spec, P_db); 
axis(spectrogram_ax, 'xy'); colormap(spectrogram_ax, parula);
all_P_db_vals = P_db(isfinite(P_db));

if ~isempty(all_P_db_vals)
    clim_vals = [prctile(all_P_db_vals, clim_lower_percentile), prctile(all_P_db_vals, clim_upper_percentile)];
    if clim_vals(1) < clim_vals(2); clim(spectrogram_ax, clim_vals); end
end

ylim(spectrogram_ax, [0 spectrogram_freq_max_hz]);

set(spectrogram_ax, 'FontName', plot_font_name, 'FontSize', axis_font_size, 'TickLength', [0 0], 'LineWidth', axis_line_width, 'Box', 'on');
if effective_plot_start_dt < effective_plot_end_dt; set(spectrogram_ax, 'XLim', [effective_plot_start_dt, effective_plot_end_dt]); end

% Add Colorbar
cb_pos = spectrogram_ax.Position;
colorbar_left = cb_pos(1) + cb_pos(3) + 0.015;
cb = colorbar(spectrogram_ax, 'Position', [colorbar_left, cb_pos(2), 0.03, cb_pos(4)]);
cb.Label.String = 'Power (dB/Hz)';
cb.Label.FontName = plot_font_name; cb.Label.FontSize = label_font_size;
set(cb, 'FontName', plot_font_name, 'FontSize', axis_font_size);

% Setting dynamic ticks
update_time_ticks(spectrogram_ax);
addlistener(spectrogram_ax, 'XLim', 'PostSet', @(src, event) update_time_ticks(event.AffectedObject));

%% Save Plot (optional)
if publication_mode
    fprintf('Setting figure properties for %0.1fin x %0.1fin publication output.\n', target_pub_width_inches, target_pub_height_inches);
    set(fig_handle, 'PaperUnits', 'inches'); set(fig_handle, 'PaperSize', [target_pub_width_inches, target_pub_height_inches]);
    set(fig_handle, 'PaperPositionMode', 'manual'); set(fig_handle, 'PaperPosition', [0, 0, target_pub_width_inches, target_pub_height_inches]);
end

plot_filename_base = 'PlotOutput';

if ~isempty(seizure_description_text); plot_filename_base = matlab.lang.makeValidName(strrep(seizure_description_text, ' ', '_')); end
try dt_start_str = datestr(datetime(plot_window_start_datetime_str, 'TimeZone', 'local'), 'yyyymmdd_HHMMSS');
    plot_filename_no_ext = sprintf('%s_Ch%s_%s', plot_filename_base, strrep(eeg_signal_column_name,'_','-'), dt_start_str);
catch; plot_filename_no_ext = [plot_filename_base, '_Ch', strrep(eeg_signal_column_name,'_','-')]; end

if ishandle(fig_handle)
    % Save .png file (optional)
    fig_filename_png = [plot_filename_no_ext, '.png'];
    fprintf('Saving PNG to: %s\n', fig_filename_png);
    try exportgraphics(fig_handle, fig_filename_png, 'Resolution', 300); fprintf('PNG saved.\n');
    catch ME_export; fprintf('Could not save PNG with exportgraphics: %s\nAttempting print...\n', ME_export.message);
        try print(fig_handle, fig_filename_png, '-dpng', '-r300'); fprintf('PNG saved with print -dpng.\n');
        catch ME_print; fprintf('Failed to save PNG with print: %s\n', ME_print.message); end
    end

    % Save .emf file (optional)
    fig_filename_emf = [plot_filename_no_ext, '.emf'];
    fprintf('Saving EMF to: %s\n', fig_filename_emf);
    try 
        exportgraphics(fig_handle, fig_filename_emf, 'ContentType', 'vector');
        fprintf('EMF saved.\n');
    catch ME_export_emf
        fprintf('Could not save EMF with exportgraphics: %s\nAttempting saveas...\n', ME_export_emf.message);
        try
            saveas(fig_handle, fig_filename_emf);
            fprintf('EMF saved with saveas.\n');
        catch ME_saveas_emf
            fprintf('Failed to save EMF with saveas: %s\n', ME_saveas_emf.message);
        end
    end
else; fprintf('Figure handle invalid or no plots rendered. Plot not saved.\n'); end
fprintf('Plots generated.\n');


% Local Helper Function
function update_time_ticks(ax)
    % Get the current x-axis limits
    xlim_vals = get(ax, 'XLim');
    

    % The xlim_vals are already datetime objects because the axis was
    % created with them. No conversion is needed.
    start_time = xlim_vals(1);
    end_time = xlim_vals(2);
    
    % Calculate the duration of the visible window
    duration_seconds = seconds(end_time - start_time);
    
    % Choose the best format based on the duration
    if duration_seconds <= 2
        tick_format = 'HH:MM:SS.FFF'; % Milliseconds
    elseif duration_seconds <= 90
        tick_format = 'HH:MM:SS';     % Seconds
    elseif duration_seconds <= (2 * 60 * 60)
        tick_format = 'HH:MM';        % Minutes
    else
        tick_format = 'dd-HH:MM';     % Hours/Days
    end
    
    % Apply the new format
    datetick(ax, 'x', tick_format, 'keeplimits');
    ax.XTickLabelRotation = 30;
end