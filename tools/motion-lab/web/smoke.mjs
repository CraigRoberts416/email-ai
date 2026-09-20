import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { spring } from 'motion';
import { AnimateNumber } from 'motion-plus/react';
import { gsap } from 'gsap';

const trajectory = spring({ keyframes: [0, 100], stiffness: 260, damping: 26 });
const mid = trajectory.next(150).value;
assert(mid > 0 && mid < 100);
assert.equal(trajectory.next(3000).value, 100);
assert(AnimateNumber, 'Premium React export must import');

const object = { x: 0, turn: 0 };
const timeline = gsap.timeline({ paused: true })
  .to(object, { x: 100, duration: 1, ease: 'none' })
  .to(object, { turn: 90, duration: 1, ease: 'none' });
timeline.seek(0.5);
assert.equal(object.x, 50);
timeline.seek(2);
assert.equal(object.x, 100);
assert.equal(object.turn, 90);
timeline.kill();
gsap.ticker.sleep();

const packagedPlugins = ['DrawSVGPlugin', 'MorphSVGPlugin', 'MotionPathPlugin', 'SplitText', 'ScrollTrigger'];
for (const name of packagedPlugins) assert(existsSync(`node_modules/gsap/${name}.js`));

const versions = Object.fromEntries(['motion', 'motion-plus', 'react', 'react-dom', 'vite', 'gsap']
  .map(name => [name, JSON.parse(readFileSync(`node_modules/${name}/package.json`, 'utf8')).version]));
console.log(JSON.stringify({ passed: ['Motion spring computation', 'Motion+ AnimateNumber module import', 'GSAP timeline midpoint/end + cleanup', 'Selected GSAP plugins present, not browser-imported'], versions }, null, 2));
