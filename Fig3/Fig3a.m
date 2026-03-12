% =========================================================================
% FIGURE 3A: 36 HOURS SPECTOGRAM
% =========================================================================
%% --- 1. Initial Setup ---
%clear; 
%close all; 
%clc; 

%% --- 2. Parameters ---
% EEG Data: File path, and recording start time for each file
eeg_parquet_file_paths = { ... 
    'Resaved-biov-2023-11-01T16_30_00-05_00-2023-11-02T16_30_00-05_00-EEGN03.parquet', ...
    'Resaved-biov-2023-11-02T16_30_00-05_00-2023-11-03T12_45_00-05_00-EEGN03.parquet' ...
};
eeg_recording_start_datetime_strs = { ... 
    '2023-11-01 16:30:00', ... 
    '2023-11-02 16:30:00' ...
};

% Define column with the data in the parquet file
eeg_signal_column_name = 'val'; 

% Define sampling rate
Fs_eeg = 256; 

% Define plotting range
plot_window_start_datetime_str = '2023-11-02 00:00:00'; 
plot_window_end_datetime_str = '2023-11-03 12:00:00'; 
plot_description_text = 'EEG Spectrogram'; 

% Plot parameters
spectrogram_freq_max_hz = 65;
clim_lower_percentile = 55;
clim_upper_percentile = 97;
win_len_sec = 60; 
overlap_percentage = 50;    

% Microvolt parameters
bitres = 17;
gain = 160;  

% Plot settings
figure_position = [100, 100, 1600, 400]; % Adjust height with the 4th value

plot_font_name = 'Arial';
axis_font_size = 9;
axis_line_width = 0.75;

N_window_eeg = round(win_len_sec * Fs_eeg);
N_overlap_eeg = round(N_window_eeg * (overlap_percentage / 100));
N_fft_eeg = max(1024, 2^nextpow2(N_window_eeg));

%% Define Plot Window
try
    effective_plot_start_dt = datetime(plot_window_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
catch ME
    error('Invalid plot_window_start_datetime_str: %s. Error: %s', plot_window_start_datetime_str, ME.message);
end
try
    effective_plot_end_dt = datetime(plot_window_end_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
catch ME
    error('Invalid plot_window_end_datetime_str: %s. Error: %s', plot_window_end_datetime_str, ME.message);
end
fprintf('Target plotting window: %s to %s\n', datestr(effective_plot_start_dt), datestr(effective_plot_end_dt));

%% Load and Concatenate Data

fprintf('Loading and concatenating EEG data from multiple Parquet files...\n');
raw_eeg_signal_full = [];
eeg_time_datetime_full = datetime([], [], [], [], [], [], 'TimeZone', 'local');
if length(eeg_parquet_file_paths) ~= length(eeg_recording_start_datetime_strs)
    error('The number of EEG file paths must match the number of EEG recording start datetimes.');
end

for i_file = 1:length(eeg_parquet_file_paths)
    current_eeg_file_path = eeg_parquet_file_paths{i_file};
    current_eeg_file_start_str = eeg_recording_start_datetime_strs{i_file};
    fprintf('Loading EEG file %d of %d: %s\n', i_file, length(eeg_parquet_file_paths), current_eeg_file_path);
    try
        if isempty(strtrim(current_eeg_file_start_str))
            warning('Empty start datetime string for EEG file %s. Skipping this file.', current_eeg_file_path);
            continue; 
        end
        current_eeg_file_start_dt = datetime(current_eeg_file_start_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', 'local');
        if isnat(current_eeg_file_start_dt) 
            warning('Failed to parse start datetime for EEG file %s: ''%s''. Skipping this file.', current_eeg_file_path, current_eeg_file_start_str);
            continue; 
        end
        
        tbl_eeg_parquet = parquetread(current_eeg_file_path);
        temp_raw_eeg_signal = tbl_eeg_parquet.(eeg_signal_column_name);
        if isempty(temp_raw_eeg_signal)
             warning('No EEG data found in column %s for file %s. Skipping this file.', eeg_signal_column_name, current_eeg_file_path);
            continue;
        end
        if size(temp_raw_eeg_signal, 2) > 1 && size(temp_raw_eeg_signal,1) == 1; temp_raw_eeg_signal = temp_raw_eeg_signal'; end
        if size(temp_raw_eeg_signal, 2) > 1 && size(temp_raw_eeg_signal,1) > 1
            warning('EEG signal in file %s has multiple columns. Using first.', current_eeg_file_path); temp_raw_eeg_signal = temp_raw_eeg_signal(:,1);
        end
        
        num_samples_this_file = length(temp_raw_eeg_signal);
        if num_samples_this_file == 0
            warning('Zero samples in EEG file %s after extraction. Skipping.', current_eeg_file_path);
            continue;
        end
        
        temp_eeg_time_datetime = current_eeg_file_start_dt + seconds((0:num_samples_this_file-1)' / Fs_eeg);
        temp_eeg_time_datetime.TimeZone = 'local'; 
        raw_eeg_signal_full = [raw_eeg_signal_full; temp_raw_eeg_signal]; 
        eeg_time_datetime_full = [eeg_time_datetime_full; temp_eeg_time_datetime]; 
        
        fprintf('EEG data from %s appended.\n', current_eeg_file_path);
    catch ME_eeg_load_loop
        warning('Failed to load or process EEG file %s. Error: %s. Skipping.', current_eeg_file_path, ME_eeg_load_loop.message);
    end
end

if isempty(raw_eeg_signal_full) || isempty(eeg_time_datetime_full) || (isa(eeg_time_datetime_full,'datetime') && all(isnat(eeg_time_datetime_full)))
    error('No EEG data loaded after attempting all files. Check paths, column names, and start times. Ensure datetime strings are valid.');
end

[eeg_time_datetime_full, sort_idx_eeg] = sort(eeg_time_datetime_full);
raw_eeg_signal_full = raw_eeg_signal_full(sort_idx_eeg);
[eeg_time_datetime_full, unique_idx_eeg] = unique(eeg_time_datetime_full);
raw_eeg_signal_full = raw_eeg_signal_full(unique_idx_eeg);
fprintf('All EEG data concatenated. Total samples: %d, Timespan: %s to %s\n', ...
    length(raw_eeg_signal_full), datestr(eeg_time_datetime_full(1)), datestr(eeg_time_datetime_full(end)));
actual_plot_start_dt_eeg_used = eeg_time_datetime_full(1); 
if ~isempty(actual_plot_start_dt_eeg_used); actual_plot_start_dt_eeg_used.TimeZone = 'local';end 

%% Crop the data based on the plotting window
idx_eeg_plot_start = find(eeg_time_datetime_full >= effective_plot_start_dt, 1, 'first');
idx_eeg_plot_end = find(eeg_time_datetime_full <= effective_plot_end_dt, 1, 'last');

if isempty(idx_eeg_plot_start) || isempty(idx_eeg_plot_end) || idx_eeg_plot_start >= idx_eeg_plot_end
    error('No overlapping EEG data for the specified plot window. Check that plot window start/end times are within the span of your concatenated EEG files.');
end

raw_eeg_signal_cropped = raw_eeg_signal_full(idx_eeg_plot_start:idx_eeg_plot_end);
actual_plot_start_dt_eeg_used = eeg_time_datetime_full(idx_eeg_plot_start);
if ~isempty(actual_plot_start_dt_eeg_used); actual_plot_start_dt_eeg_used.TimeZone = 'local';
end 

fprintf('EEG data for plot: %s to %s.\n', datestr(actual_plot_start_dt_eeg_used), datestr(eeg_time_datetime_full(idx_eeg_plot_end)));
val_uv = double(raw_eeg_signal_cropped) * 1e6 / (2^bitres * gain);
fprintf('Cropped EEG Data converted to microvolts.\n');

%% Calculate EEG Spectrogram

fprintf('Calculating EEG spectrogram...\n');
P_db = []; T_spec_datetime = []; F_spec = [];

if isempty(val_uv); warning('val_uv is empty. Skipping spectrogram.');
elseif length(val_uv) < N_window_eeg; warning('EEG for spectrogram (length: %d) shorter than STFT window (%d). Skipping spectrogram.', length(val_uv), N_window_eeg);
else
    [~, F_spec, T_spec_relative_sec, P_spec_data] = spectrogram(val_uv, N_window_eeg, N_overlap_eeg, N_fft_eeg, Fs_eeg, 'psd');
    epsilon = 1e-12; P_db = 10 * log10(P_spec_data + epsilon);
    T_spec_datetime = actual_plot_start_dt_eeg_used + seconds(T_spec_relative_sec);
    if ~isempty(T_spec_datetime); T_spec_datetime.TimeZone = 'local'; end
end

fprintf('EEG Spectrogram calculated.\n');

%% Plot overview
fprintf('Plotting overview...\n');
fig_handle = figure('Color','w'); 
set(fig_handle, 'Position', figure_position);
ax_plot = subplot(1, 1, 1);

if ~isempty(P_db) && ~isempty(T_spec_datetime) && ~isempty(F_spec)
    imagesc(ax_plot, T_spec_datetime, F_spec, P_db); 
    axis(ax_plot, 'xy'); 
    colormap(ax_plot, parula); 
    colorbar(ax_plot);
    
    all_P_db_current_plot = P_db(:); 
    all_P_db_current_plot = all_P_db_current_plot(isfinite(all_P_db_current_plot)); 
    clim_vals_current_plot = [-50 0]; 
    if ~isempty(all_P_db_current_plot)
        clim_vals_current_plot = [prctile(all_P_db_current_plot, clim_lower_percentile), prctile(all_P_db_current_plot, clim_upper_percentile)];
        if clim_vals_current_plot(1) >= clim_vals_current_plot(2)
            if all(all_P_db_current_plot == all_P_db_current_plot(1))
                clim_vals_current_plot = [all_P_db_current_plot(1) - 0.5, all_P_db_current_plot(1) + 0.5];
            else
                clim_vals_current_plot = [clim_vals_current_plot(1)-1, clim_vals_current_plot(1)+1];
            end
        end
    end
    clim(ax_plot, clim_vals_current_plot); 
    ylim(ax_plot, [0 spectrogram_freq_max_hz]);
    
else
    text(0.5, 0.5, 'Spectrogram data not available', 'HorizontalAlignment', 'center', 'FontName', plot_font_name); 
    axis(ax_plot, 'off');
end

set(ax_plot, 'FontName', plot_font_name, 'FontSize', axis_font_size, 'TickDir', 'in', 'LineWidth', axis_line_width, 'Box', 'off');
grid(ax_plot, 'off');

valid_fig_handle_output = ishandle(fig_handle) && strcmp(get(fig_handle,'type'),'figure');
if ~isempty(ax_plot)
    xlim(ax_plot, [effective_plot_start_dt, effective_plot_end_dt]);
    tick_format_output = 'dd-mmm HH';
    ax_plot.XTickLabelRotation = 30;
    datetick(ax_plot, 'x', tick_format_output, 'keeplimits');
end


% Remove the axis value labels but keep the tick marks
set(ax_plot, 'XTickLabel', []);
set(ax_plot, 'YTickLabel', []);

% Save Figure (optional)
plot_filename_base_save = 'EEG_Spectrogram_Overview';
if ~isempty(plot_description_text); plot_filename_base_save = matlab.lang.makeValidName(strrep(plot_description_text, ' ', '_')); end
dt_start_str_save = datestr(effective_plot_start_dt, 'yyyymmdd_HHMMSS'); 
plot_filename_no_ext_save = sprintf('%s_Ch%s_%s', plot_filename_base_save, strrep(eeg_signal_column_name,'_','-'), dt_start_str_save);

if valid_fig_handle_output
    % Save .fig file (interactive MATLAB figure)
    fig_filename_save = [plot_filename_no_ext_save, '.fig'];
    fprintf('Saving interactive plot to: %s\n', fig_filename_save);
    savefig(fig_handle, fig_filename_save); 
    fprintf('Interactive plot saved.\n');
    
    % Save .png file (high-resolution raster image)
    png_filename_save = [plot_filename_no_ext_save, '.png'];
    fprintf('Saving high-resolution PNG to: %s\n', png_filename_save);
    try
        exportgraphics(fig_handle, png_filename_save, 'Resolution', 300);
        fprintf('High-resolution PNG saved.\n');
    catch ME_export_save
        fprintf('Could not save PNG with exportgraphics. Error: %s\nAttempting saveas...\n', ME_export_save.message);
        try
            saveas(fig_handle, png_filename_save);
            fprintf('PNG saved with saveas.\n');
        catch ME_saveas_save
            fprintf('Failed to save PNG with saveas. Error: %s\n', ME_saveas_save.message);
        end
    end
    
    % Save EMF (optional)
    emf_filename_save = [plot_filename_no_ext_save, '.emf'];
    fprintf('Saving vector EMF to: %s\n', emf_filename_save);
    try
        % To ensure the saved EMF respects the aspect ratio from 'figure_position',
        % set the 'PaperPositionMode' to 'auto'. This tells MATLAB to 
        % use the on-screen figure dimensions for printing/saving.
        set(fig_handle, 'PaperPositionMode', 'auto');
        

        % Use the '-dmeta' driver for EMF and the '-painters' renderer for a
        % clean, true-vector output.
        print(fig_handle, emf_filename_save, '-dmeta', '-painters');
        
        fprintf('Vector EMF saved.\n');
    catch ME_print_emf
        fprintf('Failed to save EMF with the print command. Error: %s\n', ME_print_emf.message);
    end
else
    fprintf('Figure handle invalid. Plot not saved.\n');
end
fprintf('Overview plot generated and saved.\n');