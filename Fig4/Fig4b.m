% =========================================================================
% FIGURE 4B: MYOCLONIC EVENT
% =========================================================================
% clear, close all, clc;

%% Parameters

% Import EEG Data: recording start time, file path, column, sampling
% frequency
eeg_recording_start_datetime_str = '2024-07-09 12:15:00';
eeg_parquet_file_path = 'Resaved-tk_micz-2024-07-09T17_15_00-05_00-2024-07-10T17_15_00-05_00-EEG0702.parquet';
eeg_signal_column_name = 'z';
Fs_eeg = 256;

% Import IMU Data: recording start time, file path, columns, sampling
% frequency
imu_parquet_file_path = 'Resaved-tk_xyz_secondary-2024-07-09T17_15_00-05_00-2024-07-10T17_15_00-05_00-EEG0702.parquet';
imu_timestamp_column_name = 't';
imu_x_col_name = 'x'; imu_y_col_name = 'y'; imu_z_col_name = 'z';
imu_recording_start_datetime_str = '2024-07-09 12:15:00';

% Define plotting window
plot_window_start_datetime_str = '2024-07-10 07:17:00';
plot_window_end_datetime_str   = '2024-07-10 08:17:00';

% Seizure onset time (kept for data context, not plotted)
seizure_onset_datetime_strs = {'2024-07-10 07:47:00'}; 

% Output image description text (optional)
seizure_description_text = 'Spec_IMUxyz_LegendSW_3.5x1.5_Pub';

% Set timezone
user_local_timezone = 'America/Chicago'; 

% Plot Parameters
show_spectrogram = true;
show_raw_eeg = false;
show_imu_magnitude = false;
show_imu_xyz = true;
publication_ready = true;

if publication_ready
    target_pub_width_inches = 3.5;
    target_pub_height_inches = 1.25; % Shorter plot
    figure_width_pixels = target_pub_width_inches * 150;
    figure_height_pixels = target_pub_height_inches * 150;
    figure_position = [100, 50, figure_width_pixels, figure_height_pixels];
    plot_font_name = 'Arial';
    axis_font_size = 5;
    label_font_size = 6;
    data_line_width = 0.5;
    axis_line_width = 0.25;
    left_margin = 0.15;
    right_margin = 0.22;
    bottom_margin = 0.18;
    top_margin = 0.05;
    vertical_spacing = 0.05; % amount of white space 
else
    
    figure_position = [100, 50, 1200, 950]; % size of plot
    plot_font_name = 'Arial';
    axis_font_size = 9;
    label_font_size = 10;
    data_line_width = 1.2;
    axis_line_width = 0.75;
    left_margin = 0.08; right_margin = 0.12; bottom_margin = 0.08; top_margin = 0.05;
    vertical_spacing = 0.03; 
end

% Spectrogram Parameters (EEG)
spectrogram_freq_max_hz = 20;
clim_lower_percentile = 65;
clim_upper_percentile = 97;
win_len_sec = 1.5;
overlap_percentage = 80;

% Microvolt conversion parameters
bitres = 17; gain = 160;

% Set axis limits
spectrogram_plot_ylim = [0 65];
imu_xyz_plot_ylim     = [-5000 5000];

N_window = round(win_len_sec * Fs_eeg);
N_overlap = round(N_window * (overlap_percentage / 100));
N_fft = max(2048, 2^nextpow2(N_window));

% Load EEG Data
fprintf('Loading EEG data from Parquet file: %s\n', eeg_parquet_file_path);
try
    tbl_eeg_parquet = parquetread(eeg_parquet_file_path);
    raw_eeg_signal = tbl_eeg_parquet.(eeg_signal_column_name);
    fprintf('EEG data loaded successfully for channel: %s.\n', eeg_signal_column_name);
catch ME_eeg_load
    error('Failed to load EEG data: %s', ME_eeg_load.message);
end

if isempty(raw_eeg_signal); error('Raw EEG signal is empty.'); end
if size(raw_eeg_signal, 2) > 1 && size(raw_eeg_signal,1) == 1; raw_eeg_signal = raw_eeg_signal';
elseif size(raw_eeg_signal, 2) > 1 && size(raw_eeg_signal,1) > 1
    warning('EEG signal has multiple columns. Using the first column only.'); raw_eeg_signal = raw_eeg_signal(:,1);
end

% Load IMU Data
can_plot_imu = false;
if show_imu_xyz
    fprintf('Loading IMU data from Parquet file: %s\n', imu_parquet_file_path);
    imu_time_datetime = NaT(0,0);
    imu_x_data = []; imu_y_data = []; imu_z_data = [];
    try
        tbl_imu_parquet = parquetread(imu_parquet_file_path);
        imu_timestamps_raw = tbl_imu_parquet.(imu_timestamp_column_name);
        imu_x_data_raw = tbl_imu_parquet.(imu_x_col_name);
        imu_y_data_raw = tbl_imu_parquet.(imu_y_col_name);
        imu_z_data_raw = tbl_imu_parquet.(imu_z_col_name);
        if isa(imu_timestamps_raw, 'datetime')
            imu_time_datetime = imu_timestamps_raw;
            if ~isempty(imu_time_datetime)
                if isempty(imu_time_datetime(1).TimeZone)
                    imu_time_datetime.TimeZone = user_local_timezone;
                else
                    imu_time_datetime.TimeZone = user_local_timezone;
                end
            end
        elseif isnumeric(imu_timestamps_raw) && ~isempty(imu_recording_start_datetime_str)
            imu_start_dt = datetime(imu_recording_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', user_local_timezone);
            imu_time_datetime = imu_start_dt + milliseconds(imu_timestamps_raw);
        else; error('Unhandled IMU timestamp format or missing IMU recording start string for numeric timestamps.'); end

        imu_x_data = double(imu_x_data_raw(:));
        imu_y_data = double(imu_y_data_raw(:));
        imu_z_data = double(imu_z_data_raw(:));
        if size(imu_time_datetime,2) > 1 && size(imu_time_datetime,1) == 1; imu_time_datetime = imu_time_datetime'; end
        fprintf('IMU data loaded and processed.\n');
        can_plot_imu = true;
    catch ME_imu_load
        warning('Failed to load/process IMU data: %s. IMU plots will be skipped.', ME_imu_load.message);
        can_plot_imu = false;
    end
else
    fprintf('IMU data loading skipped as IMU XYZ plot is disabled.\n');
end
if ~can_plot_imu
    show_imu_xyz = false;
end

%% Implement Plot Window and Time Alignment

try eeg_file_start_dt = datetime(eeg_recording_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', user_local_timezone);
catch ME; error('Invalid eeg_recording_start_datetime_str: %s', ME.message); end
effective_plot_start_dt = datetime(plot_window_start_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', user_local_timezone);
effective_plot_end_dt = datetime(plot_window_end_datetime_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', user_local_timezone);
if effective_plot_start_dt >= effective_plot_end_dt; error('Plot window start time must be before end time.'); end
offset_plot_start_sec_from_eeg_file_start = seconds(effective_plot_start_dt - eeg_file_start_dt);
offset_plot_end_sec_from_eeg_file_start   = seconds(effective_plot_end_dt - eeg_file_start_dt);
idx_eeg_start_crop = round(offset_plot_start_sec_from_eeg_file_start * Fs_eeg) + 1;
idx_eeg_end_crop   = round(offset_plot_end_sec_from_eeg_file_start * Fs_eeg) + 1;
if idx_eeg_start_crop < 1
    idx_eeg_start_crop = 1;
    effective_plot_start_dt = eeg_file_start_dt;
    if ~isempty(effective_plot_start_dt); effective_plot_start_dt.TimeZone = user_local_timezone; end
    warning('Plot window starts before EEG data. Adjusting plot start to EEG file start: %s', datestr(effective_plot_start_dt));
end

if idx_eeg_end_crop > length(raw_eeg_signal)
    idx_eeg_end_crop = length(raw_eeg_signal);
    effective_plot_end_dt = eeg_file_start_dt + seconds((idx_eeg_end_crop-1)/Fs_eeg);
    if ~isempty(effective_plot_end_dt); effective_plot_end_dt.TimeZone = user_local_timezone; end
    warning('Plot window ends after EEG data. Adjusting plot end to EEG file end: %s', datestr(effective_plot_end_dt));
end

if idx_eeg_start_crop >= idx_eeg_end_crop || isempty(raw_eeg_signal) || idx_eeg_start_crop > length(raw_eeg_signal) || idx_eeg_end_crop < 1 ; error('No valid EEG data range for plot window after adjustments.'); end
raw_eeg_signal_cropped = raw_eeg_signal(idx_eeg_start_crop:idx_eeg_end_crop);

fprintf('EEG data cropped to plot window: %s to %s.\n', datestr(effective_plot_start_dt), datestr(effective_plot_end_dt));

if isempty(raw_eeg_signal_cropped); error('EEG signal is empty after cropping.'); end

time_vector_eeg_datetime = effective_plot_start_dt + seconds((0:(length(raw_eeg_signal_cropped)-1))' / Fs_eeg);

if ~isempty(time_vector_eeg_datetime); time_vector_eeg_datetime.TimeZone = user_local_timezone; end
% Conversion to microvolts
val_uv = double(raw_eeg_signal_cropped) * 1e6 / (2^bitres * gain);

%% Calculate EEG Spectrogram

P_db = []; T_spec_datetime = []; F_spec = []; has_spectrogram_data = false;

if show_spectrogram
    fprintf('Calculating EEG spectrogram...\n');
    if isempty(val_uv); warning('val_uv is empty. Skipping spectrogram calculation.');
    elseif length(val_uv) < N_window; warning('EEG for spectrogram too short. Skipping calculation.');
    else
        [S_temp, F_spec, T_spec_relative_sec, P_spec_data] = spectrogram(val_uv, N_window, N_overlap, N_fft, Fs_eeg, 'psd');
        epsilon = 1e-12;
        P_db = 10 * log10(P_spec_data + epsilon);
        T_spec_datetime = effective_plot_start_dt + seconds(T_spec_relative_sec);
        if ~isempty(T_spec_datetime); T_spec_datetime.TimeZone = user_local_timezone; end
        fprintf('EEG Spectrogram calculated.\n');
        has_spectrogram_data = ~isempty(P_db);
    end

else
    fprintf('Spectrogram calculation skipped as per configuration.\n');
end

%% Seizure Onset Datetime Objects

fprintf('Preparing seizure onset datetime objects (lines not plotted)...\n');
seizure_onset_dt_objs = NaT(0,0, 'TimeZone', user_local_timezone);
if iscell(seizure_onset_datetime_strs) && ~isempty(seizure_onset_datetime_strs)
    for k_seizure = 1:length(seizure_onset_datetime_strs)
        current_seizure_str = strtrim(seizure_onset_datetime_strs{k_seizure});
        if ischar(current_seizure_str) && ~isempty(current_seizure_str)
            try
                dt_obj = datetime(current_seizure_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', user_local_timezone);
                seizure_onset_dt_objs(end+1,1) = dt_obj;
            catch ME_seizure_onset
                warning('Invalid format or value for seizure onset string: "%s". Error: %s. Skipping this entry.', current_seizure_str, ME_seizure_onset.message);
            end
        elseif ~isempty(current_seizure_str)
            warning('Invalid (non-string or empty) entry for seizure onset at cell index %d. Skipping this entry.', k_seizure);
        end
    end
end

if ~isempty(seizure_onset_dt_objs); fprintf('%d Seizure onset datetime object(s) prepared.\n', length(seizure_onset_dt_objs));
else; fprintf('No valid seizure onset times provided or parsed.\n'); end

%% Plot Selected Data

fig_handle = figure('Color','w');
set(fig_handle, 'Position', figure_position);
plot_positions_map = containers.Map('KeyType','char','ValueType','any');
temp_ax_list = {};
plot_width_norm = 1 - left_margin - right_margin;
total_plot_height_norm = 1 - bottom_margin - top_margin;
if total_plot_height_norm <=0 || plot_width_norm <=0
    close(fig_handle);
    error("Calculated plot dimensions are zero or negative. Check margins.");
end

active_plot_keys = {};

if show_spectrogram && has_spectrogram_data; active_plot_keys{end+1} = 'spectrogram'; end
if show_imu_xyz && can_plot_imu; active_plot_keys{end+1} = 'imu_xyz'; end

num_render_plots = length(active_plot_keys);
if num_render_plots == 0
    warning('No data to plot.');
    ax_empty = axes('Position', [0.1 0.1 0.8 0.8]);
    text(0.5, 0.5, 'No data selected or available for plotting.', 'Parent', ax_empty, 'HorizontalAlignment', 'center');
    axis(ax_empty, 'off');
else
    plot_height_each_norm = (total_plot_height_norm - (num_render_plots - 1) * vertical_spacing) / num_render_plots;
    if plot_height_each_norm <=0 ; close(fig_handle); error("Calculated subplot height is zero or negative. Adjust margins/spacing."); end

    current_bottom = bottom_margin;
    plot_order = {};
    if show_imu_xyz && can_plot_imu; plot_order{end+1} = 'imu_xyz'; end
    if show_spectrogram && has_spectrogram_data; plot_order{end+1} = 'spectrogram'; end
    for i = 1:length(plot_order)
        key = plot_order{i};
        plot_positions_map(key) = [left_margin, current_bottom, plot_width_norm, plot_height_each_norm];
        current_bottom = current_bottom + plot_height_each_norm + vertical_spacing;
    end

    spectrogram_ax = []; imu_xyz_ax = [];
    if show_spectrogram && has_spectrogram_data && isKey(plot_positions_map, 'spectrogram')
        spectrogram_ax = axes('Position', plot_positions_map('spectrogram'));
        imagesc(spectrogram_ax, T_spec_datetime, F_spec, P_db);
        axis(spectrogram_ax, 'xy'); colormap(spectrogram_ax, parula);
        all_P_db_plot_vals = P_db(:); all_P_db_plot_vals = all_P_db_plot_vals(isfinite(all_P_db_plot_vals));
        clim_vals_spec_plot = prctile(all_P_db_plot_vals, [clim_lower_percentile, clim_upper_percentile]);
        if diff(clim_vals_spec_plot) == 0; clim_vals_spec_plot(2) = clim_vals_spec_plot(1) + 1; end
        if ~any(isnan(clim_vals_spec_plot)) && ~any(isinf(clim_vals_spec_plot)); clim(spectrogram_ax, clim_vals_spec_plot); end

        if ~isempty(spectrogram_plot_ylim); ylim(spectrogram_ax, spectrogram_plot_ylim); else; ylim(spectrogram_ax, [0 spectrogram_freq_max_hz]); end

        spectrogram_ax.YAxis.Visible = 'on';
        set(spectrogram_ax, 'FontName', plot_font_name, 'FontSize', axis_font_size, 'TickDir', 'in', 'LineWidth', axis_line_width, 'Box', 'off');
        set(spectrogram_ax, 'YTickLabel', {});
        temp_ax_list{end+1} = spectrogram_ax;
    end

    if show_imu_xyz && can_plot_imu && isKey(plot_positions_map, 'imu_xyz')
        imu_xyz_ax = axes('Position', plot_positions_map('imu_xyz'));
        imu_plot_indices_crop = imu_time_datetime >= effective_plot_start_dt & imu_time_datetime <= effective_plot_end_dt;
        imu_time_datetime_cropped_plot = imu_time_datetime(imu_plot_indices_crop);
        imu_x_cropped_plot = imu_x_data(imu_plot_indices_crop);
        imu_y_cropped_plot = imu_y_data(imu_plot_indices_crop);
        imu_z_cropped_plot = imu_z_data(imu_plot_indices_crop);
        if ~isempty(imu_time_datetime_cropped_plot)
            hold(imu_xyz_ax, 'on');
            plot(imu_xyz_ax, imu_time_datetime_cropped_plot, imu_x_cropped_plot, 'DisplayName', 'X', 'LineWidth', data_line_width);
            plot(imu_xyz_ax, imu_time_datetime_cropped_plot, imu_y_cropped_plot, 'DisplayName', 'Y', 'LineWidth', data_line_width);
            plot(imu_xyz_ax, imu_time_datetime_cropped_plot, imu_z_cropped_plot, 'DisplayName', 'Z', 'LineWidth', data_line_width);
            hold(imu_xyz_ax, 'off');
            lgd = legend(imu_xyz_ax, 'show', 'Location', 'southwest', 'FontSize', axis_font_size, 'FontName', plot_font_name);
            set(lgd, 'Box', 'off', 'Units', 'normalized');
            if publication_ready; lgd.ItemTokenSize = [10, 5]; end
            if ~isempty(imu_xyz_plot_ylim); ylim(imu_xyz_ax, imu_xyz_plot_ylim); else; axis(imu_xyz_ax,'tight'); end
        else
            text(0.5,0.5,'No IMU XYZ data in window','HorizontalAlignment','center','FontName',plot_font_name, 'Parent', imu_xyz_ax, 'FontSize', label_font_size);
            axis(imu_xyz_ax,'off');
        end

        imu_xyz_ax.YAxis.Visible = 'off';
        set(imu_xyz_ax, 'FontName', plot_font_name, 'FontSize', axis_font_size, 'TickDir', 'out', 'LineWidth', axis_line_width, 'Box', 'off');
        temp_ax_list{end+1} = imu_xyz_ax;
    end

    valid_ax_to_link_plot = [temp_ax_list{:}];
    valid_ax_to_link_plot = valid_ax_to_link_plot(isgraphics(valid_ax_to_link_plot));

    if length(valid_ax_to_link_plot) > 1
        linkaxes(valid_ax_to_link_plot, 'x');
    end

    if ~isempty(valid_ax_to_link_plot)
         xlim(valid_ax_to_link_plot(1), [effective_plot_start_dt, effective_plot_end_dt]);
    end

    if show_spectrogram && has_spectrogram_data && isgraphics(spectrogram_ax)
        cb_pos = spectrogram_ax.Position;
        colorbar_left = cb_pos(1) + cb_pos(3) + 0.015;
        colorbar_bottom = cb_pos(2);
        colorbar_width = 0.02;
        colorbar_height = cb_pos(4);
        if (colorbar_left + colorbar_width) > (1-right_margin/4)
            colorbar_left = (1-right_margin/2) - colorbar_width;
            if publication_ready; colorbar_width = max(0.02, right_margin*0.3); end
        end

        cb = colorbar(spectrogram_ax, 'Position', [colorbar_left, colorbar_bottom, colorbar_width, colorbar_height]);
        set(cb, 'FontName', plot_font_name, 'FontSize', axis_font_size);
    end

    if ~isempty(valid_ax_to_link_plot)
        plot_duration_hours_tick = hours(effective_plot_end_dt - effective_plot_start_dt);
        if plot_duration_hours_tick <= (15/60); tick_format_plot = 'HH:MM:SS';
        elseif plot_duration_hours_tick <= 2; tick_format_plot = 'HH:MM';
        else; tick_format_plot = 'dd-HH:MM'; end

        bottom_most_ax = [];
        if show_imu_xyz && can_plot_imu && isgraphics(imu_xyz_ax)
            bottom_most_ax = imu_xyz_ax;
        elseif show_spectrogram && has_spectrogram_data && isgraphics(spectrogram_ax)
            bottom_most_ax = spectrogram_ax;
        end

        if ~isempty(bottom_most_ax)
            bottom_most_ax.XTickLabelRotation = 30;
        end

        for i_ax_tick_loop_idx_val = 1:length(valid_ax_to_link_plot)
            ax_handle_tick_plot = valid_ax_to_link_plot(i_ax_tick_loop_idx_val);
            if ~isgraphics(ax_handle_tick_plot); continue; end

            if ax_handle_tick_plot == bottom_most_ax
                 datetick(ax_handle_tick_plot, 'x', tick_format_plot, 'keeplimits');
                 ax_handle_tick_plot.XAxis.Visible = 'on';
                 ax_handle_tick_plot.XTickLabel = {};
            else
                 ax_handle_tick_plot.XAxis.Visible = 'off';
            end
        end
    end
end

% %% Save Plot (Optional)
% if publication_ready && num_render_plots > 0
%     fprintf('Setting figure properties for %0.2fin x %0.2fin publication output.\n', target_pub_width_inches, target_pub_height_inches);
%     set(fig_handle, 'PaperUnits', 'inches');
%     set(fig_handle, 'PaperSize', [target_pub_width_inches, target_pub_height_inches]);
%     set(fig_handle, 'PaperPositionMode', 'manual');
%     set(fig_handle, 'PaperPosition', [0, 0, target_pub_width_inches, target_pub_height_inches]);
% end
% 
% plot_filename_base_final = 'PlotOutput_FinalMinimal_V6_LegendSW';
% if ~isempty(seizure_description_text)
%     plot_filename_base_final = matlab.lang.makeValidName(strrep(seizure_description_text, ' ', '_'));
% end
% 
% if ~isempty(plot_window_start_datetime_str)
%     try dt_start_str_for_file_final = datestr(datetime(plot_window_start_datetime_str, 'TimeZone', user_local_timezone), 'yyyymmdd_HHMMSS');
%         plot_filename_no_ext_final = sprintf('%s_Ch%s_%s', plot_filename_base_final, strrep(eeg_signal_column_name,'_','-'), dt_start_str_for_file_final);
%     catch; plot_filename_no_ext_final = [plot_filename_base_final, '_Ch', strrep(eeg_signal_column_name,'_','-')]; end
% 
% else; plot_filename_no_ext_final = [plot_filename_base_final, '_Ch', strrep(eeg_signal_column_name,'_','-')]; end
% 
% if ishandle(fig_handle) && strcmp(get(fig_handle,'type'),'figure') && num_render_plots > 0
%     if ~publication_ready
%         fig_filename_fig_final = [plot_filename_no_ext_final, '.fig'];
%         fprintf('Saving interactive plot to: %s\n', fig_filename_fig_final);
%         savefig(fig_handle, fig_filename_fig_final); fprintf('Interactive plot saved.\n');
%     end
% 
%     fig_filename_png_final = [plot_filename_no_ext_final, '.png'];
%     fprintf('Saving PNG to: %s\n', fig_filename_png_final);
%     try exportgraphics(fig_handle, fig_filename_png_final, 'Resolution', 300); fprintf('PNG saved.\n');
%     catch ME_export; fprintf('Could not save PNG with exportgraphics: %s\nAttempting print...\n', ME_export.message);
%         try print(fig_handle, fig_filename_png_final, '-dpng', '-r300'); fprintf('PNG saved with print -dpng.\n');
%         catch ME_print; fprintf('Failed to save PNG with print: %s\n', ME_print.message); end
%     end
% 
%     % MODIFIED: Save .emf file
%     fig_filename_emf_final = [plot_filename_no_ext_final, '.emf'];
%     fprintf('Saving EMF to: %s\n', fig_filename_emf_final);
%     try
%         exportgraphics(fig_handle, fig_filename_emf_final, 'ContentType', 'vector');
%         fprintf('EMF saved.\n');
%     catch ME_export_emf
%         fprintf('Could not save EMF with exportgraphics: %s\nAttempting saveas...\n', ME_export_emf.message);
%         try
%             saveas(fig_handle, fig_filename_emf_final);
%             fprintf('EMF saved with saveas.\n');
%         catch ME_saveas_emf
%             fprintf('Failed to save EMF with saveas. Error: %s\n', ME_saveas_emf.message);
%         end
%     end
% else
%     fprintf('Figure handle invalid or no plots rendered. Plot not saved.\n');
% end
% fprintf('Plots generated.\n');
% if publication_ready; fprintf('** Publication ready (%0.1fin x %0.1fin). Review output & TUNE MARGINS/FONTS in Section 2. **\n', target_pub_width_inches, target_pub_height_inches); end