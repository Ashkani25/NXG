// Copies the Colyseus browser client (no bundler) from node_modules into www/vendor.
const fs = require('fs'), path = require('path');
const root = path.join(__dirname, '..', 'node_modules', 'colyseus.js'), dst = path.join(__dirname, '..', 'www', 'vendor');
const cands = ['dist/colyseus.js', 'dist/colyseus.min.js'].map(f => path.join(root, f)), from = cands.find(f => fs.existsSync(f));
if (!from) { console.error('colyseus.js browser bundle not found in node_modules/colyseus.js/dist - run `npm install` first'); process.exit(1) }
fs.mkdirSync(dst, { recursive: true }); fs.copyFileSync(from, path.join(dst, 'colyseus.js')); console.log('vendored', path.relative(process.cwd(), from));
