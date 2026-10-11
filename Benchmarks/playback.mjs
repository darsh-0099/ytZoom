// Deterministic operation counts, not a measurement of live YouTube CPU or RAM.
import { readFileSync, writeFileSync } from 'node:fs';
import vm from 'node:vm';
const extract = path => readFileSync(path, 'utf8').match(/static let source = """\n([\s\S]*?)\n    """/)[1];
function measure(source) {
  const counts = { playerQueries: 0, previewScans: 0, styleLookups: 0, appearanceChanges: 0 };
  const video = { isConnected: true, paused: true, ended: false, playbackRate: 1,
    closest: selector => selector === '#movie_player' ? {} : null };
  const root = { dark: false, hasAttribute: () => root.dark,
    toggleAttribute: (_, dark) => { counts.appearanceChanges++; root.dark = dark; }, style: {} };
  const styles = new Map();
  const document = { hidden: false, documentElement: root,
    querySelector: () => { counts.playerQueries++; return video; },
    querySelectorAll: () => { counts.previewScans++; return []; },
    getElementById: id => { counts.styleLookups++; return styles.get(id); },
    createElement: () => ({ textContent: '' }), head: { appendChild: style => styles.set(style.id, style) },
    addEventListener() {} };
  const window = {};
  vm.runInNewContext(source, { window, document, URL, location: { hostname: 'www.youtube.com', href: 'https://www.youtube.com/watch?v=fixture' } });
  const settings = { css: 'body{color:white}', rate: 1.5, suppressPreviews: true, darkMode: true };
  window.__ytzoom.configure(settings);
  for (const key of Object.keys(counts)) counts[key] = 0;
  for (let i = 0; i < 1000; i++) window.__ytzoom.configure(settings);
  return counts;
}
const report = { scenario: '1000 identical settings updates after initialization',
  scope: 'DOM/media fixture operation counts; not live browser performance',
  current: measure(extract('Sources/ytZoom/PlaybackScript.swift')) };
if (process.argv[2]) report.baseline = measure(extract(process.argv[2]));
if (process.argv[3]) writeFileSync(process.argv[3], JSON.stringify(report, null, 2) + '\n');
process.stdout.write(JSON.stringify(report, null, 2) + '\n');
