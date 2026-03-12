% =========================================================================
% FIGURE 3D: PRE-ICTAL, ICTAL, AND POST-ICTAL SINGLE-CHANNEL RAW EEG TRACE
% EVENT 1 - SPINS
% =========================================================================
%clear;
%clc;
% --- Settings ---
parquet_filename = 'Resaved-biov-2023-10-03T15_30_00-05_00-2023-10-04T12_00_00-05_00-EEGSY08.parquet';
recording_start_str = '2023-10-03 15:30:00';
signal_column = 'val';
sampling_rate = 256; % Assumed sampling rate for the Parquet file
target_tz = 'America/Chicago';

% --- Define the four 5-second phases for plotting ---
phases = {
    datetime('2023-10-04 06:53:03', 'TimeZone', target_tz), datetime('2023-10-04 06:53:08', 'TimeZone', target_tz);
    datetime('2023-10-04 06:55:31', 'TimeZone', target_tz), datetime('2023-10-04 06:55:36', 'TimeZone', target_tz);
    datetime('2023-10-04 06:56:41', 'TimeZone', target_tz), datetime('2023-10-04 06:56:46', 'TimeZone', target_tz);
    datetime('2023-10-04 06:58:04', 'TimeZone', target_tz), datetime('2023-10-04 06:58:09', 'TimeZone', target_tz);
};

% --- Plotting Aesthetics ---
eeg_line_color = 'k'; % Black line color
eeg_line_width = 1.2;
font_name = 'Helvetica';
font_size = 10;
axis_line_width = 1.2;

% --- Load Data ---
fprintf('Reading Parquet file: %s...\n', parquet_filename);
try
    % Read the specified column from the Parquet file
    continuous_data = parquetread(parquet_filename, 'SelectedVariableNames', {signal_column}).(signal_column);
catch ME
    error('Failed to read the Parquet file. Error: %s', ME.message);
end
fprintf('Parquet data loaded successfully.\n\n');

% Convert data to microvolts
bitres = 17;  
gain = 160; 

% Apply conversion formula
continuous_data = double(continuous_data) * 1e6 / (2^bitres * gain);
fprintf('Conversion to μV complete.\n\n');

% Create time vector for entire signal
file_start_time = datetime(recording_start_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss', 'TimeZone', target_tz);
num_samples = length(continuous_data);

% Create a relative time vector in seconds
relative_time_sec = (0:num_samples-1)' / sampling_rate;

% Create the absolute time vector by adding the relative time to the start time
absolute_time_vector = file_start_time + seconds(relative_time_sec);
fprintf('Time vector created successfully. Signal duration: %.2f hours\n\n', num_samples / sampling_rate / 3600);

% Generate four-panel plot
figure('Color', 'w', 'Position', [50, 400, 1200, 350]); % Wide figure for 4 plots
tl = tiledlayout(1, 4, 'TileSpacing', 'none', 'Padding', 'compact');
axes_handles = gobjects(4, 1); % To store axes handles for linking

% Loop through each of the four phases
for i = 1:length(phases)
    plot_start_time = phases{i, 1};
    plot_end_time = phases{i, 2};
    
    % Find the data indices for the current phase using the absolute time vector
    start_idx = find(absolute_time_vector >= plot_start_time, 1, 'first');
    end_idx   = find(absolute_time_vector <= plot_end_time, 1, 'last');
    
    % Create the next subplot in the 1x4 grid
    ax = nexttile;
    axes_handles(i) = ax; % Store handle for linking later
    if isempty(start_idx) || isempty(end_idx)
        warning('No data found for phase %d.', i);
        set(ax, 'visible', 'off'); % Hide axis if no data
        continue;
    end
    
    % Extract and plot the data segment for this phase

    data_segment = continuous_data(start_idx:end_idx);
    plot_time_vector = absolute_time_vector(start_idx:end_idx);
    
    plot(ax, plot_time_vector, data_segment, 'Color', eeg_line_color, 'LineWidth', eeg_line_width);

    set(ax, 'Box', 'off', 'FontName', font_name, 'FontSize', font_size, 'TickDir', 'in', 'LineWidth', axis_line_width);
    grid(ax, 'off');
    
    set(ax, 'XTickLabel', []);
   
    if i > 1
        set(ax, 'YTickLabel', []);
        ax.YAxis.Visible = 'off';
    end
end

% Final formatting
% Link all Y-axes so they share the same limits and zoom behavior
linkaxes(axes_handles, 'y');

% Set y-axis limits
ylim(axes_handles(1), [-100, 100]); 
ylabel(tl, 'Amplitude (μV)');

fprintf('Plot generation complete.\n');