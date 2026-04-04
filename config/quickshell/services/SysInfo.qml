pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property real cpuPercent: 0
    property real memPercent: 0
    property real memUsedGb: 0
    property real memTotalGb: 0
    property real temperature: 0

    // Thresholds from ashell config
    readonly property int cpuWarn: 70
    readonly property int cpuAlert: 90
    readonly property int memWarn: 75
    readonly property int memAlert: 90
    readonly property int tempWarn: 70
    readonly property int tempAlert: 90

    // Previous CPU values for delta calculation
    property real prevIdle: 0
    property real prevTotal: 0

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            cpuProc.running = true;
            memProc.running = true;
            tempProc.running = true;
        }
    }

    Process {
        id: cpuProc
        command: ["sh", "-c", "head -1 /proc/stat"]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split(/\s+/);
                if (parts[0] !== "cpu") return;
                const values = parts.slice(1).map(Number);
                const idle = values[3] + values[4];
                const total = values.reduce((a, b) => a + b, 0);
                const diffIdle = idle - root.prevIdle;
                const diffTotal = total - root.prevTotal;
                if (diffTotal > 0)
                    root.cpuPercent = Math.round((1 - diffIdle / diffTotal) * 100);
                root.prevIdle = idle;
                root.prevTotal = total;
            }
        }
    }

    Process {
        id: memProc
        command: ["sh", "-c", "grep -E '^(MemTotal|MemAvailable):' /proc/meminfo"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                let total = 0, available = 0;
                for (const line of lines) {
                    const match = line.match(/^(\w+):\s+(\d+)/);
                    if (!match) continue;
                    if (match[1] === "MemTotal") total = Number(match[2]);
                    else if (match[1] === "MemAvailable") available = Number(match[2]);
                }
                if (total > 0) {
                    root.memTotalGb = total / 1048576;
                    root.memUsedGb = (total - available) / 1048576;
                    root.memPercent = Math.round(((total - available) / total) * 100);
                }
            }
        }
    }

    Process {
        id: tempProc
        command: ["sh", "-c", "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -rn | head -1"]
        stdout: SplitParser {
            onRead: line => {
                const val = Number(line.trim());
                if (val > 0) root.temperature = Math.round(val / 1000);
            }
        }
    }

    function colorForValue(value, warn, alert) {
        if (value >= alert) return Colors.danger;
        if (value >= warn) return Colors.warning;
        return Colors.success;
    }
}
