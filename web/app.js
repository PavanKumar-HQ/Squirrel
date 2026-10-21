const appData = {
    volume: {
        total: 245.1,
        used: 118.1,
        available: 127.0
    },
    findings: [
        {
            id: 1,
            title: "Application Web & Asset Caches",
            path: "~/Library/Caches/com.apple.Safari/WebKitCache",
            size: "1.84 GB",
            category: "User Caches",
            eligibility: "Safe to Clean",
            tagClass: "tag-safe",
            ruleId: "RULE-CACHE-01",
            ruleDesc: "Pre-rendered web caches older than 7 days.",
            evidence: ["Located in ~/Library/Caches", "Unmodified for 14+ days"],
            recovery: "Managed Quarantine"
        },
        {
            id: 2,
            title: "Xcode Intermediate DerivedData",
            path: "~/Library/Developer/Xcode/DerivedData",
            size: "6.40 GB",
            category: "Developer",
            eligibility: "Keep / Excluded",
            tagClass: "tag-keep",
            ruleId: "RULE-DEV-EXCLUDE",
            ruleDesc: "Active compilation artifacts excluded in v1.0.",
            evidence: ["Matches developer workspace policy", "Exempt from batch deletion"],
            recovery: "N/A"
        },
        {
            id: 3,
            title: "Stale Diagnostic Crash Reports",
            path: "~/Library/Logs/DiagnosticReports/stale.crash",
            size: "940 MB",
            category: "System Logs",
            eligibility: "Safe to Clean",
            tagClass: "tag-safe",
            ruleId: "RULE-LOGS-01",
            ruleDesc: "Historical crash traces older than 14 days.",
            evidence: ["File extension .crash", "Inactive for 30+ days"],
            recovery: "macOS Trash"
        },
        {
            id: 4,
            title: "Downloaded Installer: Docker.dmg",
            path: "~/Downloads/Docker.dmg",
            size: "680 MB",
            category: "Downloads",
            eligibility: "Review Recommended",
            tagClass: "tag-review",
            ruleId: "RULE-INSTALLER-01",
            ruleDesc: "Disk image already installed into /Applications.",
            evidence: ["Installer package", "Stored in ~/Downloads"],
            recovery: "macOS Trash"
        },
        {
            id: 5,
            title: "Spotify Streaming Cache",
            path: "~/Library/Caches/com.spotify.client/Storage",
            size: "640 MB",
            category: "User Caches",
            eligibility: "Safe to Clean",
            tagClass: "tag-safe",
            ruleId: "RULE-CACHE-01",
            ruleDesc: "Temporary cached audio tracks.",
            evidence: ["Located in ~/Library/Caches", "Regenerated on demand"],
            recovery: "Managed Quarantine"
        }
    ],
    duplicates: [
        {
            hash: "3a9f81bc20e...18b",
            size: "1.20 GB",
            copies: [
                { name: "Final_Cut_Project_Backup.mov", path: "~/Movies/Final_Cut_Project_Backup.mov", isKeep: true },
                { name: "Final_Cut_Project_Backup (1).mov", path: "~/Downloads/Final_Cut_Project_Backup (1).mov", isKeep: false }
            ]
        },
        {
            hash: "8c771da44e...9f2",
            size: "450 MB",
            copies: [
                { name: "Presentation_Assets.zip", path: "~/Documents/Presentation_Assets.zip", isKeep: true },
                { name: "Presentation_Assets_copy.zip", path: "~/Desktop/Presentation_Assets_copy.zip", isKeep: false }
            ]
        }
    ],
    history: [
        { time: "Today 19:42", name: "WebKitCache", path: "~/Library/Caches/com.apple.Safari", action: "Moved to Quarantine", status: "Success", reclaimed: "1.84 GB" },
        { time: "Today 19:42", name: "diagnostic.log", path: "~/Library/Logs/diagnostic.log", action: "Moved to Trash", status: "Success", reclaimed: "940 MB" }
    ],
    inaccessible: [
        { path: "~/Library/Mail", reason: "TCC protected user email database (Requires Full Disk Access)" },
        { path: "~/Library/Messages", reason: "Protected chat attachments directory (Requires Full Disk Access)" },
        { path: "/System/Volumes/Data/.Spotlight-V100", reason: "SIP protected root index container" }
    ]
};

const app = {
    init() {
        this.bindEvents();
        this.renderDashboard();
        this.renderFindings();
        this.renderTreemap();
        this.renderDuplicates();
        this.renderHistory();
        this.renderInaccessible();
    },

    bindEvents() {
        // Tab switching
        document.querySelectorAll('.nav-item').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const tab = btn.dataset.tab;
                this.switchTab(tab);
            });
        });

        // Scan buttons
        document.getElementById('btnMainScan').addEventListener('click', () => this.startScan());
        document.getElementById('btnScanTop').addEventListener('click', () => this.startScan());
        document.getElementById('btnCancelScan').addEventListener('click', () => this.cancelScan());

        // Clean safely
        document.getElementById('btnCleanSafely').addEventListener('click', () => this.cleanSafely());

        // Refresh stats
        document.getElementById('btnRefreshStats').addEventListener('click', () => {
            const btn = document.getElementById('btnRefreshStats');
            btn.innerHTML = '<span>Refreshing...</span>';
            setTimeout(() => {
                btn.innerHTML = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M23 4v6h-6"/><path d="M1 20v-6h6"/><path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15"/></svg><span>Refresh Volume</span>';
            }, 600);
        });

        // Findings filter tabs
        document.querySelectorAll('.btn-filter').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('.btn-filter').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                this.filterFindings(btn.dataset.filter);
            });
        });

        // Findings search
        document.getElementById('findingSearch').addEventListener('input', (e) => {
            this.searchFindings(e.target.value);
        });

        // History tabs
        document.querySelectorAll('.history-tab-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('.history-tab-btn').forEach(b => b.classList.remove('active'));
                btn.classList.add('active');
                this.switchHistoryTab(btn.dataset.history);
            });
        });
    },

    switchTab(tabId) {
        document.querySelectorAll('.nav-item').forEach(b => b.classList.toggle('active', b.dataset.tab === tabId));
        document.querySelectorAll('.tab-pane').forEach(p => p.classList.remove('active'));
        const activePane = document.getElementById(`pane-${tabId}`);
        if (activePane) activePane.classList.add('active');

        const titleMap = {
            dashboard: "Dashboard",
            findings: "Findings & Classification",
            treemap: "Storage Treemap (Squarified)",
            duplicates: "Exact Duplicate Files",
            history: "History & Quarantine",
            permissions: "Inaccessible Areas"
        };
        document.getElementById('pageTitle').textContent = titleMap[tabId] || "Squirrel";
    },

    startScan() {
        const card = document.getElementById('scanProgressCard');
        card.style.display = 'block';
        const fill = document.getElementById('progressFillLine');
        const text = document.getElementById('progressCurrentPath');
        const stats = document.getElementById('progressStatsText');
        const statusText = document.getElementById('scanStatusText');

        let pct = 0;
        const paths = [
            "Scanning ~/Downloads...",
            "Scanning ~/Library/Caches...",
            "Scanning ~/Library/Logs...",
            "Hashing duplicate candidates with CryptoKit SHA-256...",
            "Finalizing squarified treemap layout..."
        ];

        this.scanInterval = setInterval(() => {
            pct += 20;
            fill.style.width = `${pct}%`;
            text.textContent = paths[Math.min(Math.floor(pct / 20) - 1, paths.length - 1)];
            stats.textContent = `Analyzing ${Math.floor(pct * 142)} items (${(pct * 0.18).toFixed(1)} GB analyzed)`;

            if (pct >= 100) {
                clearInterval(this.scanInterval);
                setTimeout(() => {
                    card.style.display = 'none';
                    statusText.textContent = "Status: Scan completed • Last Scan: Just now";
                    fill.style.width = '0%';
                }, 500);
            }
        }, 350);
    },

    cancelScan() {
        if (this.scanInterval) clearInterval(this.scanInterval);
        document.getElementById('scanProgressCard').style.display = 'none';
        document.getElementById('scanStatusText').textContent = "Status: Scan cancelled";
    },

    cleanSafely() {
        const modal = document.getElementById('cleanupModal');
        modal.classList.add('active');

        // Update storage numbers
        appData.volume.used = 114.68;
        appData.volume.available = 130.42;
        document.getElementById('valUsedSpace').textContent = "114.7 GB";
        document.getElementById('valAvailSpace').textContent = "130.4 GB";

        document.getElementById('btnCleanSafely').disabled = true;
        document.getElementById('btnCleanSafely').innerHTML = '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 6 9 17 4 12"/></svg><span>Cleaned Safely!</span>';
        document.getElementById('safeOpportunitySize').textContent = "0 B (Clean)";
    },

    closeModal() {
        document.getElementById('cleanupModal').classList.remove('active');
    },

    renderDashboard() {
        const list = document.getElementById('topOpportunityList');
        list.innerHTML = appData.findings.slice(0, 4).map(f => `
            <div class="opp-item">
                <div class="opp-item-icon">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/></svg>
                </div>
                <div class="opp-item-info">
                    <div class="opp-item-name">${f.title}</div>
                    <div class="opp-item-rule">${f.ruleDesc}</div>
                </div>
                <span class="finding-tag ${f.tagClass}">${f.eligibility}</span>
                <div class="opp-item-size">${f.size}</div>
            </div>
        `).join('');

        const dTreemap = document.getElementById('dashboardTreemap');
        dTreemap.innerHTML = `
            <div class="treemap-tile tile-cache" onclick="app.switchTab('treemap')">
                <div class="tile-title">User Caches</div>
                <div class="tile-size">8.42 GB</div>
            </div>
            <div class="treemap-tile tile-logs" onclick="app.switchTab('treemap')">
                <div class="tile-title">System & App Logs</div>
                <div class="tile-size">3.90 GB</div>
            </div>
            <div class="treemap-tile tile-downloads" onclick="app.switchTab('treemap')">
                <div class="tile-title">Downloads & DMGs</div>
                <div class="tile-size">5.20 GB</div>
            </div>
            <div class="treemap-tile tile-large" onclick="app.switchTab('treemap')">
                <div class="tile-title">Large Files (>100MB)</div>
                <div class="tile-size">14.80 GB</div>
            </div>
            <div class="treemap-tile tile-duplicates" onclick="app.switchTab('treemap')">
                <div class="tile-title">Exact Duplicates</div>
                <div class="tile-size">1.65 GB</div>
            </div>
            <div class="treemap-tile tile-other" onclick="app.switchTab('treemap')">
                <div class="tile-title">Other Scanned Files</div>
                <div class="tile-size">4.20 GB</div>
            </div>
        `;
    },

    renderFindings(filter = 'all', query = '') {
        const container = document.getElementById('findingsContainer');
        const filtered = appData.findings.filter(f => {
            const matchesFilter = (filter === 'all') ||
                (filter === 'safe' && f.eligibility === 'Safe to Clean') ||
                (filter === 'review' && f.eligibility === 'Review Recommended') ||
                (filter === 'keep' && f.eligibility === 'Keep / Excluded');
            const matchesQuery = !query || f.title.toLowerCase().includes(query.toLowerCase()) || f.path.toLowerCase().includes(query.toLowerCase());
            return matchesFilter && matchesQuery;
        });

        container.innerHTML = filtered.map(f => `
            <div class="finding-row" onclick="this.classList.toggle('expanded')">
                <div class="finding-summary">
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/></svg>
                    <div style="flex:1">
                        <strong>${f.title}</strong>
                        <div style="font-size:0.75rem; color:var(--text-secondary); font-family:var(--font-mono);">${f.path}</div>
                    </div>
                    <span class="finding-tag ${f.tagClass}">${f.eligibility}</span>
                    <strong style="font-family:var(--font-mono);">${f.size}</strong>
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg>
                </div>
                <div class="finding-details">
                    <div><strong>Rule:</strong> ${f.ruleId} — ${f.ruleDesc}</div>
                    <div><strong>Recovery Method:</strong> ${f.recovery}</div>
                    <div><strong>Evidence:</strong> ${f.evidence.join(' • ')}</div>
                </div>
            </div>
        `).join('');
    },

    filterFindings(filter) {
        this.currentFilter = filter;
        this.renderFindings(filter, this.currentQuery);
    },

    searchFindings(query) {
        this.currentQuery = query;
        this.renderFindings(this.currentFilter, query);
    },

    renderTreemap() {
        const fullCanvas = document.getElementById('fullTreemapCanvas');
        fullCanvas.innerHTML = `
            <div class="treemap-tile tile-cache" style="grid-column: span 2; grid-row: span 2;" onclick="app.inspectNode('User Caches', '~/Library/Caches', '8.42 GB', 'RULE-CACHE-01', 'Managed Quarantine')">
                <div class="tile-title">User Caches</div>
                <div class="tile-size">8.42 GB</div>
            </div>
            <div class="treemap-tile tile-downloads" style="grid-column: span 2;" onclick="app.inspectNode('Downloads & DMGs', '~/Downloads', '5.20 GB', 'RULE-INSTALLER-01', 'macOS Trash')">
                <div class="tile-title">Downloads & Installers</div>
                <div class="tile-size">5.20 GB</div>
            </div>
            <div class="treemap-tile tile-logs" onclick="app.inspectNode('System Logs', '~/Library/Logs', '3.90 GB', 'RULE-LOGS-01', 'macOS Trash')">
                <div class="tile-title">System Logs</div>
                <div class="tile-size">3.90 GB</div>
            </div>
            <div class="treemap-tile tile-duplicates" onclick="app.inspectNode('Exact Duplicates', 'SHA-256 Clusters', '1.65 GB', 'RULE-DUP-01', 'macOS Trash')">
                <div class="tile-title">Exact Duplicates</div>
                <div class="tile-size">1.65 GB</div>
            </div>
            <div class="treemap-tile tile-large" style="grid-column: span 4;" onclick="app.inspectNode('Large Files', 'Scanned User Roots', '14.80 GB', 'RULE-LARGE-01', 'Review Only')">
                <div class="tile-title">Large Files (>100MB) — Final_Cut_Project_Backup.mov, VirtualDisk.qcow2</div>
                <div class="tile-size">14.80 GB</div>
            </div>
        `;
    },

    inspectNode(title, path, size, rule, recovery) {
        const inspector = document.getElementById('treemapInspector');
        inspector.innerHTML = `
            <div style="display:flex; flex-direction:column; gap:14px;">
                <h3 style="font-size:1.1rem; font-weight:700;">${title}</h3>
                <div style="font-size:0.8rem; color:var(--text-secondary);">
                    <div style="margin-bottom:8px;"><strong>Path:</strong> <span style="font-family:var(--font-mono);">${path}</span></div>
                    <div style="margin-bottom:8px;"><strong>Allocated Size:</strong> ${size}</div>
                    <div style="margin-bottom:8px;"><strong>Rule:</strong> ${rule}</div>
                    <div style="margin-bottom:8px;"><strong>Recovery:</strong> ${recovery}</div>
                </div>
                <button class="btn btn-primary btn-sm" onclick="alert('Item selected: ' + '${title}')">Inspect Contents</button>
            </div>
        `;
    },

    resetTreemap() {
        this.renderTreemap();
        document.getElementById('treemapInspector').innerHTML = `
            <div class="inspector-empty">
                <p>Select an item in the treemap to view path, allocated blocks, and safety eligibility.</p>
            </div>
        `;
    },

    renderDuplicates() {
        const list = document.getElementById('duplicatesList');
        list.innerHTML = appData.duplicates.map((group, gIdx) => `
            <div class="duplicate-group">
                <div class="group-header">
                    <span>${group.copies.length} Copies • ${group.size} each</span>
                    <span class="group-hash">SHA-256: ${group.hash}</span>
                </div>
                ${group.copies.map((copy, cIdx) => `
                    <div class="duplicate-item">
                        <input type="checkbox" ${copy.isKeep ? '' : 'checked'} onchange="app.toggleDuplicateSelect()">
                        <div style="flex:1;">
                            <strong>${copy.name}</strong>
                            ${copy.isKeep ? '<span class="badge-keep" style="margin-left:6px;">RECOMMENDED TO KEEP</span>' : ''}
                            <div style="font-size:0.75rem; color:var(--text-secondary); font-family:var(--font-mono);">${copy.path}</div>
                        </div>
                    </div>
                `).join('')}
            </div>
        `).join('');
    },

    toggleDuplicateSelect() {
        document.getElementById('btnDeleteSelectedDuplicates').disabled = false;
    },

    renderHistory() {
        const container = document.getElementById('historyContainer');
        container.innerHTML = appData.history.map(h => `
            <div class="history-entry">
                <div>
                    <strong>${h.name}</strong> • <span style="color:var(--text-secondary);">${h.action}</span>
                    <div style="font-size:0.75rem; color:var(--text-secondary); font-family:var(--font-mono);">${h.path}</div>
                </div>
                <div style="text-align:right;">
                    <strong style="color:var(--success); font-family:var(--font-mono);">${h.reclaimed}</strong>
                    <div style="font-size:0.72rem; color:var(--text-muted);">${h.time}</div>
                </div>
            </div>
        `).join('');
    },

    switchHistoryTab(tab) {
        const container = document.getElementById('historyContainer');
        if (tab === 'quarantine') {
            container.innerHTML = `
                <div class="history-entry">
                    <div>
                        <strong>WebKitCache.dat</strong> (1.84 GB)
                        <div style="font-size:0.75rem; color:var(--text-secondary); font-family:var(--font-mono);">Original: ~/Library/Caches/com.apple.Safari/WebKitCache</div>
                        <div style="font-size:0.72rem; color:var(--text-muted);">Quarantined: Today 19:42 • Manifest ID: 87da7f-44</div>
                    </div>
                    <button class="btn btn-secondary btn-sm" onclick="alert('File restored safely to original location!')">Restore File</button>
                </div>
            `;
        } else {
            this.renderHistory();
        }
    },

    renderInaccessible() {
        const list = document.getElementById('inaccessibleList');
        list.innerHTML = appData.inaccessible.map(item => `
            <div class="card" style="margin-bottom:8px; display:flex; gap:12px; align-items:center;">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#ff9f0a" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0110 0v4"/></svg>
                <div>
                    <strong style="font-family:var(--font-mono); font-size:0.85rem;">${item.path}</strong>
                    <div style="font-size:0.75rem; color:var(--text-secondary);">${item.reason}</div>
                </div>
            </div>
        `).join('');
    }
};

document.addEventListener('DOMContentLoaded', () => app.init());
