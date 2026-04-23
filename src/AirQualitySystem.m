classdef AirQualitySystem < handle
    % AirQualitySystem - Intelligent Air Quality Monitoring with Source Detection
    % Handles data acquisition (via Raspberry Pi + SDS011 or Simulation),
    % feature extraction, source classification, and real-time visualization.
    
    properties
        PiIPAddress     % Raspberry Pi IP Address
        PiUsername      % Raspberry Pi Username
        PiPassword      % Raspberry Pi Password
        Port            % Serial Port (e.g., '/dev/ttyUSB0')
        BaudRate        % Serial Baud Rate (default 9600 for SDS011)
        SimMode         % Boolean flag to run simulation without hardware
        
        % Data buffers
        TimeArray
        PM25Data
        PM10Data
        SourceData
        AdviceData
        
        % Hardware objects
        PiObj
        SerialDevObj
        
        % UI objects
        FigureHandle
        PlotLine25
        PlotLine10
        ScatterPlot
        AnnotationText
    end
    
    methods
        function obj = AirQualitySystem(ip, user, pass, port, simMode)
            % Constructor
            if nargin < 5
                simMode = false;
            end
            obj.PiIPAddress = ip;
            obj.PiUsername = user;
            obj.PiPassword = pass;
            obj.Port = port;
            obj.BaudRate = 9600;
            obj.SimMode = simMode;
            
            % Initialize empty buffers
            obj.TimeArray = [];
            obj.PM25Data = [];
            obj.PM10Data = [];
            obj.SourceData = strings(0);
            obj.AdviceData = strings(0);
        end
        
        function connect(obj)
            % Establish connection to hardware if not in simulation mode
            if obj.SimMode
                fprintf('Running in SIMULATION MODE. No hardware connection required.\n');
            else
                fprintf('Connecting to Raspberry Pi at %s...\n', obj.PiIPAddress);
                try
                    obj.PiObj = raspi(obj.PiIPAddress, obj.PiUsername, obj.PiPassword);
                    fprintf('Connecting to Nova PM SDS011 on %s...\n', obj.Port);
                    obj.SerialDevObj = serialdev(obj.PiObj, obj.Port, obj.BaudRate);
                    fprintf('Hardware connection established successfully.\n');
                catch ME
                    warning('Failed to connect to hardware: %s', ME.message);
                    fprintf('Falling back to SIMULATION MODE.\n');
                    obj.SimMode = true;
                end
            end
        end
        
        function run(obj, numSamples)
            % Main execution loop for real-time monitoring
            obj.setupDashboard();
            
            fprintf('Starting intelligent monitoring for %d samples...\n', numSamples);
            fprintf('------------------------------------------------------------\n');
            
            for k = 1:numSamples
                % 1. Data Acquisition
                [pm25, pm10] = obj.readSensor(k);
                
                % Update buffers
                obj.TimeArray(k) = k;
                obj.PM25Data(k) = pm25;
                obj.PM10Data(k) = pm10;
                
                % 2. Intelligence: Extract & Classify
                [source, advice] = obj.analyze(k);
                obj.SourceData(k) = source;
                obj.AdviceData(k) = advice;
                
                % 3. Visualization
                obj.updateDashboard();
                
                % Print to console if event detected
                if source ~= "Clean"
                    fprintf('Time %3d | PM2.5=%5.1f | Source: %-30s | Advice: %s\n', ...
                        k, pm25, source, advice);
                end
                
                pause(1); % 1 Hz sampling rate (typical for SDS011)
                
                % Early exit if figure closed
                if ~ishghandle(obj.FigureHandle)
                    fprintf('Dashboard closed. Stopping monitoring.\n');
                    break;
                end
            end
            fprintf('Monitoring session complete.\n');
        end
        
        function [pm25, pm10] = readSensor(obj, k)
            % Reads from SDS011 or generates intelligent mock data
            if obj.SimMode
                % Generate baseline
                pm25 = 12 + 2 * randn();
                pm10 = 15 + 3 * randn();
                
                % Inject simulated events for demonstration
                if k >= 20 && k <= 25
                    pm25 = pm25 + 30; % Dust spike
                    pm10 = pm10 + 35;
                elseif k >= 50 && k <= 60
                    pm25 = pm25 + 45; % Combustion
                    pm10 = pm10 + 50;
                elseif k >= 80 && k <= 90
                    pm25 = pm25 + 10; % Coarse particles
                    pm10 = pm10 + 40;
                end
            else
                % Read physical sensor
                try
                    data = read(obj.SerialDevObj, 10);
                    if length(data) == 10 && data(1) == 170 && data(10) == 171
                        pm25 = ((double(data(4)) * 256) + double(data(3))) / 10;
                        pm10 = ((double(data(6)) * 256) + double(data(5))) / 10;
                    else
                        % Repeat last valid if corrupted
                        if k > 1
                            pm25 = obj.PM25Data(k-1);
                            pm10 = obj.PM10Data(k-1);
                        else
                            pm25 = 0; pm10 = 0;
                        end
                    end
                catch
                     if k > 1
                        pm25 = obj.PM25Data(k-1);
                        pm10 = obj.PM10Data(k-1);
                     else
                        pm25 = 0; pm10 = 0;
                     end
                end
            end
        end
        
        function [source, advice] = analyze(obj, k)
            % Core AI / Intelligence logic
            pm25 = obj.PM25Data(k);
            pm10 = obj.PM10Data(k);
            
            % Feature Extraction
            ratio = pm25 / max(pm10, 0.1); % avoid div by zero
            if k > 1
                rate_of_change = pm25 - obj.PM25Data(k-1);
            else
                rate_of_change = 0;
            end
            
            % Smart Thresholding (dynamic based on history)
            if k > 5
                baseline = mean(obj.PM25Data(1:k-1));
                threshold = baseline + 2*std(obj.PM25Data(1:k-1));
                threshold = max(threshold, 15); % Minimum sensible threshold
            else
                threshold = 20;
            end
            
            % Classification Tree
            if pm25 > threshold
                if rate_of_change > 10
                    source = "Dust / Sudden disturbance";
                elseif ratio > 0.8
                    source = "Combustion (cooking / smoke)";
                elseif ratio < 0.5
                    source = "Coarse particles (outdoor dust)";
                else
                    source = "General pollution";
                end
            else
                source = "Clean";
            end
            
            % Adaptive Recommendations
            if pm25 < 15
                advice = "Air is clean";
            elseif pm25 < 35
                advice = "Moderate - consider ventilation";
            else
                advice = "Unhealthy - open window / reduce activity";
            end
        end
        
        function runFSDAAnalysis(obj)
            % Post-monitoring robust analysis using FSDA (Flexible Statistics and Data Analysis)
            % This method performs robust multivariate outlier detection to find hidden pollution anomalies.
            
            fprintf('\n--- Starting FSDA Robust Analysis ---\n');
            if isempty(obj.PM25Data) || length(obj.PM25Data) < 10
                fprintf('Not enough data to run FSDA analysis.\n');
                return;
            end
            
            try
                % Check if FSDA is installed by looking for FSM function
                if exist('FSM', 'file') ~= 2
                    fprintf('FSDA toolbox not found in MATLAB path. Skipping robust analysis.\n');
                    fprintf('Please install FSDA to enable advanced robust statistics.\n');
                    return;
                end
                
                % Prepare multivariate data matrix: [PM2.5, PM10]
                Y = [obj.PM25Data', obj.PM10Data'];
                
                % Use FSM (Forward Search for Multivariate Outliers)
                % This robustly identifies pollution events without being skewed by extreme spikes
                fprintf('Running FSM (Forward Search for Multivariate data)...\n');
                out = FSM(Y, 'plots', 1, 'msg', 0);
                
                numOutliers = length(out.outliers);
                fprintf('FSDA detected %d robust anomalies in the data stream.\n', numOutliers);
                
                % Add a new figure summarizing the FSDA results
                figure('Name', 'FSDA Robust Analysis Results', 'Color', 'w');
                scatter(Y(:,1), Y(:,2), 50, 'b', 'filled'); hold on;
                if numOutliers > 0
                    scatter(Y(out.outliers, 1), Y(out.outliers, 2), 100, 'r', 'filled', 'MarkerEdgeColor', 'k');
                    legend('Normal Measurements', 'Robust FSDA Anomalies', 'Location', 'best');
                else
                    legend('Measurements');
                end
                title('FSDA Bivariate Outlier Detection (PM_{2.5} vs PM_{10})', 'FontWeight', 'bold');
                xlabel('PM2.5 Concentration (\mu g / m^3)');
                ylabel('PM10 Concentration (\mu g / m^3)');
                grid on;
                
            catch ME
                fprintf('An error occurred during FSDA analysis: %s\n', ME.message);
            end
        end
        
        function setupDashboard(obj)
            % Initializes the real-time plot
            obj.FigureHandle = figure('Name', 'Intelligent Air Quality Monitor', ...
                                      'Position', [100, 100, 900, 500], ...
                                      'NumberTitle', 'off', 'Color', 'w');
            
            % Main axes
            ax = axes('Parent', obj.FigureHandle);
            hold(ax, 'on');
            grid(ax, 'on');
            
            % Lines
            obj.PlotLine25 = plot(ax, NaN, NaN, 'b-', 'LineWidth', 2, 'DisplayName', 'PM2.5');
            obj.PlotLine10 = plot(ax, NaN, NaN, 'g--', 'LineWidth', 1.5, 'DisplayName', 'PM10');
            obj.ScatterPlot = scatter(ax, NaN, NaN, 100, 'r', 'filled', 'DisplayName', 'Detected Events');
            
            title(ax, 'Real-Time Air Quality & Source Detection', 'FontSize', 14, 'FontWeight', 'bold');
            xlabel(ax, 'Time (seconds)', 'FontSize', 12);
            ylabel(ax, 'Concentration (\mu g / m^3)', 'FontSize', 12);
            legend(ax, 'Location', 'northwest', 'FontSize', 11);
            
            % Status Annotation Panel
            obj.AnnotationText = annotation('textbox', [0.15, 0.75, 0.35, 0.15], ...
                'String', 'Initializing...', 'FitBoxToText', 'on', ...
                'BackgroundColor', [0.95 0.95 0.95], 'EdgeColor', 'k', 'FontSize', 11, ...
                'Margin', 10);
        end
        
        function updateDashboard(obj)
            % Updates plot with new data safely
            if ~ishghandle(obj.FigureHandle)
                return; % Stop updating if figure was closed
            end
            
            % Update Lines
            set(obj.PlotLine25, 'XData', obj.TimeArray, 'YData', obj.PM25Data);
            set(obj.PlotLine10, 'XData', obj.TimeArray, 'YData', obj.PM10Data);
            
            % Find events
            eventIdx = find(obj.SourceData ~= "Clean");
            if ~isempty(eventIdx)
                set(obj.ScatterPlot, 'XData', obj.TimeArray(eventIdx), 'YData', obj.PM25Data(eventIdx));
            end
            
            % Auto scale X axis to show a scrolling window of the last 60 seconds
            ax = obj.PlotLine25.Parent;
            windowSize = 60;
            currentMax = max(obj.TimeArray);
            if isempty(currentMax), currentMax = 1; end
            xlim(ax, [max(1, currentMax - windowSize), max(windowSize, currentMax + 5)]);
            
            % Auto scale Y axis
            yMax = max([obj.PM10Data, 50]) * 1.2;
            ylim(ax, [0, yMax]);
            
            % Update Status Text
            latestSrc = obj.SourceData(end);
            latestAdv = obj.AdviceData(end);
            statusStr = sprintf('CURRENT STATUS\nSource: %s\nAdvice: %s', latestSrc, latestAdv);
            set(obj.AnnotationText, 'String', statusStr);
            
            % Highlight red if unhealthy
            if latestSrc ~= "Clean"
                set(obj.AnnotationText, 'BackgroundColor', [1 0.8 0.8]); % Light Red
            else
                set(obj.AnnotationText, 'BackgroundColor', [0.9 1 0.9]); % Light Green
            end
            
            drawnow;
        end
    end
end
