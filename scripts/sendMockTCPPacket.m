function sendMockTCPPacket(ip, port)
% sendMockTCPPacket  Connect to a MATLAB tcpserver and inject one JSON packet.
% Used by ScriptsCoverageTest to cover the socket_intelligence_dashboard branches.
try
    client = tcpclient(ip, port, 'Timeout', 1);
    packet = struct('timestamp', datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
                    'pm25', 25.5, 'pm10', 30.2);
    write(client, uint8([jsonencode(packet), newline]));
    pause(0.15);
    clear client;
catch
    % Silently ignore – dashboard may not be ready yet
end
end
