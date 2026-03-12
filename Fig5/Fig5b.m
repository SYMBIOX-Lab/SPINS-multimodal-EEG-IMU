% =========================================================================
% FIGURE 5B: BLAND ALTMAN ANALYSIS DELTA/THETA RATIO
% =========================================================================
% clear, close all, clc;

%% Configuration
% Define File Paths and Time Window
edfFilePath = 'RightEeg_0001_new.edf';
csvFilePath = 'converted_sensor_data_patient5right.csv';

cropStartTimeStr = '2024-11-25 13:45:30';
cropEndTimeStr   = '2024-11-25 14:15:30';
targetTimezone = 'America/Chicago';

% Manual Timeshift and Signal Processing Settings
manual_offset_seconds = -19.38;

% Define Frequency Bands
delta_band = [0.5, 4]; % Hz
theta_band = [4, 8];   % Hz

% Plotting Parameters and Formatting
figure_position = [100, 100, 900, 700];
plot_font_name = 'Arial';
axis_font_size = 10;
label_font_size = 10;
title_font_size = 18;

%% Load and Process EDF Data
fprintf('Loading and processing EDF data...\n');
try
    info = edfinfo(edfFilePath);
    originalChannelName = 'EEG Right-Ref';
    channelName = 'EEGRight_Ref';
    if isprop(info, 'VariableNames'), channelLabels = info.VariableNames; else, channelLabels = info.SignalLabels; end
    channelIndex = find(strcmp(channelLabels, originalChannelName));
    if isempty(channelIndex), channelIndex = find(strcmp(channelLabels, channelName)); end
    if isempty(channelIndex), error('Could not find the channel index for "%s".', originalChannelName); end
    if isprop(info, 'SampleRate'), eeg_fs = info.SampleRate(channelIndex); elseif isprop(info, 'SignalFrequencies'), eeg_fs = info.SignalFrequencies(channelIndex); else, eeg_fs = info.NumSamples(channelIndex) / seconds(info.DataRecordDuration); end
    startTimeString = strcat(info.StartDate, {' '}, info.StartTime);
    eeg_start_time_naive = datetime(startTimeString, 'InputFormat', 'dd.MM.yy HH.mm.ss');
    eeg_start_time_local = eeg_start_time_naive;
    eeg_start_time_local.TimeZone = targetTimezone;
    selected_channel_name = channelLabels{channelIndex};
    all_data_edf = edfread(edfFilePath, 'SelectedSignals', selected_channel_name);
    actual_variable_name = all_data_edf.Properties.VariableNames{1};
    signal_in_cells = all_data_edf.(actual_variable_name);
    eeg_signal = vertcat(signal_in_cells{:});
    eeg_signal = double(eeg_signal);
catch ME
    fprintf('Error loading EDF file: %s\n', ME.message); return;
end

%% Load and Process CSV
fprintf('Loading CSV data...\n');
try
    csv_table = readtable(csvFilePath);
    sensor_timestamp_text = csv_table.timestamp;
    sensor_data = csv_table.value;
    sensor_time_vector_utc = datetime(sensor_timestamp_text, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSSSSS', 'TimeZone', 'UTC');
    sensor_time_vector_local = sensor_time_vector_utc;
    sensor_time_vector_local.TimeZone = targetTimezone;
catch ME
    fprintf('Error loading CSV file: %s\n', ME.message); return;
end

%% Synchronize and Scale Signals

num_eeg_samples = length(eeg_signal);
eeg_time_vector_local = eeg_start_time_local + seconds((0:num_eeg_samples-1)' / eeg_fs);
eeg_time_vector_local = eeg_time_vector_local + seconds(manual_offset_seconds);
cropStartTime = datetime(cropStartTimeStr, 'TimeZone', targetTimezone);
cropEndTime   = datetime(cropEndTimeStr, 'TimeZone', targetTimezone);
eeg_crop_idx = (eeg_time_vector_local >= cropStartTime & eeg_time_vector_local <= cropEndTime);
eeg_signal_cropped = eeg_signal(eeg_crop_idx);
sensor_crop_idx = (sensor_time_vector_local >= cropStartTime & sensor_time_vector_local <= cropEndTime);
sensor_data_cropped = sensor_data(sensor_crop_idx);
sensor_time_cropped = sensor_time_vector_local(sensor_crop_idx); % Crop time vector

% Calculate original sensor sampling rate
if length(sensor_time_cropped) < 2
    error('Not enough sensor data in the specified crop window to determine sampling rate.');
end
sensor_fs_original = 1 / mean(seconds(diff(sensor_time_cropped)));
if sensor_fs_original <= 0 || ~isfinite(sensor_fs_original)
    error('Could not determine a valid positive sampling rate for the sensor data. Check timestamps in CSV.');
end


%Display Results
fprintf('--------------------------------------------------\n');
fprintf('EEG (EDF) Sampling Rate: %.2f Hz\n', eeg_fs);
fprintf('Sensor (CSV) Sampling Rate: %.2f Hz\n', sensor_fs_original);
fprintf('--------------------------------------------------\n');
fprintf('Downsampling sensor data to match EEG sampling rate...\n');
sensor_data_downsampled = resample(sensor_data_cropped, round(eeg_fs), round(sensor_fs_original));

%% Prepare Data for Analysis (No Filter)
% Center and Scale Signals
eeg_to_plot = eeg_signal_cropped - mean(eeg_signal_cropped);
sensor_to_plot = -sensor_data_downsampled; % Invert
sensor_to_plot = sensor_to_plot - mean(sensor_to_plot); % Center
eeg_min = min(eeg_to_plot); eeg_max = max(eeg_to_plot);
sensor_min = min(sensor_to_plot); sensor_max = max(sensor_to_plot);
sensor_scaled = (eeg_max - eeg_min) * (sensor_to_plot - sensor_min) / (sensor_max - sensor_min) + eeg_min;
sensor_scaled = sensor_scaled + 8;
minLength = min(length(eeg_to_plot), length(sensor_scaled));
eeg_final = eeg_to_plot(1:minLength);
sensor_final = sensor_scaled(1:minLength);
fprintf('Signal preparation complete.\n');

%% Calculate Time-Varying Delta/Theta Ratio for Both Signals 
fprintf('Calculating time-varying Delta/Theta ratios...\n');
delta_filter = designfilt('bandpassiir', 'FilterOrder', 4, 'HalfPowerFrequency1', delta_band(1), 'HalfPowerFrequency2', delta_band(2), 'SampleRate', eeg_fs);
theta_filter = designfilt('bandpassiir', 'FilterOrder', 4, 'HalfPowerFrequency1', theta_band(1), 'HalfPowerFrequency2', theta_band(2), 'SampleRate', eeg_fs);

eeg_delta_signal = filtfilt(delta_filter, eeg_final);
eeg_theta_signal = filtfilt(theta_filter, eeg_final);

sensor_delta_signal = filtfilt(delta_filter, sensor_final);
sensor_theta_signal = filtfilt(theta_filter, sensor_final);

window_len_sec = 2.0; 
window_len_samples = round(window_len_sec * eeg_fs);
overlap_samples = round(window_len_samples / 2);

[~, ~, ~, P_eeg_delta] = spectrogram(eeg_delta_signal, window_len_samples, overlap_samples, [], eeg_fs, 'power');
[~, ~, ~, P_eeg_theta] = spectrogram(eeg_theta_signal, window_len_samples, overlap_samples, [], eeg_fs, 'power');
eeg_ratio = sum(P_eeg_delta, 1) ./ (sum(P_eeg_theta, 1) + eps);

[~, ~, ~, P_sensor_delta] = spectrogram(sensor_delta_signal, window_len_samples, overlap_samples, [], eeg_fs, 'power');
[~, ~, ~, P_sensor_theta] = spectrogram(sensor_theta_signal, window_len_samples, overlap_samples, [], eeg_fs, 'power');
sensor_ratio = sum(P_sensor_delta, 1) ./ (sum(P_sensor_theta, 1) + eps);

fprintf('Ratio calculation complete.\n');
%% Perform Bland-Altman on Ratios

mean_ratios = (eeg_ratio + sensor_ratio) / 2;
diff_ratios = eeg_ratio - sensor_ratio;

mean_diff = mean(diff_ratios);
std_diff = std(diff_ratios);

upper_loa = mean_diff + 1.96 * std_diff;
lower_loa = mean_diff - 1.96 * std_diff;

fprintf('Analysis complete.\n');

%% Generate Bland Altman Plot

figure('Name', 'Bland-Altman Plot of Delta/Theta Ratio', 'Color', 'w', 'Position', figure_position);
hold on;

inlier_mask = (diff_ratios >= lower_loa) & (diff_ratios <= upper_loa);
    sum(~inlier_mask), (sum(~inlier_mask) / length(diff_ratios)) * 100);

% Scatter Plot Formatting
scatter(mean_ratios(inlier_mask), diff_ratios(inlier_mask), 50, 'o', ...
    'MarkerEdgeColor', [0.2 0.5 0.8], ... % A professional blue
    'MarkerFaceColor', [0.2 0.5 0.8], ...
    'MarkerFaceAlpha', 0.3, ...
    'LineWidth', 1.0);

% Plot lines with Black and Gray
plot(xlim, [mean_diff, mean_diff], 'k-', 'LineWidth', 2.5); 
plot(xlim, [upper_loa, upper_loa], '--', 'Color', [0.3 0.3 0.3], 'LineWidth', 2);
plot(xlim, [lower_loa, lower_loa], '--', 'Color', [0.3 0.3 0.3], 'LineWidth', 2);
hold off;

% More Plot Formatting: limits, fonts, labels
ylim([-300, 300]);
xlim([0, 200]); 
set(gca, ...
    'FontName', plot_font_name, ...
    'FontSize', axis_font_size, ...
    'Box', 'off', ...
    'LineWidth', 1.2, ...
    'TickDir', 'out', ...
    'XTickLabel', [], ...  
    'YTickLabel', []);   
grid off;

fprintf('Plot generation complete.\n');

%% Save Figure (optional)
[~, edf_filename_base, ~] = fileparts(edfFilePath);
[~, csv_filename_base, ~] = fileparts(csvFilePath);
plot_filename_base_str = sprintf('BlandAltman_DeltaThetaRatio_%s_vs_%s.png', edf_filename_base, csv_filename_base);
fprintf('Saving figure to: %s\n', plot_filename_base_str);
try
  exportgraphics(gcf, plot_filename_base_str, 'Resolution', 300);
catch
    saveas(gcf, plot_filename_base_str);
end
fprintf('Analysis complete.\n');