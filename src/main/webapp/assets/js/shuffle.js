/**
 * ASF compliance: randomize element ordering on every page load.
 * Elements with [data-shuffle-group] will have their direct children
 * shuffled using the Fisher-Yates algorithm.
 *
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.
 */
(function () {
    'use strict';
    document.querySelectorAll('[data-shuffle-group]').forEach(function (container) {
        var items = Array.from(container.children);
        // Fisher-Yates shuffle
        for (var i = items.length - 1; i > 0; i--) {
            var j = Math.floor(Math.random() * (i + 1));
            var temp = items[i];
            items[i] = items[j];
            items[j] = temp;
        }
        items.forEach(function (item) {
            container.appendChild(item);
        });
    });
})();
