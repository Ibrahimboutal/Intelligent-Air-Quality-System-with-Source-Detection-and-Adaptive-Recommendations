function sendMockTCPPacket(ip, port, numPackets, burstDelay)
% sendMockTCPPacket  Connect to a MATLAB tcpserver/tcpip and inject JSON packets.
% Used by ScriptsCoverageTest to cover the socket_intelligence_dashboard branches
% and for stress testing the telemetry buffer.
if nargin < 3, numPackets = 1; end
if nargin < 4, burstDelay = 0.15; end % Reduce this to 0.01 for 100x stress testing

try
    useLegacy = isempty(which('tcpclient'));
    if ~useLegacy
        client = tcpclient(ip, port, 'Timeout', 1);
        for i = 1:numPackets
            packet = struct('timestamp', datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
                            'pm25', 25.5 + randn(), 'pm10', 30.2 + randn());
            write(client, uint8([jsonencode(packet), newline]));
            if burstDelay > 0, pause(burstDelay); end
        end
        clear client;
    else
        % Legacy fallback for older MATLAB versions (e.g. R2019b)
        client = tcpip(ip, port, 'NetworkRole', 'client', 'Timeout', 1);
        fopen(client);
        for i = 1:numPackets
            packet = struct('timestamp', datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
                            'pm25', 25.5 + randn(), 'pm10', 30.2 + randn());
            fprintf(client, '%s\n', jsonencode(packet));
            if burstDelay > 0, pause(burstDelay); end
        end
        fclose(client);
        delete(client);
    end
    fprintf('Successfully sent %d mock packets.\n', numPackets);
catch ME
    % Silently ignore – dashboard may not be ready yet
    fprintf('Mock packet failed: %s\n', ME.message);
end
end
