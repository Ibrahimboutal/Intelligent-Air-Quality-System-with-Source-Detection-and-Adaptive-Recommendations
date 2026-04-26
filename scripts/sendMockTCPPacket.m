function sendMockTCPPacket(ip, port)
% sendMockTCPPacket  Connect to a MATLAB tcpserver/tcpip and inject one JSON packet.
% Used by ScriptsCoverageTest to cover the socket_intelligence_dashboard branches.
try
    useLegacy = isempty(which('tcpclient'));
    if ~useLegacy
        client = tcpclient(ip, port, 'Timeout', 1);
        packet = struct('timestamp', datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
                        'pm25', 25.5, 'pm10', 30.2);
        write(client, uint8([jsonencode(packet), newline]));
        pause(0.15);
        clear client;
    else
        % Legacy fallback for older MATLAB versions (e.g. R2019b)
        client = tcpip(ip, port, 'NetworkRole', 'client', 'Timeout', 1);
        fopen(client);
        packet = struct('timestamp', datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
                        'pm25', 25.5, 'pm10', 30.2);
        fprintf(client, '%s\n', jsonencode(packet));
        pause(0.15);
        fclose(client);
        delete(client);
    end
catch
    % Silently ignore – dashboard may not be ready yet
end
end
