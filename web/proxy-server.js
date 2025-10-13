const WebSocket = require('ws');
const http = require('http');

const PORT = 8080;
const GODOT_SERVER = 'ws://localhost:9080';

const server = http.createServer();
const wss = new WebSocket.Server({ server });

wss.on('connection', (clientWs) => {
    console.log('Client connected to proxy');
    
    // Connect to Godot server
    const godotWs = new WebSocket(GODOT_SERVER);
    
    godotWs.on('open', () => {
        console.log('Connected to Godot server');
    });
    
    // Forward messages from client to Godot
    clientWs.on('message', (data) => {
        if (godotWs.readyState === WebSocket.OPEN) {
            godotWs.send(data);
        }
    });
    
    // Forward messages from Godot to client
    godotWs.on('message', (data) => {
        if (clientWs.readyState === WebSocket.OPEN) {
            clientWs.send(data);
        }
    });
    
    // Handle disconnections
    clientWs.on('close', () => {
        console.log('Client disconnected');
        godotWs.close();
    });
    
    godotWs.on('close', () => {
        console.log('Godot server disconnected');
        clientWs.close();
    });
    
    godotWs.on('error', (err) => {
        console.error('Godot WS error:', err);
        clientWs.close();
    });
});

server.listen(PORT, () => {
    console.log(`WebSocket proxy running on port ${PORT}`);
    console.log(`Forwarding to: ${GODOT_SERVER}`);
});