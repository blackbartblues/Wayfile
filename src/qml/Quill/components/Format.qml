pragma Singleton

import QtQuick

QtObject {
    function bytes(n) {
        if (n === undefined || n === null || isNaN(n) || n < 0) return "0 B";
        if (n < 1024) return n + " B";

        var units = ["KB", "MB", "GB", "TB", "PB"];
        var value = n / 1024;
        var idx = 0;
        while (value >= 1024 && idx < units.length - 1) {
            value /= 1024;
            idx++;
        }

        // One decimal for GB and below; whole number for TB+
        var rounded = idx >= 3 ? Math.round(value) : Math.round(value * 10) / 10;
        return rounded + " " + units[idx];
    }
}
